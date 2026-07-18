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
from apps.appconfig.models import get_platform_setting
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
    WalletTransactionStateLog,
    WalletWebhookEvent,
)
from .payout_retry import enqueue_payout_retry, mark_payout_retry_success
from .services import WalletAccountingService
from .serializers import WalletSerializer, WalletTransactionSerializer
from .fraud import FraudEngine, RiskContext
from .idempotency_service import IdempotencyConflict, IdempotencyService

logger = logging.getLogger(__name__)
security_event_logger = logging.getLogger("security.events")


from config.middleware import _client_ip  # noqa: E402, F401


class WalletViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = WalletSerializer
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "wallet"

    def get_queryset(self):
        return Wallet.objects.filter(owner=self.request.user).select_related("owner")

    _MIN_TX_AMOUNT = Decimal("100")
    _MAX_TX_AMOUNT = Decimal("100000000")

    def _parse_amount(self, raw):
        try:
            amount = Decimal(str(raw))
        except (InvalidOperation, TypeError):
            return None
        if amount < self._MIN_TX_AMOUNT:
            return None
        if amount > self._MAX_TX_AMOUNT:
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
        """
        Extract a checkout URL from the reference field.

        M9 — Only returns HTTPS URLs.  Internal metadata embedded in the
        reference string (tx_ref, provider keys) is stripped before returning.
        Never returns non-HTTP values that could leak internal state.
        """
        if not reference:
            return None
        candidate: str | None = None
        if reference.startswith("https://") or reference.startswith("http://"):
            candidate = reference.strip() or None
        elif reference.startswith("checkout_url:"):
            raw = reference[len("checkout_url:"):]
            if ";tx_ref:" in raw:
                raw = raw.split(";tx_ref:", 1)[0]
            candidate = raw.strip() or None
        if candidate and ("://" in candidate):
            if not candidate.startswith("https://") and not getattr(settings, "DEBUG", False):
                return None
            return candidate
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


    @staticmethod
    def _compute_hmac(secret: str, body: bytes) -> str:
        return hmac.new(secret.encode("utf-8"), body or b"", hashlib.sha256).hexdigest()

    def _check_webhook_timestamp(self, request, endpoint: str) -> tuple[bool, str]:
        """Audit ref: [NEW-002] reject replays outside a 5-minute window.

        NotchPay can be configured to send X-Notch-Timestamp (epoch seconds).
        When present, we enforce |now - ts| <= WEBHOOK_TIMESTAMP_WINDOW. When
        absent, behaviour is governed by settings.WEBHOOK_REQUIRE_TIMESTAMP:
        production should set it to True after coordinating with the provider.
        """
        import time as _time

        window = int(getattr(settings, "WEBHOOK_TIMESTAMP_WINDOW_SECONDS", 300))
        require = bool(getattr(settings, "WEBHOOK_REQUIRE_TIMESTAMP", False))
        raw = (
            request.headers.get("X-Notch-Timestamp")
            or request.headers.get("X-NotchPay-Timestamp")
            or ""
        ).strip()
        if not raw:
            if require:
                security_event_logger.warning(
                    "webhook_missing_timestamp endpoint=%s ip=%s", endpoint, _client_ip(request),
                )
                return False, "Webhook timestamp manquant."
            return True, ""
        try:
            ts = int(raw)
        except (TypeError, ValueError):
            return False, "Webhook timestamp invalide."
        if abs(int(_time.time()) - ts) > window:
            security_event_logger.warning(
                "webhook_timestamp_out_of_window endpoint=%s ip=%s delta=%s",
                endpoint, _client_ip(request), abs(int(_time.time()) - ts),
            )
            return False, "Webhook timestamp hors fenetre."
        return True, ""

    def _verify_webhook_auth(self, request, endpoint: str, secret_setting: str) -> tuple[bool, str]:
        shared_secret = str(getattr(settings, secret_setting, "") or "").strip()
        if not shared_secret:
            security_event_logger.error(
                "webhook_auth_misconfigured endpoint=%s ip=%s — %s not set, request rejected",
                endpoint, _client_ip(request), secret_setting,
            )
            return False, "Signature HMAC webhook non configuree. Contactez l'administrateur."

        ts_ok, ts_err = self._check_webhook_timestamp(request, endpoint)
        if not ts_ok:
            return False, ts_err

        incoming_sig = (
            request.headers.get("X-Notch-Signature")
            or request.headers.get("X-NotchPay-Signature")
            or request.headers.get("X-Paydunya-Signature")
            or ""
        ).strip()
        if not incoming_sig:
            security_event_logger.warning(
                "webhook_missing_signature endpoint=%s ip=%s", endpoint, _client_ip(request)
            )
            return False, "Signature HMAC manquante."

        computed = self._compute_hmac(shared_secret, request.body)
        if not hmac.compare_digest(incoming_sig.lower(), computed.lower()):
            security_event_logger.warning(
                "webhook_invalid_signature endpoint=%s ip=%s", endpoint, _client_ip(request)
            )
            return False, "Signature HMAC invalide."

        expected_token = str(getattr(settings, "NOTCHPAY_WEBHOOK_TOKEN", "") or "").strip()
        if expected_token:
            incoming_token = (
                request.headers.get("X-NotchPay-Token")
                or request.headers.get("X-Notch-Token")
                or ""
            ).strip()
            if not hmac.compare_digest(incoming_token, expected_token):
                security_event_logger.warning(
                    "webhook_invalid_token endpoint=%s ip=%s", endpoint, _client_ip(request)
                )
                return False, "Webhook token invalide."

        return True, ""

    def _require_wallet_action(self, request, action_key):
        if not has_action_permission(request.user, action_key):
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        return None

    _DEBIT_ACTIONS = frozenset({"withdraw", "transfer", "payout", "release", "order", "escrow_lock"})

    def _check_fraud(self, request, amount, action: str):
        """Evaluate fraud risk. Returns a Response if blocked, None to proceed."""
        ctx = RiskContext(
            user_id=request.user.id,
            amount=amount,
            action=action,
            ip=request.META.get("REMOTE_ADDR", ""),
            user_agent=request.META.get("HTTP_USER_AGENT", ""),
            device_id=request.headers.get("X-Device-Id", ""),
        )
        try:
            decision = FraudEngine.evaluate(ctx, request.user)
        except Exception:
            logger.exception("fraud_engine_error user=%d action=%s", request.user.id, action)
            if action in self._DEBIT_ACTIONS:
                try:
                    from apps.accounts.security import write_audit_log
                    write_audit_log(
                        actor=request.user,
                        action="fraud_engine_unavailable_blocked",
                        action_key="wallet.fraud.fail_closed",
                        metadata={"flow": action, "amount": str(amount)},
                    )
                except Exception:
                    logger.exception("fraud_fail_closed_audit_log_failed user=%d action=%s", request.user.id, action)
                return response.Response(
                    {"detail": "Service de securite indisponible. Reessayez dans quelques instants."},
                    status=status.HTTP_503_SERVICE_UNAVAILABLE,
                )
            return None
        if decision.is_blocked:
            logger.warning(
                "fraud_block user=%d action=%s score=%d reasons=%s",
                request.user.id,
                action,
                decision.score,
                ",".join(decision.reasons),
            )
            return response.Response(
                {"detail": "Transaction bloquee pour raisons de securite. Contactez le support."},
                status=status.HTTP_403_FORBIDDEN,
            )
        return None

    @staticmethod
    def _log_state_transition(
        tx,
        *,
        from_status: str,
        to_status: str,
        extended_status: str = "",
        reason: str = "",
        actor_id: int | None = None,
    ) -> None:
        """Append an immutable state transition log entry. Never raises."""
        try:
            WalletTransactionStateLog.objects.create(
                transaction=tx,
                from_status=from_status,
                to_status=to_status,
                extended_status=extended_status,
                reason=reason[:240],
                actor_id=actor_id,
                metadata={"kind": tx.kind, "amount": str(tx.amount)},
            )
        except Exception:
            logger.exception("state_log_failed tx_id=%s", getattr(tx, "id", None))

    def _enforce_kyc_limits(self, request, amount, *, kind: str):
        """Limites par opération selon le niveau KYC (docs 03/05/06).

        `kind` vaut "deposit" ou "withdraw" — le doc fixe des plafonds
        distincts (niveau 0 : dépôt <= 50 000, retrait <= 100 000 FCFA).
        Les plafonds sont configurables à chaud (clé "kyc.limits").
        """
        limits_map = get_platform_setting("kyc.limits")
        level = str(getattr(request.user, "kyc_level", 0))
        profile = limits_map.get(level)
        if profile is None:
            profile = limits_map[max(limits_map, key=int)]
        per_tx_key = "deposit_per_tx" if kind == "deposit" else "withdraw_per_tx"
        per_tx_limit = Decimal(str(profile[per_tx_key]))
        if amount > per_tx_limit:
            return response.Response(
                {"detail": f"Limite KYC par operation depassee ({per_tx_limit:.0f} FCFA). Validez votre identite pour augmenter vos plafonds."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        day_start = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
        wallet, _ = Wallet.objects.get_or_create(owner=request.user)
        day_total = (
            wallet.transactions.filter(
                status__in=[TransactionStatus.SUCCESS, TransactionStatus.PENDING],
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

    @staticmethod
    def _withdrawal_fee(amount: Decimal) -> Decimal:
        """Frais de retrait = max(montant * pourcentage, plancher), en FCFA entiers.

        Arrondi au FCFA supérieur : le net reste entier (contrainte NotchPay)
        et la plateforme ne sous-facture jamais d'un centime.
        """
        from decimal import ROUND_UP

        percent = Decimal(str(get_platform_setting("withdrawal.fee_percent")))
        floor = Decimal(str(get_platform_setting("withdrawal.fee_min")))
        if percent <= 0 and floor <= 0:
            return Decimal("0")
        fee = amount * percent / Decimal("100")
        if fee < floor:
            fee = floor
        return fee.quantize(Decimal("1"), rounding=ROUND_UP)

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
        return None

    @decorators.action(detail=False, methods=["post"])
    def request_otp(self, request):
        return response.Response(
            {"detail": "Endpoint desactive. Le retrait utilise le code de securite par email."},
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
        limit_error = self._enforce_kyc_limits(request, amount, kind="deposit")
        if limit_error:
            return limit_error
        security_error = self._validate_wallet_security(request, amount, "TOPUP")
        if security_error:
            return security_error
        fraud_error = self._check_fraud(request, amount, "topup")
        if fraud_error:
            return fraud_error

        idempotency_key = request.headers.get("Idempotency-Key") or str(request.data.get("idempotency_key") or "").strip()
        idem_record = None
        if idempotency_key:
            try:
                idem_record, cached = IdempotencyService.acquire(
                    key=idempotency_key,
                    user_id=request.user.id,
                    endpoint="wallet.topup",
                    payload=dict(request.data),
                )
            except IdempotencyConflict as exc:
                return response.Response({"detail": str(exc)}, status=status.HTTP_409_CONFLICT)
            if cached is not None:
                return response.Response(cached, status=status.HTTP_200_OK)

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
            try:
                with transaction.atomic():
                    tx = wallet.transactions.create(
                        amount=amount,
                        kind="TOPUP",
                        provider=provider,
                        status=TransactionStatus.PENDING,
                        idempotency_key=idempotency_key,
                        external_transaction_id=external_tx,
                        reference=f"topup:{provider}:{source_account}:tx:{external_tx}",
                    )
            except IntegrityError:
                existing = (
                    wallet.transactions.filter(idempotency_key=idempotency_key).first()
                    if idempotency_key else None
                )
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
                raise
        checkout = NotchPayCheckoutService.create_invoice(
            amount=amount,
            description=f"Recharge wallet {request.user.username}",
            tx_ref=external_tx,
            provider=provider,
            customer_name=request.user.get_full_name() or request.user.username,
            customer_email=request.user.email,
        )

        if checkout.get("error"):
            _raw_error = str(checkout["error"])
            logger.error(
                "notchpay_checkout_error tx=%s provider_error=%.500s",
                external_tx,
                _raw_error,
            )
            self._mark_transaction_failed(tx=tx, reason=_raw_error[:240])
            IdempotencyService.fail(idem_record)
            return response.Response(
                {"detail": "Echec initialisation paiement. Reessayez ou contactez le support."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        payment_mode = "redirect"
        if checkout.get("mode") == "SIMULATED":
            self._mark_transaction_success(tx=tx, payload={"mode": "SIMULATED"}, mark_payout=True)
            payment_mode = "simulated"
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

            if NotchPayCheckoutService.supports_direct_charge(provider):
                charge_result = NotchPayCheckoutService.charge(
                    reference=checkout_reference,
                    channel=NotchPayCheckoutService.channel_for_provider(provider),
                    phone=source_account,
                    client_ip=_client_ip(request),
                )
                if charge_result.get("error"):
                    _raw_error = str(charge_result["error"])
                    logger.error(
                        "notchpay_charge_error tx=%s provider_error=%.500s",
                        external_tx,
                        _raw_error,
                    )
                    self._mark_transaction_failed(tx=tx, reason=_raw_error[:240])
                    IdempotencyService.fail(idem_record)
                    return response.Response(
                        {"detail": "Echec du paiement. Verifiez le numero puis reessayez."},
                        status=status.HTTP_502_BAD_GATEWAY,
                    )
                payment_mode = "direct_charge"
                checkout["checkout_url"] = None

        write_audit_log(
            actor=request.user,
            action="Demande recharge wallet",
            action_key="wallet.topup",
            metadata={
                "tx": tx.external_transaction_id,
                "amount": str(amount),
                "provider": provider,
                "payment_mode": payment_mode,
            },
        )
        response_data = {
            "detail": (
                "Validez le paiement sur votre telephone."
                if payment_mode == "direct_charge"
                else "Paiement initie."
            ),
            "transaction_id": tx.external_transaction_id,
            "mode": checkout.get("mode", "LIVE"),
            "payment_mode": payment_mode,
            "checkout_url": checkout.get("checkout_url"),
            "status": tx.status,
        }
        IdempotencyService.complete(idem_record, response_data)
        return response.Response(response_data)

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
        limit_error = self._enforce_kyc_limits(request, amount, kind="withdraw")
        if limit_error:
            return limit_error
        security_error = self._validate_wallet_security(request, amount, "WITHDRAW")
        if security_error:
            return security_error
        fraud_error = self._check_fraud(request, amount, "withdraw")
        if fraud_error:
            return fraud_error

        fee = self._withdrawal_fee(amount)
        net_amount = amount - fee
        if net_amount < self._MIN_TX_AMOUNT:
            return response.Response(
                {"detail": f"Montant trop faible: apres frais de {fee:.0f} FCFA, le net doit rester >= {self._MIN_TX_AMOUNT:.0f} FCFA."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        idempotency_key = request.headers.get("Idempotency-Key") or str(request.data.get("idempotency_key") or "").strip()
        idem_record = None
        if idempotency_key:
            try:
                idem_record, cached = IdempotencyService.acquire(
                    key=idempotency_key,
                    user_id=request.user.id,
                    endpoint="wallet.withdraw",
                    payload=dict(request.data),
                )
            except IdempotencyConflict as exc:
                return response.Response({"detail": str(exc)}, status=status.HTTP_409_CONFLICT)
            if cached is not None:
                return response.Response(cached, status=status.HTTP_200_OK)

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
            try:
                with transaction.atomic():
                    tx = wallet.transactions.create(
                        amount=-amount,
                        kind="WITHDRAWAL",
                        provider=provider,
                        status=TransactionStatus.PENDING,
                        idempotency_key=idempotency_key,
                        external_transaction_id=external_tx,
                        reference=f"withdraw:{provider}:{destination_account}:tx:{external_tx}",
                        metadata={"fee": str(fee), "net_amount": str(net_amount)},
                    )
            except IntegrityError:
                existing = (
                    wallet.transactions.filter(idempotency_key=idempotency_key).first()
                    if idempotency_key else None
                )
                if existing:
                    return response.Response(
                        {
                            "detail": "Requete idempotente deja traitee.",
                            "transaction_id": existing.external_transaction_id,
                            "status": existing.status,
                        },
                        status=status.HTTP_200_OK,
                    )
                raise

        disburse_id = f"WITHDRAW-{tx.id}"
        transfer = NotchPayDisbursementService.send_money(
            amount=net_amount,
            account_alias=destination_account,
            provider=provider,
            transaction_id=disburse_id,
            account_name=request.user.get_full_name() or request.user.username,
        )
        if transfer.get("error"):
            _raw_error = str(transfer["error"])
            logger.error(
                "notchpay_disburse_error tx=%s provider_error=%.500s",
                external_tx,
                _raw_error,
            )
            self._mark_transaction_failed(tx=tx, reason=_raw_error[:240])
            IdempotencyService.fail(idem_record)
            return response.Response(
                {"detail": "Echec initialisation retrait. Reessayez ou contactez le support."},
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
        response_data = {
            "detail": "Retrait initie.",
            "transaction_id": transfer["transaction_id"],
            "mode": transfer["mode"],
            "status": tx.status,
            "fee": str(fee),
            "net_amount": str(net_amount),
        }
        IdempotencyService.complete(idem_record, response_data)
        return response.Response(response_data)

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
                fee = Decimal(str((tx.metadata or {}).get("fee") or "0"))
                if fee > 0:
                    WalletAccountingService.mutate_wallet(
                        wallet=wallet,
                        amount=fee,
                        entry_type=LedgerEntryType.COMMISSION,
                        direction=LedgerDirection.CREDIT,
                        reference=f"wallet-withdraw-fee:{tx.external_transaction_id or tx.id}",
                        idempotency_key=f"tx-fee:{tx.id}",
                        created_by=wallet.owner,
                        metadata={"withdrawal_tx": tx.external_transaction_id},
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
            self._log_state_transition(
                tx,
                from_status=TransactionStatus.PENDING,
                to_status=TransactionStatus.SUCCESS,
                extended_status="settled",
                reason="provider_confirmed",
            )
        broadcast_event("wallets", "transaction_success", {"transaction_id": tx.external_transaction_id, "kind": tx.kind})
        write_audit_log(
            actor=tx.wallet.owner,
            action="Transaction wallet succes",
            action_key="wallet.transaction.success",
            metadata={"transaction_id": tx.external_transaction_id, "kind": tx.kind},
        )
        try:
            _kind_label = {"TOPUP": "Recharge", "WITHDRAWAL": "Retrait"}.get(tx.kind, tx.kind)
            _amount = abs(tx.amount)
            create_realtime_notification(
                user=tx.wallet.owner,
                title=f"{_kind_label} confirmé",
                body=f"{_kind_label} de {_amount:,.0f} XAF confirmé avec succès.",
                payload={"transaction_id": tx.external_transaction_id, "kind": tx.kind},
            )
        except Exception:
            logger.exception("notif_wallet_success_failed tx=%s", getattr(tx, "id", None))
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
            logger.exception("notif_wallet_incident_owner_failed tx=%s", tx.id)
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
                logger.exception("notif_wallet_incident_admin_failed tx=%s admin=%d", tx.id, admin.id)
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
                tx.status = TransactionStatus.FAILED
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
            self._log_state_transition(
                tx,
                from_status=TransactionStatus.PENDING,
                to_status=tx.status,
                extended_status=(
                    "failed_retryable"
                    if tx.status == TransactionStatus.PENDING
                    else "failed_final"
                ),
                reason=reason[:240],
            )

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
        is_valid, auth_error = self._verify_webhook_auth(request, "checkout", "NOTCHPAY_CHECKOUT_WEBHOOK_SECRET")
        if not is_valid:
            return response.Response({"detail": auth_error}, status=status.HTTP_403_FORBIDDEN)

        payload = request.data if isinstance(request.data, dict) else {}
        event_payload = self._parse_notchpay_event(payload)
        event_data = event_payload.get("data") if isinstance(event_payload.get("data"), dict) else {}
        if not event_data:
            return response.Response({"detail": "Payload NotchPay invalide."}, status=status.HTTP_400_BAD_REQUEST)

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
        is_valid, auth_error = self._verify_webhook_auth(request, "disburse", "NOTCHPAY_DISBURSE_WEBHOOK_SECRET")
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
            expected_amount = abs(tx.amount)
            _net_meta = (tx.metadata or {}).get("net_amount")
            if _net_meta not in {None, ""}:
                try:
                    expected_amount = Decimal(str(_net_meta))
                except (InvalidOperation, TypeError):
                    pass
            if is_success:
                raw_amount = data.get("amount") or payload.get("amount")
                if raw_amount in {None, ""}:
                    event.processed = True
                    event.processed_at = timezone.now()
                    event.processing_error = "montant_manquant"
                    event.save(update_fields=["processed", "processed_at", "processing_error"])
                    security_event_logger.warning(
                        "webhook_disburse_missing_amount tx=%s ip=%s",
                        external_tx,
                        _client_ip(request),
                    )
                    return response.Response(
                        {"detail": "Montant manquant dans le webhook."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                try:
                    if Decimal(str(raw_amount)) != expected_amount:
                        event.processed = True
                        event.processed_at = timezone.now()
                        event.processing_error = "montant_non_conforme"
                        event.save(update_fields=["processed", "processed_at", "processing_error"])
                        security_event_logger.warning(
                            "webhook_disburse_amount_mismatch tx=%s "
                            "expected=%s received=%s ip=%s",
                            external_tx,
                            expected_amount,
                            raw_amount,
                            _client_ip(request),
                        )
                        return response.Response(
                            {"detail": "Montant non conforme."},
                            status=status.HTTP_400_BAD_REQUEST,
                        )
                except (InvalidOperation, TypeError):
                    event.processed = True
                    event.processed_at = timezone.now()
                    event.processing_error = "montant_invalide"
                    event.save(update_fields=["processed", "processed_at", "processing_error"])
                    return response.Response(
                        {"detail": "Montant invalide."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
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

        verified, step_up_message = verify_sensitive_action_challenge(
            user=request.user,
            action_key="wallet.reconcile",
            challenge_token=str(request.data.get("challenge_token") or ""),
            verification_code=str(request.data.get("verification_code") or ""),
        )
        if not verified:
            security_event_logger.warning(
                "reconcile_stepup_failed user=%d reason=%s ip=%s",
                request.user.id,
                step_up_message,
                _client_ip(request),
            )
            return response.Response(
                {"detail": step_up_message},
                status=status.HTTP_403_FORBIDDEN,
            )

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
        queryset = wallet.transactions.all().order_by("-created_at")

        status_filter = str(request.query_params.get("status") or "").strip().upper()
        if status_filter in {TransactionStatus.PENDING, TransactionStatus.SUCCESS, TransactionStatus.FAILED}:
            queryset = queryset.filter(status=status_filter)

        kind_filter = str(request.query_params.get("kind") or "").strip().upper()
        if kind_filter:
            queryset = queryset.filter(kind=kind_filter)

        before_raw = str(request.query_params.get("before") or "").strip()
        if before_raw:
            if any(ord(c) < 0x20 for c in before_raw):
                return response.Response(
                    {"detail": "Curseur invalide."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            from django.utils.dateparse import parse_datetime
            before_dt = parse_datetime(before_raw)
            if before_dt is None or not timezone.is_aware(before_dt):
                return response.Response(
                    {"detail": "Curseur invalide: format ISO-8601 avec fuseau requis."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            _now = timezone.now()
            _lower_bound = _now.replace(year=2020, month=1, day=1)
            if before_dt < _lower_bound or before_dt > _now:
                return response.Response(
                    {"detail": "Curseur hors limites."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            queryset = queryset.filter(created_at__lt=before_dt)

        try:
            page_size = min(max(int(request.query_params.get("limit", 40)), 1), 100)
        except (TypeError, ValueError):
            page_size = 40

        rows = list(queryset[:page_size + 1])
        has_more = len(rows) > page_size
        rows = rows[:page_size]

        resp = response.Response(WalletTransactionSerializer(rows, many=True).data)
        resp["X-Has-More"] = "true" if has_more else "false"
        resp["X-Page-Size"] = str(page_size)
        if rows:
            resp["X-Next-Cursor"] = rows[-1].created_at.isoformat()
        return resp

    @decorators.action(
        detail=False,
        methods=["get"],
        url_path=r"transactions/(?P<external_id>[^/.]+)/status",
    )
    def transaction_status(self, request, external_id=None):
        """
        GET /api/wallets/transactions/{external_id}/status/

        Phase 3 — lightweight polling endpoint for pending payment screens.
        Used by NotchPayPendingSheet to check confirmation without downloading
        the full transaction list.  Returns a minimal payload optimised for
        low-bandwidth Africa mobile networks.
        """
        if not external_id:
            return response.Response({"detail": "external_id requis."}, status=status.HTTP_400_BAD_REQUEST)

        wallet = Wallet.objects.filter(owner=request.user).first()
        if not wallet:
            return response.Response({"detail": "Portefeuille introuvable."}, status=status.HTTP_404_NOT_FOUND)
        tx = (
            WalletTransaction.objects
            .filter(wallet=wallet, external_transaction_id=external_id)
            .first()
        )
        if not tx:
            tx = (
                WalletTransaction.objects
                .filter(wallet=wallet, idempotency_key=external_id)
                .first()
            )
        if not tx:
            return response.Response({"detail": "Transaction introuvable."}, status=status.HTTP_404_NOT_FOUND)

        latest_log = tx.state_logs.order_by("-created_at").first()
        return response.Response({
            "id": tx.id,
            "external_transaction_id": tx.external_transaction_id,
            "status": tx.status,
            "extended_status": latest_log.extended_status if latest_log else "",
            "kind": tx.kind,
            "provider": tx.provider,
            "amount": str(tx.amount),
            "created_at": tx.created_at.isoformat(),
            "updated_at": tx.updated_at.isoformat(),
            "reconciled_at": tx.reconciled_at.isoformat() if tx.reconciled_at else None,
            "failure_reason": tx.failure_reason,
            "can_retry": (
                tx.status == TransactionStatus.FAILED and tx.kind == "TOPUP"
            ),
        })
