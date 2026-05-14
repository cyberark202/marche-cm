import logging
import hashlib
import hmac
import re
import secrets
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Q, Sum
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets

from apps.accounts.security import (
    has_action_permission,
    verify_sensitive_action_challenge,
    write_audit_log,
)
from apps.notifications.realtime import broadcast_event
from apps.notifications.service import create_realtime_notification
from apps.accounts.models import User, UserRole
from .notchpay_checkout_service import NotchPayCheckoutService
from .notchpay_service import NotchPayDisbursementService
from .models import (
    LedgerDirection,
    LedgerEntryType,
    PaymentProvider,
    TransactionStatus,
    Wallet,
    WalletTransaction,
    WalletWebhookEvent,
)
from .payout_retry import enqueue_payout_retry, mark_payout_retry_success
from .services import WalletAccountingService
from .serializers import WalletSerializer, WalletTransactionSerializer

logger = logging.getLogger(__name__)


class WalletViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = WalletSerializer
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "wallet"

    def get_queryset(self):
        Wallet.objects.get_or_create(owner=self.request.user)
        return Wallet.objects.filter(owner=self.request.user).select_related("owner")

    def _parse_amount(self, raw):
        try:
            amount = Decimal(str(raw))
        except (InvalidOperation, TypeError):
            return None
        if amount <= 0:
            return None
        return amount.quantize(Decimal("0.01"))

    def _parse_phone(self, raw):
        phone = "".join(ch for ch in str(raw or "") if ch.isdigit() or ch == "+")
        if not phone.startswith("+"):
            return None
        digits = phone[1:]
        if not digits.isdigit() or len(digits) < 8:
            return None
        return f"+{digits}"

    def _parse_email(self, raw):
        email = str(raw or "").strip().lower()
        if re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email):
            return email
        return None

    def _parse_card_reference(self, raw):
        digits = "".join(ch for ch in str(raw or "") if ch.isdigit())
        if 12 <= len(digits) <= 19:
            return digits
        return None

    def _parse_provider(self, raw, *, requires_withdraw_mode: bool = False):
        provider = (str(raw or "MOBILE_MONEY")).strip().upper()
        allowed = {
            PaymentProvider.MOBILE_MONEY,
            PaymentProvider.ORANGE_MONEY,
            PaymentProvider.VISA,
            PaymentProvider.MASTERCARD,
            PaymentProvider.PAYPAL,
        }
        if provider not in allowed:
            return None
        if settings.NOTCHPAY_ENABLED and settings.NOTCHPAY_ONLY_MTN and provider != PaymentProvider.MOBILE_MONEY:
            return None
        if requires_withdraw_mode and settings.NOTCHPAY_ENABLED and not NotchPayDisbursementService.withdraw_channel_for(provider):
            return None
        return provider

    def _provider_error_detail(self, raw, *, requires_withdraw_mode: bool = False):
        provider = (str(raw or "MOBILE_MONEY")).strip().upper()
        allowed = {
            PaymentProvider.MOBILE_MONEY,
            PaymentProvider.ORANGE_MONEY,
            PaymentProvider.VISA,
            PaymentProvider.MASTERCARD,
            PaymentProvider.PAYPAL,
        }
        if provider not in allowed:
            return "Moyen de paiement invalide. Choisissez: MOBILE_MONEY, ORANGE_MONEY, VISA, MASTERCARD ou PAYPAL."
        if settings.NOTCHPAY_ENABLED and settings.NOTCHPAY_ONLY_MTN and provider != PaymentProvider.MOBILE_MONEY:
            return "Moyen indisponible: le serveur est configure en mode MTN uniquement."
        if requires_withdraw_mode and settings.NOTCHPAY_ENABLED and not NotchPayDisbursementService.withdraw_channel_for(provider):
            return f"Retrait via {provider} non configure. Contactez l'administrateur."
        return "Moyen de paiement invalide."

    def _parse_account_identifier(self, provider: str, raw):
        if provider in {PaymentProvider.MOBILE_MONEY, PaymentProvider.ORANGE_MONEY}:
            return self._parse_phone(raw)
        if provider in {PaymentProvider.VISA, PaymentProvider.MASTERCARD}:
            return self._parse_card_reference(raw)
        if provider == PaymentProvider.PAYPAL:
            return self._parse_email(raw)
        return None

    def _invalid_account_detail(self, provider: str, *, source: bool):
        origin = "source" if source else "destinataire"
        if provider in {PaymentProvider.MOBILE_MONEY, PaymentProvider.ORANGE_MONEY}:
            return f"Numero {origin} invalide. Format attendu: +2376XXXXXXXX."
        if provider in {PaymentProvider.VISA, PaymentProvider.MASTERCARD}:
            return f"Reference carte {origin} invalide. Entrez entre 12 et 19 chiffres."
        if provider == PaymentProvider.PAYPAL:
            return f"Email PayPal {origin} invalide."
        return "Identifiant de compte invalide."

    def _extract_checkout_url(self, reference: str) -> str | None:
        if not reference:
            return None
        if reference.startswith("http"):
            return reference.strip() or None
        if reference.startswith("checkout_url:"):
            raw = reference[len("checkout_url:") :]
            if ";tx_ref:" in raw:
                raw = raw.split(";tx_ref:", 1)[0]
            return raw.strip() or None
        return None

    def _parse_notchpay_event(self, payload) -> dict:
        if not isinstance(payload, dict):
            return {}
        event_type = str(payload.get("type") or "").strip().lower()
        raw_data = payload.get("data")
        if event_type and isinstance(raw_data, dict):
            return {
                "id": str(payload.get("id") or payload.get("event_id") or "").strip(),
                "type": event_type,
                "data": raw_data,
            }

        # Legacy PayDunya-style payload support (transitional compatibility).
        if isinstance(raw_data, dict):
            return {
                "id": str(raw_data.get("event_id") or payload.get("event_id") or "").strip(),
                "type": str(raw_data.get("status") or event_type or "").strip().lower(),
                "data": raw_data,
            }

        parsed: dict = {}
        for key, value in payload.items():
            if not str(key).startswith("data["):
                continue
            parts = re.findall(r"\[([^\]]+)\]", str(key))
            if not parts:
                continue
            cursor = parsed
            for part in parts[:-1]:
                if part not in cursor or not isinstance(cursor[part], dict):
                    cursor[part] = {}
                cursor = cursor[part]
            cursor[parts[-1]] = value
        if not parsed:
            return {}
        return {
            "id": str(parsed.get("event_id") or payload.get("event_id") or "").strip(),
            "type": str(parsed.get("status") or event_type or "").strip().lower(),
            "data": parsed,
        }

    def _verify_checkout_webhook_auth(self, request) -> tuple[bool, str]:
        expected_token = str(getattr(settings, "NOTCHPAY_WEBHOOK_TOKEN", "") or "").strip()
        incoming_token = (
            request.headers.get("X-NotchPay-Token")
            or request.headers.get("X-Notch-Token")
            or request.headers.get("X-Paydunya-Token")
            or request.query_params.get("token")
            or (request.data.get("token") if isinstance(request.data, dict) else "")
            or ""
        ).strip()
        if expected_token and not hmac.compare_digest(incoming_token, expected_token):
            return False, "Webhook token invalide."

        shared_secret = str(getattr(settings, "NOTCHPAY_CHECKOUT_WEBHOOK_SECRET", "") or "").strip()
        if shared_secret:
            incoming_signature = (
                request.headers.get("X-Notch-Signature")
                or request.headers.get("X-NotchPay-Signature")
                or request.headers.get("X-Paydunya-Signature")
                or ""
            ).strip()
            computed = hmac.new(shared_secret.encode("utf-8"), request.body or b"", hashlib.sha256).hexdigest()
            if not incoming_signature or not hmac.compare_digest(incoming_signature.lower(), computed.lower()):
                return False, "Signature webhook invalide."
            return True, ""

        if not expected_token:
            return False, "Aucun mecanisme de signature webhook configure."
        # Mode token-only: tolere uniquement hors production pour faciliter
        # le developpement local. En prod, exiger NOTCHPAY_CHECKOUT_WEBHOOK_SECRET.
        if not getattr(settings, "DEBUG", False):
            return False, "La signature HMAC est obligatoire en production (NOTCHPAY_CHECKOUT_WEBHOOK_SECRET)."
        return True, ""

    def _verify_disburse_webhook_auth(self, request) -> tuple[bool, str]:
        expected_token = str(getattr(settings, "NOTCHPAY_WEBHOOK_TOKEN", "") or "").strip()
        incoming_token = (
            request.headers.get("X-NotchPay-Token")
            or request.headers.get("X-Notch-Token")
            or request.headers.get("X-Paydunya-Token")
            or request.query_params.get("token")
            or (request.data.get("token") if isinstance(request.data, dict) else "")
            or ""
        ).strip()
        if expected_token and not hmac.compare_digest(incoming_token, expected_token):
            return False, "Webhook token invalide."

        shared_secret = str(getattr(settings, "NOTCHPAY_DISBURSE_WEBHOOK_SECRET", "") or "").strip()
        if shared_secret:
            incoming_signature = (
                request.headers.get("X-Notch-Signature")
                or request.headers.get("X-NotchPay-Signature")
                or request.headers.get("X-Paydunya-Signature")
                or ""
            ).strip()
            computed = hmac.new(shared_secret.encode("utf-8"), request.body or b"", hashlib.sha256).hexdigest()
            if not incoming_signature or not hmac.compare_digest(incoming_signature.lower(), computed.lower()):
                return False, "Signature webhook invalide."
            return True, ""

        if not expected_token:
            return False, "Aucun mecanisme d'auth webhook configure."
        if not getattr(settings, "DEBUG", False):
            return False, "La signature HMAC est obligatoire en production (NOTCHPAY_DISBURSE_WEBHOOK_SECRET)."
        return True, ""

    def _require_wallet_action(self, request, action_key):
        if not has_action_permission(request.user, action_key):
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        return None

    def _enforce_kyc_limits(self, request, amount):
        profile = settings.KYC_LIMITS.get(getattr(request.user, "kyc_level", 0), settings.KYC_LIMITS[0])
        if amount > Decimal(str(profile["per_transaction"])):
            return response.Response(
                {"detail": f"Limite KYC par transaction depassee ({profile['per_transaction']})."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        day_start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        wallet, _ = Wallet.objects.get_or_create(owner=request.user)
        day_total = (
            wallet.transactions.filter(
                status=TransactionStatus.SUCCESS,
                kind__in=["TOPUP", "WITHDRAWAL"],
                created_at__gte=day_start,
            ).aggregate(value=Sum("amount"))["value"]
            or Decimal("0")
        )
        if abs(day_total) + amount > Decimal(str(profile["per_day"])):
            return response.Response(
                {"detail": f"Limite KYC journaliere depassee ({profile['per_day']})."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return None

    def _validate_wallet_security(self, request, amount, purpose):
        if purpose == "WITHDRAW":
            verified, message = verify_sensitive_action_challenge(
                user=request.user,
                action_key="wallet.withdraw",
                challenge_token=str(request.data.get("challenge_token") or ""),
                verification_code=str(request.data.get("verification_code") or ""),
            )
            if not verified:
                return response.Response({"detail": message}, status=status.HTTP_403_FORBIDDEN)
        request.user.refresh_from_db(fields=["wallet_pin_hash", "wallet_pin_failed_attempts", "wallet_pin_locked_until"])
        if request.user.is_wallet_pin_locked():
            remaining_seconds = int((request.user.wallet_pin_locked_until - timezone.now()).total_seconds())
            remaining_minutes = max(1, (remaining_seconds + 59) // 60)
            return response.Response(
                {
                    "detail": (
                        f"PIN wallet temporairement bloque apres plusieurs erreurs. "
                        f"Reessayez dans {remaining_minutes} minute(s)."
                    )
                },
                status=status.HTTP_423_LOCKED,
            )
        pin = str(request.data.get("pin") or "").strip()
        if len(pin) != 4 or not pin.isdigit():
            return response.Response({"detail": "PIN wallet invalide (4 chiffres requis)."}, status=status.HTTP_400_BAD_REQUEST)
        if not request.user.check_wallet_pin(pin):
            locked = request.user.register_wallet_pin_failure(
                max_attempts=settings.WALLET_PIN_MAX_ATTEMPTS,
                lock_minutes=settings.WALLET_PIN_LOCK_MINUTES,
            )
            if locked:
                return response.Response(
                    {
                        "detail": (
                            f"PIN wallet bloque pendant {settings.WALLET_PIN_LOCK_MINUTES} minute(s) "
                            f"apres trop de tentatives."
                        )
                    },
                    status=status.HTTP_423_LOCKED,
                )
            remaining_attempts = max(0, settings.WALLET_PIN_MAX_ATTEMPTS - request.user.wallet_pin_failed_attempts)
            return response.Response(
                {"detail": f"PIN wallet invalide. Tentatives restantes: {remaining_attempts}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        request.user.reset_wallet_pin_failures()
        return None

    @decorators.action(detail=False, methods=["post"])
    def request_otp(self, request):
        return response.Response(
            {"detail": "OTP desactive. Utilisez uniquement le PIN wallet."},
            status=status.HTTP_410_GONE,
        )

    @decorators.action(detail=False, methods=["post"])
    def topup(self, request):
        authz = self._require_wallet_action(request, "wallet.topup")
        if authz is not None:
            return authz

        amount = self._parse_amount(request.data.get("amount"))
        provider = self._parse_provider(request.data.get("provider"), requires_withdraw_mode=False)
        source_raw = request.data.get("source_account")
        if source_raw in {None, ""}:
            source_raw = request.data.get("source_phone")
        source_account = self._parse_account_identifier(str(provider or ""), source_raw)
        if amount is None:
            return response.Response({"detail": "Montant invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if provider is None:
            return response.Response(
                {"detail": self._provider_error_detail(request.data.get("provider"), requires_withdraw_mode=False)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if source_account is None:
            return response.Response(
                {"detail": self._invalid_account_detail(provider, source=True)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if settings.NOTCHPAY_ENABLED and amount != amount.to_integral_value():
            return response.Response(
                {"detail": "Montant invalide: NotchPay requiert un entier (FCFA)."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        limit_error = self._enforce_kyc_limits(request, amount)
        if limit_error:
            return limit_error
        security_error = self._validate_wallet_security(request, amount, "TOPUP")
        if security_error:
            return security_error

        idempotency_key = request.headers.get("Idempotency-Key") or str(request.data.get("idempotency_key") or "").strip()
        external_tx = f"WALLET-{secrets.token_hex(8)}"
        with transaction.atomic():
            wallet, _ = Wallet.objects.select_for_update().get_or_create(owner=request.user)
            if idempotency_key:
                existing = wallet.transactions.filter(idempotency_key=idempotency_key).first()
                if existing:
                    checkout_url = self._extract_checkout_url(existing.reference)
                    return response.Response(
                        {
                            "detail": "Requete idempotente deja traitee.",
                            "transaction_id": existing.external_transaction_id,
                            "status": existing.status,
                            "checkout_url": checkout_url,
                        },
                        status=status.HTTP_200_OK,
                    )
            tx = wallet.transactions.create(
                amount=amount,
                kind="TOPUP",
                provider=provider,
                status=TransactionStatus.PENDING,
                idempotency_key=idempotency_key,
                external_transaction_id=external_tx,
                reference=f"topup:{provider}:{source_account}:tx:{external_tx}",
            )
        checkout = NotchPayCheckoutService.create_invoice(
            amount=amount,
            description=f"Recharge wallet {request.user.username}",
            tx_ref=external_tx,
            customer_name=request.user.get_full_name() or request.user.username,
            customer_email=request.user.email,
        )

        if checkout.get("error"):
            self._mark_transaction_failed(tx=tx, reason=str(checkout["error"]))
            return response.Response(
                {"detail": "Echec NotchPay.", "error": checkout["error"]},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        if checkout.get("mode") == "SIMULATED":
            self._mark_transaction_success(tx=tx, payload={"mode": "SIMULATED"}, mark_payout=True)
        else:
            checkout_reference = str(checkout.get("reference") or tx.external_transaction_id).strip()
            provider_transaction_id = str(
                checkout.get("provider_transaction_id")
                or checkout.get("invoice_token")
                or ""
            ).strip()
            checkout_url = checkout.get("checkout_url", "")
            update_fields = ["reference", "updated_at"]
            if checkout_reference and checkout_reference != tx.external_transaction_id:
                tx.external_transaction_id = checkout_reference
                update_fields.append("external_transaction_id")
            if provider_transaction_id:
                tx.metadata = {**(tx.metadata or {}), "notchpay_payment_id": provider_transaction_id}
                update_fields.append("metadata")
            ref = f"checkout_url:{checkout_url};tx_ref:{external_tx}"
            if len(ref) > 120:
                ref = checkout_url[:120]
            tx.reference = ref
            tx.save(update_fields=update_fields)

        write_audit_log(
            actor=request.user,
            action="Demande recharge wallet",
            action_key="wallet.topup",
            metadata={"tx": tx.external_transaction_id, "amount": str(amount), "provider": provider},
        )
        return response.Response(
            {
                "detail": "Paiement initie.",
                "transaction_id": tx.external_transaction_id,
                "mode": checkout.get("mode", "LIVE"),
                "checkout_url": checkout.get("checkout_url"),
                "status": tx.status,
            }
        )

    @decorators.action(detail=False, methods=["post"])
    def withdraw(self, request):
        authz = self._require_wallet_action(request, "wallet.withdraw")
        if authz is not None:
            return authz

        amount = self._parse_amount(request.data.get("amount"))
        provider = self._parse_provider(request.data.get("provider"), requires_withdraw_mode=True)
        destination_raw = request.data.get("destination_account")
        if destination_raw in {None, ""}:
            destination_raw = request.data.get("destination_phone")
        destination_account = self._parse_account_identifier(str(provider or ""), destination_raw)
        if amount is None:
            return response.Response({"detail": "Montant invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if provider is None:
            return response.Response(
                {"detail": self._provider_error_detail(request.data.get("provider"), requires_withdraw_mode=True)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if destination_account is None:
            return response.Response(
                {"detail": self._invalid_account_detail(provider, source=False)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        limit_error = self._enforce_kyc_limits(request, amount)
        if limit_error:
            return limit_error
        security_error = self._validate_wallet_security(request, amount, "WITHDRAW")
        if security_error:
            return security_error

        idempotency_key = request.headers.get("Idempotency-Key") or str(request.data.get("idempotency_key") or "").strip()
        external_tx = f"WALLET-{secrets.token_hex(8)}"

        with transaction.atomic():
            wallet, _ = Wallet.objects.select_for_update().get_or_create(owner=request.user)
            if idempotency_key:
                existing = wallet.transactions.filter(idempotency_key=idempotency_key).first()
                if existing:
                    return response.Response(
                        {
                            "detail": "Requete idempotente deja traitee.",
                            "transaction_id": existing.external_transaction_id,
                            "status": existing.status,
                        },
                        status=status.HTTP_200_OK,
                    )
            if wallet.available_balance < amount:
                return response.Response({"detail": "Solde insuffisant."}, status=status.HTTP_400_BAD_REQUEST)
            WalletAccountingService.mutate_wallet(
                wallet=wallet,
                amount=amount,
                entry_type=LedgerEntryType.WITHDRAWAL,
                direction=LedgerDirection.DEBIT,
                available_delta=-amount,
                pending_delta=amount,
                reference=f"wallet-withdraw-init:{external_tx}",
                idempotency_key=f"withdraw-init:{idempotency_key or external_tx}",
                created_by=request.user,
                metadata={"provider": provider},
            )
            tx = wallet.transactions.create(
                amount=-amount,
                kind="WITHDRAWAL",
                provider=provider,
                status=TransactionStatus.PENDING,
                idempotency_key=idempotency_key,
                external_transaction_id=external_tx,
                reference=f"withdraw:{provider}:{destination_account}:tx:{external_tx}",
            )

        disburse_id = f"WITHDRAW-{tx.id}"
        transfer = NotchPayDisbursementService.send_money(
            amount=amount,
            account_alias=destination_account,
            provider=provider,
            transaction_id=disburse_id,
            account_name=request.user.get_full_name() or request.user.username,
        )
        if transfer.get("error"):
            self._mark_transaction_failed(tx=tx, reason=str(transfer["error"]))
            return response.Response(
                {"detail": "Echec NotchPay.", "error": transfer["error"]},
                status=status.HTTP_502_BAD_GATEWAY,
            )
        if transfer["mode"] == "SIMULATED":
            self._mark_transaction_success(tx=tx, payload={"mode": "SIMULATED"}, mark_payout=True)
        write_audit_log(
            actor=request.user,
            action="Demande retrait wallet",
            action_key="wallet.withdraw",
            metadata={"tx": tx.external_transaction_id, "amount": str(amount), "provider": provider},
        )
        return response.Response(
            {
                "detail": "Retrait initie.",
                "transaction_id": transfer["transaction_id"],
                "mode": transfer["mode"],
                "status": tx.status,
            }
        )

    def _mark_transaction_success(self, *, tx: WalletTransaction, payload: dict, mark_payout: bool | None = None):
        with transaction.atomic():
            tx = WalletTransaction.objects.select_for_update().select_related("wallet").get(id=tx.id)
            if tx.status == TransactionStatus.SUCCESS:
                return tx
            if tx.status == TransactionStatus.FAILED:
                return tx
            wallet = tx.wallet
            if tx.kind == "TOPUP":
                WalletAccountingService.credit_available(
                    wallet=wallet,
                    amount=abs(tx.amount),
                    entry_type=LedgerEntryType.DEPOSIT,
                    reference=f"wallet-topup-success:{tx.external_transaction_id or tx.id}",
                    idempotency_key=f"tx-success:{tx.id}",
                    created_by=wallet.owner,
                    metadata={"provider_payload": payload},
                )
            elif tx.kind == "WITHDRAWAL":
                amount = abs(tx.amount)
                WalletAccountingService.mutate_wallet(
                    wallet=wallet,
                    amount=amount,
                    entry_type=LedgerEntryType.PAYOUT,
                    direction=LedgerDirection.DEBIT,
                    pending_delta=-amount,
                    reference=f"wallet-withdraw-success:{tx.external_transaction_id or tx.id}",
                    idempotency_key=f"tx-success:{tx.id}",
                    created_by=wallet.owner,
                    metadata={"provider_payload": payload},
                )
            elif tx.kind.startswith("PAYOUT_"):
                mark_payout_retry_success(tx=tx)
                try:
                    from apps.orders.services import OrderFinanceService

                    OrderFinanceService.finalize_payout_success(tx=tx, actor=None)
                except Exception as exc:
                    write_audit_log(
                        actor=tx.wallet.owner,
                        action="Echec finalisation payout",
                        action_key="orders.payout.success",
                        metadata={"transaction_id": tx.external_transaction_id, "error": str(type(exc).__name__)},
                    )
                    logger.exception("Echec finalisation payout tx=%s", tx.id)
                    raise
            tx.status = TransactionStatus.SUCCESS
            tx.reconciled_at = timezone.now()
            tx.failure_reason = ""
            update_fields = ["status", "reconciled_at", "failure_reason", "updated_at"]
            if mark_payout is not None:
                tx.cinetpay_transfered = mark_payout
                update_fields.append("cinetpay_transfered")
            tx.save(update_fields=update_fields)
        broadcast_event("wallets", "transaction_success", {"transaction_id": tx.external_transaction_id, "kind": tx.kind})
        write_audit_log(
            actor=tx.wallet.owner,
            action="Transaction wallet succes",
            action_key="wallet.transaction.success",
            metadata={"transaction_id": tx.external_transaction_id, "kind": tx.kind},
        )
        return tx

    def _notify_wallet_incident(self, *, tx: WalletTransaction, title: str, body: str):
        try:
            create_realtime_notification(
                user=tx.wallet.owner,
                title=title,
                body=body,
                payload={"transaction_id": tx.external_transaction_id, "kind": tx.kind},
            )
        except Exception:
            pass
        admins = User.objects.filter(Q(role=UserRole.GENERAL_ADMIN) | Q(is_superuser=True), is_active=True).distinct()
        for admin in admins:
            try:
                create_realtime_notification(
                    user=admin,
                    title=f"[Alerte wallet] {title}",
                    body=body,
                    payload={"transaction_id": tx.external_transaction_id, "owner_id": tx.wallet.owner_id},
                )
            except Exception:
                continue

    def _mark_transaction_failed(self, *, tx: WalletTransaction, reason: str):
        should_rollback_failed_payout = False
        with transaction.atomic():
            tx = WalletTransaction.objects.select_for_update().select_related("wallet").get(id=tx.id)
            if tx.status == TransactionStatus.FAILED:
                return tx
            if tx.status == TransactionStatus.SUCCESS:
                return tx
            wallet = tx.wallet
            if tx.kind == "WITHDRAWAL":
                amount = abs(tx.amount)
                WalletAccountingService.mutate_wallet(
                    wallet=wallet,
                    amount=amount,
                    entry_type=LedgerEntryType.REFUND,
                    direction=LedgerDirection.CREDIT,
                    available_delta=amount,
                    pending_delta=-amount,
                    reference=f"wallet-withdraw-failed:{tx.external_transaction_id or tx.id}",
                    idempotency_key=f"tx-failed:{tx.id}",
                    created_by=wallet.owner,
                    metadata={"reason": reason},
                )
            elif tx.kind.startswith("PAYOUT_"):
                retry_job = enqueue_payout_retry(tx=tx, error=reason, delay_seconds=180)
                if retry_job is not None:
                    tx.status = TransactionStatus.PENDING
                else:
                    tx.status = TransactionStatus.FAILED
                    should_rollback_failed_payout = True
            else:
                tx.status = TransactionStatus.FAILED
            tx.failure_reason = reason[:240]
            update_fields = ["status", "failure_reason", "updated_at"]
            if tx.status == TransactionStatus.FAILED:
                tx.reconciled_at = timezone.now()
                update_fields.append("reconciled_at")
            tx.save(update_fields=update_fields)

        if tx.kind.startswith("PAYOUT_") and should_rollback_failed_payout:
            try:
                from apps.orders.services import OrderFinanceService

                OrderFinanceService.rollback_failed_payout(tx=tx, reason=reason, actor=None)
            except Exception:
                logger.exception("Rollback payout echoue tx=%s", tx.id)
                write_audit_log(
                    actor=tx.wallet.owner,
                    action="Rollback payout echoue",
                    action_key="orders.payout.rollback.failed",
                    metadata={"transaction_id": tx.external_transaction_id, "reason": reason},
                )

        broadcast_event("wallets", "transaction_failed", {"transaction_id": tx.external_transaction_id, "reason": tx.failure_reason})
        self._notify_wallet_incident(
            tx=tx,
            title="Transaction wallet echouee",
            body=f"{tx.kind} - raison: {tx.failure_reason}",
        )
        write_audit_log(
            actor=tx.wallet.owner,
            action="Transaction wallet echouee",
            action_key="wallet.transaction.failed",
            metadata={"transaction_id": tx.external_transaction_id, "reason": tx.failure_reason},
        )
        return tx

    def _mark_payout_completed(self, *, tx: WalletTransaction):
        if tx.cinetpay_transfered:
            return
        tx.cinetpay_transfered = True
        tx.save(update_fields=["cinetpay_transfered", "updated_at"])

    def _trigger_auto_payout(self, *, tx: WalletTransaction):
        if not settings.NOTCHPAY_AUTO_PAYOUT:
            return
        if tx.kind != "TOPUP":
            return
        if tx.cinetpay_transfered:
            return
        tx.cinetpay_transfered = True
        tx.save(update_fields=["cinetpay_transfered", "updated_at"])
        disburse_id = f"TOPUP-PAYOUT-{tx.id}"
        payout = NotchPayDisbursementService.send_money(
            amount=abs(tx.amount),
            phone=settings.NOTCHPAY_MTN_NUMBER,
            provider=PaymentProvider.MOBILE_MONEY,
            transaction_id=disburse_id,
            account_name=settings.NOTCHPAY_STORE_NAME or "Marche CM",
        )
        if payout.get("error"):
            tx.cinetpay_transfered = False
            tx.save(update_fields=["cinetpay_transfered", "updated_at"])
            self._notify_wallet_incident(
                tx=tx,
                title="Payout automatique echoue",
                body=f"Erreur payout: {payout['error']}",
            )
            write_audit_log(
                actor=tx.wallet.owner,
                action="Echec payout automatique",
                action_key="wallet.payout.failed",
                metadata={"tx": tx.external_transaction_id, "error": payout["error"]},
            )
            return
        if payout.get("mode") == "SIMULATED":
            self._mark_payout_completed(tx=tx)

    @decorators.action(detail=False, methods=["post"], permission_classes=[permissions.AllowAny], url_path="notchpay/checkout/webhook")
    def notchpay_checkout_webhook(self, request):
        payload = request.data if isinstance(request.data, dict) else {}
        event_payload = self._parse_notchpay_event(payload)
        event_data = event_payload.get("data") if isinstance(event_payload.get("data"), dict) else {}
        if not event_data:
            return response.Response({"detail": "Payload NotchPay invalide."}, status=status.HTTP_400_BAD_REQUEST)

        is_valid, auth_error = self._verify_checkout_webhook_auth(request)
        if not is_valid:
            return response.Response({"detail": auth_error}, status=status.HTTP_403_FORBIDDEN)

        event_type = str(event_payload.get("type") or "").strip().lower()
        invoice_data = event_data.get("invoice") if isinstance(event_data.get("invoice"), dict) else {}
        reference = str(
            event_data.get("reference")
            or invoice_data.get("token")
            or event_data.get("token")
            or payload.get("reference")
            or payload.get("token")
            or ""
        ).strip()
        payment_id = str(event_data.get("id") or payload.get("id") or "").strip()
        status_value = str(event_data.get("status") or payload.get("status") or "").strip().lower()
        if not status_value and event_type.startswith("payment."):
            status_value = event_type.split(".", 1)[1]
        event_id = str(
            event_payload.get("id")
            or payload.get("event_id")
            or payload.get("id")
            or f"{reference or payment_id}:{event_type or status_value}"
        ).strip()

        if not reference and not payment_id:
            return response.Response({"detail": "reference manquante."}, status=status.HTTP_400_BAD_REQUEST)
        if not event_id:
            return response.Response({"detail": "event_id manquant."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            with transaction.atomic():
                event = WalletWebhookEvent.objects.create(
                    provider="NOTCHPAY_CHECKOUT",
                    event_id=event_id,
                    payload=request.data,
                    processed=False,
                )
        except IntegrityError:
            return response.Response({"detail": "Webhook deja traite (idempotent)."}, status=status.HTTP_200_OK)

        tx = None
        if reference:
            tx = WalletTransaction.objects.filter(external_transaction_id=reference).select_related("wallet__owner").first()
        if not tx and payment_id:
            tx = WalletTransaction.objects.filter(metadata__notchpay_payment_id=payment_id).select_related("wallet__owner").first()
        if not tx:
            event.processed = True
            event.processed_at = timezone.now()
            event.processing_error = "transaction_inconnue"
            event.save(update_fields=["processed", "processed_at", "processing_error"])
            write_audit_log(actor=None, action="Webhook checkout sans transaction", metadata={"reference": reference, "payment_id": payment_id})
            return response.Response({"detail": "Transaction inconnue."}, status=status.HTTP_404_NOT_FOUND)

        raw_amount = event_data.get("amount")
        if raw_amount in {None, ""}:
            raw_amount = invoice_data.get("total_amount")
        # Defense en profondeur: le montant doit toujours etre present et
        # correspondre exactement au montant de la transaction. On refuse les
        # webhooks sans champ amount pour prevenir la falsification.
        if raw_amount in {None, ""}:
            event.processed = True
            event.processed_at = timezone.now()
            event.processing_error = "montant_manquant"
            event.save(update_fields=["processed", "processed_at", "processing_error"])
            return response.Response({"detail": "Montant manquant dans le webhook."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            if Decimal(str(raw_amount)) != abs(tx.amount):
                event.processed = True
                event.processed_at = timezone.now()
                event.processing_error = "montant_non_conforme"
                event.save(update_fields=["processed", "processed_at", "processing_error"])
                return response.Response({"detail": "Montant non conforme."}, status=status.HTTP_400_BAD_REQUEST)
        except (InvalidOperation, TypeError):
            event.processed = True
            event.processed_at = timezone.now()
            event.processing_error = "montant_invalide"
            event.save(update_fields=["processed", "processed_at", "processing_error"])
            return response.Response({"detail": "Montant invalide."}, status=status.HTTP_400_BAD_REQUEST)

        if payment_id and (tx.metadata or {}).get("notchpay_payment_id") != payment_id:
            tx.metadata = {**(tx.metadata or {}), "notchpay_payment_id": payment_id}
            tx.save(update_fields=["metadata", "updated_at"])

        is_success = event_type == "payment.complete" or status_value in {"complete", "completed", "paid", "success"}
        is_failure = event_type in {"payment.failed", "payment.canceled", "payment.cancelled", "payment.expired"} or status_value in {
            "failed",
            "error",
            "canceled",
            "cancelled",
            "expired",
        }
        if is_success:
            self._mark_transaction_success(tx=tx, payload=request.data, mark_payout=None)
            self._trigger_auto_payout(tx=tx)
        elif is_failure:
            self._mark_transaction_failed(tx=tx, reason=f"status={status_value or event_type}")

        event.processed = True
        event.processed_at = timezone.now()
        event.processing_error = ""
        event.save(update_fields=["processed", "processed_at", "processing_error"])
        return response.Response({"detail": "Webhook traite."}, status=status.HTTP_200_OK)

    @decorators.action(detail=False, methods=["post"], permission_classes=[permissions.AllowAny], url_path="paydunya/checkout/webhook")
    def paydunya_checkout_webhook(self, request):
        return self.notchpay_checkout_webhook(request)

    @decorators.action(detail=False, methods=["post"], permission_classes=[permissions.AllowAny], url_path="notchpay/disburse/webhook")
    def notchpay_disburse_webhook(self, request):
        is_valid, auth_error = self._verify_disburse_webhook_auth(request)
        if not is_valid:
            return response.Response({"detail": auth_error}, status=status.HTTP_403_FORBIDDEN)

        payload = request.data if isinstance(request.data, dict) else {}
        event_payload = self._parse_notchpay_event(payload)
        data = event_payload.get("data") if isinstance(event_payload.get("data"), dict) else {}
        event_type = str(event_payload.get("type") or "").strip().lower()

        external_tx = str(
            data.get("reference")
            or payload.get("reference")
            or payload.get("disburse_id")
            or payload.get("transaction_id")
            or data.get("disburse_id")
            or data.get("transaction_id")
            or ""
        ).strip()
        provider_tx = str(
            data.get("id")
            or payload.get("id")
            or payload.get("transaction_id")
            or data.get("transaction_id")
            or ""
        ).strip()
        raw_status = str(
            data.get("status")
            or payload.get("status")
            or payload.get("response_code")
            or data.get("response_code")
            or ""
        ).strip().lower()
        if not raw_status and event_type.startswith("transfer."):
            raw_status = event_type.split(".", 1)[1]

        event_id = str(
            event_payload.get("id")
            or payload.get("event_id")
            or payload.get("id")
            or f"{external_tx}:{event_type or raw_status}:{provider_tx}"
        ).strip()
        if not external_tx:
            return response.Response({"detail": "reference manquante."}, status=status.HTTP_400_BAD_REQUEST)
        if not event_id:
            return response.Response({"detail": "event_id manquant."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            with transaction.atomic():
                event = WalletWebhookEvent.objects.create(
                    provider="NOTCHPAY_DISBURSE",
                    event_id=event_id,
                    payload=request.data,
                    processed=False,
                )
        except IntegrityError:
            return response.Response({"detail": "Webhook deja traite (idempotent)."}, status=status.HTTP_200_OK)

        tx = None
        if external_tx.startswith("WITHDRAW-"):
            tx_id = external_tx.split("WITHDRAW-", 1)[1]
            if tx_id.isdigit():
                tx = WalletTransaction.objects.filter(id=int(tx_id)).select_related("wallet__owner").first()
        elif external_tx.startswith("TOPUP-PAYOUT-"):
            tx_id = external_tx.split("TOPUP-PAYOUT-", 1)[1]
            if tx_id.isdigit():
                tx = WalletTransaction.objects.filter(id=int(tx_id)).select_related("wallet__owner").first()
        if not tx:
            tx = WalletTransaction.objects.filter(external_transaction_id=external_tx).select_related("wallet__owner").first()
        if not tx:
            event.processed = True
            event.processed_at = timezone.now()
            event.processing_error = "transaction_inconnue"
            event.save(update_fields=["processed", "processed_at", "processing_error"])
            write_audit_log(actor=None, action="Webhook disburse sans transaction", metadata={"external_tx": external_tx})
            return response.Response({"detail": "Transaction inconnue."}, status=status.HTTP_404_NOT_FOUND)

        is_success = event_type == "transfer.complete" or raw_status in {"complete", "completed", "success", "00"}
        is_failure = event_type == "transfer.failed" or raw_status in {"failed", "error", "canceled", "cancelled"}
        if external_tx.startswith("WITHDRAW-"):
            if is_success:
                self._mark_transaction_success(tx=tx, payload=request.data, mark_payout=True)
            elif is_failure:
                reason = str(
                    payload.get("response_text")
                    or payload.get("reason")
                    or payload.get("message")
                    or data.get("message")
                    or f"status={raw_status or event_type}"
                ).strip()
                self._mark_transaction_failed(tx=tx, reason=reason)
        elif external_tx.startswith("TOPUP-PAYOUT-"):
            if is_success:
                self._mark_payout_completed(tx=tx)
            elif is_failure:
                tx.cinetpay_transfered = False
                tx.save(update_fields=["cinetpay_transfered", "updated_at"])
                write_audit_log(
                    actor=tx.wallet.owner,
                    action="Payout automatique echoue",
                    action_key="wallet.payout.failed",
                    metadata={"tx": tx.external_transaction_id, "status": raw_status or event_type},
                )
        else:
            if is_success:
                self._mark_transaction_success(tx=tx, payload=request.data, mark_payout=True)
            elif is_failure:
                reason = str(
                    payload.get("response_text")
                    or payload.get("reason")
                    or payload.get("message")
                    or data.get("message")
                    or f"status={raw_status or event_type}"
                ).strip()
                self._mark_transaction_failed(tx=tx, reason=reason)

        event.processed = True
        event.processed_at = timezone.now()
        event.processing_error = ""
        event.save(update_fields=["processed", "processed_at", "processing_error"])
        return response.Response({"detail": "Webhook traite."}, status=status.HTTP_200_OK)

    @decorators.action(detail=False, methods=["post"], permission_classes=[permissions.AllowAny], url_path="paydunya/disburse/webhook")
    def paydunya_disburse_webhook(self, request):
        return self.notchpay_disburse_webhook(request)

    @decorators.action(detail=False, methods=["post"])
    def reconcile(self, request):
        if not has_action_permission(request.user, "wallet.reconcile"):
            return response.Response({"detail": "Action reservee aux administrateurs."}, status=status.HTTP_403_FORBIDDEN)
        tx_id = str(request.data.get("transaction_id") or "").strip()
        target_status = str(request.data.get("status") or "").strip().upper()
        reason = str(request.data.get("reason") or "Reconciliation manuelle").strip()
        tx = WalletTransaction.objects.filter(external_transaction_id=tx_id).first()
        if not tx:
            return response.Response({"detail": "Transaction introuvable."}, status=status.HTTP_404_NOT_FOUND)
        if tx.status != TransactionStatus.PENDING:
            return response.Response(
                {"detail": f"Reconciliation autorisee uniquement sur transaction PENDING (etat actuel={tx.status})."},
                status=status.HTTP_409_CONFLICT,
            )
        if target_status == TransactionStatus.SUCCESS:
            tx = self._mark_transaction_success(tx=tx, payload={"manual": True})
        elif target_status == TransactionStatus.FAILED:
            tx = self._mark_transaction_failed(tx=tx, reason=reason)
        else:
            return response.Response({"detail": "Status invalide (SUCCESS|FAILED)."}, status=status.HTTP_400_BAD_REQUEST)
        write_audit_log(
            actor=request.user,
            action="Reconciliation transaction wallet",
            action_key="wallet.reconcile",
            metadata={"transaction_id": tx.external_transaction_id, "status": tx.status},
        )
        return response.Response(WalletTransactionSerializer(tx).data, status=status.HTTP_200_OK)

    @decorators.action(detail=False, methods=["get"])
    def transactions(self, request):
        wallet, _ = Wallet.objects.get_or_create(owner=request.user)
        queryset = wallet.transactions.all()
        status_filter = str(request.query_params.get("status") or "").strip().upper()
        if status_filter in {TransactionStatus.PENDING, TransactionStatus.SUCCESS, TransactionStatus.FAILED}:
            queryset = queryset.filter(status=status_filter)
        try:
            page_size = min(max(int(request.query_params.get("limit", 40)), 1), 100)
        except (TypeError, ValueError):
            page_size = 40
        rows = queryset[:page_size]
        return response.Response(WalletTransactionSerializer(rows, many=True).data)
