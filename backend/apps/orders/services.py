from __future__ import annotations

import hashlib
import logging
import sys
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.accounts.upload_security import validate_uploaded_file
from apps.accounts.models import UserRole
from apps.accounts.security import write_audit_log
from apps.wallets.models import LedgerDirection, LedgerEntryType, PaymentProvider, TransactionStatus, WalletTransaction
from apps.wallets.payout_retry import enqueue_payout_retry
from apps.wallets.notchpay_service import NotchPayDisbursementService
from apps.wallets.services import InsufficientFundsError, WalletAccountingService, quantize_money

from .models import (
    EscrowLifecycleStatus,
    EscrowStatus,
    EscrowType,
    LogisticsVerification,
    Order,
    OrderEscrow,
    OrderStatus,
    OrderType,
)

logger = logging.getLogger(__name__)

ZERO = Decimal("0.00")
DEFAULT_PLATFORM_COMMISSION_RATE = Decimal("0.0500")
MIN_TRUST_SCORE = Decimal("1.00")


class FraudRiskError(Exception):
    pass


class OrderFinanceService:
    @classmethod
    def _ensure_secure_proof_storage(cls):
        if settings.DEBUG or "test" in sys.argv:
            return
        require_remote = bool(getattr(settings, "REQUIRE_REMOTE_PROOF_STORAGE", True))
        if not require_remote:
            return
        # Django 5.x : la source de vérité est STORAGES["default"]; on garde
        # DEFAULT_FILE_STORAGE en repli (miroir maintenu côté settings).
        storage_backend = ""
        try:
            storage_backend = str(settings.STORAGES["default"]["BACKEND"])
        except (AttributeError, KeyError, TypeError):
            storage_backend = ""
        if not storage_backend:
            storage_backend = str(
                getattr(settings, "DEFAULT_FILE_STORAGE", "django.core.files.storage.FileSystemStorage") or ""
            )
        if "FileSystemStorage" in storage_backend:
            raise ValidationError("Stockage local interdit pour les preuves en production. Utilisez S3 ou R2.")

    @classmethod
    def lock_funds_for_order(
        cls,
        *,
        order: Order,
        actor,
        supplier_amount,
        logistics_amount,
        idempotency_key: str = "",
    ) -> list[OrderEscrow]:
        supplier_amount = quantize_money(supplier_amount)
        logistics_amount = quantize_money(logistics_amount)
        total = quantize_money(supplier_amount + logistics_amount)
        if total <= ZERO:
            raise ValidationError("Le montant total a bloquer doit etre positif.")

        # Audit ref: [FIN-014] derive a deterministic idempotency key when the
        # caller didn't pass one. Two rapid "pay" clicks from a buyer used to
        # double-lock funds because `WalletAccountingService.lock_from_available`
        # treats an empty key as "no idempotency" and re-runs the mutation.
        if not idempotency_key:
            idempotency_key = f"order:{order.id}:lock_funds_v1"

        with transaction.atomic():
            order = Order.objects.select_for_update(of=("self",)).select_related("buyer", "seller", "preferred_transit_agent").get(id=order.id)
            existing = list(order.escrows.all())
            if existing:
                return existing

            wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
            if wallet.available_balance < total:
                raise InsufficientFundsError("Solde wallet insuffisant pour cette commande.")

            WalletAccountingService.lock_from_available(
                wallet=wallet,
                amount=total,
                reference=f"order:{order.id}:fund_lock",
                idempotency_key=idempotency_key,
                order=order,
                created_by=actor,
                metadata={
                    "order_id": order.id,
                    "supplier_amount": str(supplier_amount),
                    "logistics_amount": str(logistics_amount),
                },
            )

            escrows: list[OrderEscrow] = []
            if order.order_type == OrderType.INTERNATIONAL:
                if supplier_amount <= ZERO:
                    raise ValidationError("Montant fournisseur invalide pour commande internationale.")
                supplier_escrow = OrderEscrow.objects.create(
                    order=order,
                    escrow_type=EscrowType.SUPPLIER,
                    beneficiary=order.seller,
                    amount=supplier_amount,
                    release_conditions={
                        "transit_agent_confirmation": True,
                        "purchase_proof_uploaded": True,
                        "admin_validated": True,
                    },
                    requires_transit_confirmation=True,
                    requires_purchase_proof=True,
                    requires_admin_validation=True,
                    requires_buyer_confirmation=False,
                    status=EscrowLifecycleStatus.LOCKED,
                )
                escrows.append(supplier_escrow)

                if logistics_amount > ZERO:
                    logistics_escrow = OrderEscrow.objects.create(
                        order=order,
                        escrow_type=EscrowType.LOGISTICS,
                        beneficiary=order.preferred_transit_agent,
                        amount=logistics_amount,
                        release_conditions={"buyer_confirmed_delivery": True},
                        requires_buyer_confirmation=True,
                        status=EscrowLifecycleStatus.LOCKED,
                    )
                    escrows.append(logistics_escrow)

                LogisticsVerification.objects.create(order=order, supplier_escrow=supplier_escrow)
                order.status = OrderStatus.SOURCING
                order.escrow_status = EscrowStatus.SPLIT_LOCKED
            else:
                beneficiary = order.seller
                local_escrow = OrderEscrow.objects.create(
                    order=order,
                    escrow_type=EscrowType.LOCAL,
                    beneficiary=beneficiary,
                    amount=total,
                    release_conditions={"buyer_confirmed_delivery": True},
                    requires_buyer_confirmation=True,
                    status=EscrowLifecycleStatus.LOCKED,
                )
                escrows.append(local_escrow)
                order.status = OrderStatus.PENDING
                order.escrow_status = EscrowStatus.HELD

            order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Blocage fonds commande",
                action_key="orders.escrow.lock",
                metadata={
                    "order_id": order.id,
                    "order_type": order.order_type,
                    "total_locked": str(total),
                    "escrow_count": len(escrows),
                },
            )
        return escrows

    @classmethod
    def _enforce_supplier_fraud_controls(cls, *, order: Order, actor) -> None:
        shipment = getattr(order, "shipment", None)
        if not shipment or not shipment.transit_agent_id:
            raise FraudRiskError("Aucun transitaire assigne pour la verification fournisseur.")
        if shipment.transit_agent_id in {order.seller_id, order.buyer_id}:
            raise FraudRiskError("Conflit d'interets detecte: transitaire non independant.")
        if not getattr(order.seller, "is_verified", False) or int(getattr(order.seller, "kyc_level", 0) or 0) < 1:
            raise FraudRiskError("Fournisseur non conforme KYC.")
        trust_score = Decimal(str(getattr(shipment.transit_agent, "trust_score", 0) or 0))
        if not getattr(shipment.transit_agent, "is_verified", False) or trust_score < MIN_TRUST_SCORE:
            raise FraudRiskError("Transitaire a risque: verification renforcee requise.")
        if actor and actor.id in {order.seller_id, order.buyer_id}:
            raise FraudRiskError("Validation fournisseur invalide: acteur en conflit.")

    @classmethod
    def register_supplier_confirmation(cls, *, order: Order, actor):
        with transaction.atomic():
            order = Order.objects.select_for_update(of=("self",)).select_related("shipment", "seller", "buyer").get(id=order.id)
            if order.order_type != OrderType.INTERNATIONAL:
                raise ValidationError("Cette action est reservee aux commandes internationales.")
            if not hasattr(order, "shipment") or order.shipment.transit_agent_id != actor.id:
                raise ValidationError("Confirmation reservee au transitaire assigne.")
            cls._enforce_supplier_fraud_controls(order=order, actor=actor)

            verification, _ = LogisticsVerification.objects.select_for_update().get_or_create(order=order)
            verification.transit_agent_confirmed = True
            verification.transit_agent_confirmed_by = actor
            verification.transit_agent_confirmed_at = timezone.now()
            verification.save(
                update_fields=[
                    "transit_agent_confirmed",
                    "transit_agent_confirmed_by",
                    "transit_agent_confirmed_at",
                    "updated_at",
                ]
            )
            supplier_escrow = order.escrows.select_for_update().filter(escrow_type=EscrowType.SUPPLIER).first()
            if supplier_escrow:
                supplier_escrow.transit_confirmed_by = actor
                supplier_escrow.transit_confirmed_at = verification.transit_agent_confirmed_at
                supplier_escrow.status = EscrowLifecycleStatus.READY
                supplier_escrow.save(update_fields=["transit_confirmed_by", "transit_confirmed_at", "status", "updated_at"])
            order.status = OrderStatus.SUPPLIER_VERIFIED
            order.save(update_fields=["status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Confirmation fournisseur par transitaire",
                action_key="orders.supplier.confirm",
                metadata={"order_id": order.id},
            )
        return verification

    @classmethod
    def register_supplier_purchase_proof(cls, *, order: Order, actor, proof_file):
        with transaction.atomic():
            order = Order.objects.select_for_update(of=("self",)).select_related("shipment", "seller", "buyer").get(id=order.id)
            if order.order_type != OrderType.INTERNATIONAL:
                raise ValidationError("Cette action est reservee aux commandes internationales.")
            if not hasattr(order, "shipment") or order.shipment.transit_agent_id != actor.id:
                raise ValidationError("Upload reserve au transitaire assigne.")
            cls._enforce_supplier_fraud_controls(order=order, actor=actor)
            cls._ensure_secure_proof_storage()
            validate_uploaded_file(
                proof_file,
                field_label="Preuve achat fournisseur",
                allowed_extensions={".pdf", ".png", ".jpg", ".jpeg", ".webp"},
                allowed_content_types={
                    "application/pdf",
                    "image/png",
                    "image/jpeg",
                    "image/webp",
                },
                max_mb=15,
            )

            proof_hash = ""
            if proof_file and hasattr(proof_file, "read"):
                body = proof_file.read()
                if hasattr(proof_file, "seek"):
                    proof_file.seek(0)
                proof_hash = hashlib.sha256(body).hexdigest()
                reused = LogisticsVerification.objects.filter(purchase_proof_hash=proof_hash).exclude(order=order).exists()
                if reused:
                    raise FraudRiskError("Preuve deja utilisee sur une autre commande.")

            verification, _ = LogisticsVerification.objects.select_for_update().get_or_create(order=order)
            verification.purchase_proof = proof_file
            verification.purchase_proof_hash = proof_hash
            verification.purchase_proof_uploaded_by = actor
            verification.purchase_proof_uploaded_at = timezone.now()
            verification.save(
                update_fields=[
                    "purchase_proof",
                    "purchase_proof_hash",
                    "purchase_proof_uploaded_by",
                    "purchase_proof_uploaded_at",
                    "updated_at",
                ]
            )
            supplier_escrow = order.escrows.select_for_update().filter(escrow_type=EscrowType.SUPPLIER).first()
            if supplier_escrow:
                supplier_escrow.purchase_proof = proof_file
                supplier_escrow.purchase_proof_hash = proof_hash
                supplier_escrow.purchase_proof_uploaded_by = actor
                supplier_escrow.purchase_proof_uploaded_at = verification.purchase_proof_uploaded_at
                supplier_escrow.status = EscrowLifecycleStatus.READY
                supplier_escrow.save(
                    update_fields=[
                        "purchase_proof",
                        "purchase_proof_hash",
                        "purchase_proof_uploaded_by",
                        "purchase_proof_uploaded_at",
                        "status",
                        "updated_at",
                    ]
                )
            write_audit_log(
                actor=actor,
                action="Preuve achat fournisseur upload",
                action_key="orders.supplier.proof",
                metadata={"order_id": order.id, "proof_hash": proof_hash},
            )
        return verification

    @classmethod
    def admin_validate_supplier(cls, *, order: Order, actor, approve: bool, note: str = ""):
        if not actor or not actor.is_authenticated or not (actor.is_superuser or actor.role == UserRole.GENERAL_ADMIN):
            raise ValidationError("Validation reservee a l'administration.")
        with transaction.atomic():
            order = Order.objects.select_for_update().select_related("seller", "buyer").get(id=order.id)
            verification, _ = LogisticsVerification.objects.select_for_update().get_or_create(order=order)
            supplier_escrow = order.escrows.select_for_update().filter(escrow_type=EscrowType.SUPPLIER).first()
            if not supplier_escrow:
                raise ValidationError("Escrow fournisseur introuvable.")
            if actor.id in {order.seller_id, order.buyer_id}:
                raise FraudRiskError("Separation des roles violee: admin en conflit d'interets.")
            if not approve:
                verification.fraud_flagged = True
                verification.fraud_reason = (note or "Validation admin refusee").strip()[:240]
                verification.admin_validated = False
                verification.admin_validated_by = actor
                verification.admin_validated_at = timezone.now()
                verification.save(
                    update_fields=[
                        "fraud_flagged",
                        "fraud_reason",
                        "admin_validated",
                        "admin_validated_by",
                        "admin_validated_at",
                        "updated_at",
                    ]
                )
                cls.freeze_order_escrows(order=order, actor=actor, reason=verification.fraud_reason)
                write_audit_log(
                    actor=actor,
                    action="Validation admin fournisseur refusee",
                    action_key="orders.supplier.admin_validate",
                    metadata={"order_id": order.id, "approved": False, "reason": verification.fraud_reason},
                )
                return verification

            verification.admin_validated = True
            verification.admin_validated_by = actor
            verification.admin_validated_at = timezone.now()
            verification.save(
                update_fields=["admin_validated", "admin_validated_by", "admin_validated_at", "updated_at"]
            )
            supplier_escrow.admin_validated_by = actor
            supplier_escrow.admin_validated_at = verification.admin_validated_at
            supplier_escrow.status = EscrowLifecycleStatus.READY
            supplier_escrow.save(update_fields=["admin_validated_by", "admin_validated_at", "status", "updated_at"])
            order.status = OrderStatus.ADMIN_APPROVED
            order.save(update_fields=["status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Validation admin fournisseur approuvee",
                action_key="orders.supplier.admin_validate",
                metadata={"order_id": order.id, "approved": True, "reason": note[:240]},
            )

        cls.release_supplier_escrow(order=order, actor=actor)
        return verification

    @classmethod
    def _queue_payout_transaction(cls, *, beneficiary_wallet, amount: Decimal, order: Order, kind: str, escrow: OrderEscrow | None = None):
        tx = WalletTransaction.objects.create(
            wallet=beneficiary_wallet,
            provider="",
            amount=-abs(amount),
            kind=kind,
            status=TransactionStatus.PENDING,
            reference=f"order:{order.id}:{kind.lower()}",
            metadata={
                "order_id": order.id,
                "escrow_id": escrow.id if escrow else None,
                "payout_amount": str(abs(amount)),
            },
        )
        account_alias = str(getattr(beneficiary_wallet.owner, "phone_number", "") or "").strip()
        if not account_alias:
            tx.status = TransactionStatus.FAILED
            tx.failure_reason = "account_alias_manquant"
            tx.save(update_fields=["status", "failure_reason", "updated_at"])
            return tx
        tx.metadata = {**(tx.metadata or {}), "account_alias": account_alias}
        tx.save(update_fields=["metadata", "updated_at"])
        try:
            transfer = NotchPayDisbursementService.send_money(
                amount=abs(amount),
                account_alias=account_alias,
                provider=PaymentProvider.MOBILE_MONEY,
                transaction_id=f"ORDER-PAYOUT-{tx.id}",
                account_name=beneficiary_wallet.owner.get_full_name() or beneficiary_wallet.owner.username,
            )
        except Exception as exc:
            tx.status = TransactionStatus.PENDING
            tx.failure_reason = f"payout_exception:{type(exc).__name__}"[:240]
            tx.metadata = {**(tx.metadata or {}), "payout_exception": type(exc).__name__}
            tx.save(update_fields=["status", "failure_reason", "metadata", "updated_at"])
            enqueue_payout_retry(tx=tx, error=tx.failure_reason, delay_seconds=180)
            return tx
        if transfer.get("error"):
            tx.status = TransactionStatus.PENDING
            tx.failure_reason = str(transfer.get("error", ""))[:240]
            tx.metadata = {**(tx.metadata or {}), "payout_error": transfer.get("error"), "raw": transfer.get("raw", {})}
            tx.save(update_fields=["status", "failure_reason", "metadata", "updated_at"])
            enqueue_payout_retry(tx=tx, error=tx.failure_reason, delay_seconds=180)
            return tx
        tx.provider = PaymentProvider.MOBILE_MONEY
        tx.external_transaction_id = str(transfer.get("transaction_id") or f"ORDER-PAYOUT-{tx.id}")
        tx.metadata = {**(tx.metadata or {}), "payout": transfer}
        if transfer.get("mode") == "SIMULATED":
            tx.status = TransactionStatus.SUCCESS
            tx.cinetpay_transfered = True
            tx.reconciled_at = timezone.now()
            tx.save(
                update_fields=[
                    "provider",
                    "external_transaction_id",
                    "metadata",
                    "status",
                    "cinetpay_transfered",
                    "reconciled_at",
                    "updated_at",
                ]
            )
            cls.finalize_payout_success(tx=tx, actor=None)
            return tx
        tx.save(update_fields=["provider", "external_transaction_id", "metadata", "updated_at"])
        return tx

    @classmethod
    def rollback_failed_payout(cls, *, tx: WalletTransaction, reason: str, actor=None):
        metadata = tx.metadata or {}
        order_id = metadata.get("order_id")
        escrow_id = metadata.get("escrow_id")
        if not order_id:
            return
        with transaction.atomic():
            tx = WalletTransaction.objects.select_for_update().select_related("wallet").get(id=tx.id)
            order = Order.objects.select_for_update().select_related("buyer").filter(id=order_id).first()
            if not order:
                return
            escrow = None
            if escrow_id:
                escrow = OrderEscrow.objects.select_for_update().filter(id=escrow_id, order=order).first()
            amount = quantize_money(abs(tx.amount))
            beneficiary_wallet = WalletAccountingService.get_wallet_for_update(user=tx.wallet.owner)
            buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)

            if beneficiary_wallet.pending_balance >= amount:
                WalletAccountingService.mutate_wallet(
                    wallet=beneficiary_wallet,
                    amount=amount,
                    entry_type=LedgerEntryType.PAYOUT,
                    direction=LedgerDirection.DEBIT,
                    pending_delta=-amount,
                    reference=f"order:{order.id}:payout_rollback:beneficiary_pending",
                    order=order,
                    escrow=escrow,
                    counterparty=order.buyer,
                    created_by=actor,
                    metadata={"reason": reason, "tx_id": tx.id},
                )
            elif beneficiary_wallet.available_balance >= amount:
                WalletAccountingService.mutate_wallet(
                    wallet=beneficiary_wallet,
                    amount=amount,
                    entry_type=LedgerEntryType.PAYOUT,
                    direction=LedgerDirection.DEBIT,
                    available_delta=-amount,
                    reference=f"order:{order.id}:payout_rollback:beneficiary",
                    order=order,
                    escrow=escrow,
                    counterparty=order.buyer,
                    created_by=actor,
                    metadata={"reason": reason, "tx_id": tx.id},
                )
            else:
                # Inconsistent state: insufficient beneficiary funds for rollback.
                order.status = OrderStatus.DISPUTED
                order.escrow_status = EscrowStatus.FROZEN
                order.save(update_fields=["status", "escrow_status", "updated_at"])
                if escrow and escrow.status != EscrowLifecycleStatus.RELEASED:
                    escrow.status = EscrowLifecycleStatus.FROZEN
                    escrow.frozen_reason = f"rollback_insufficient_funds:{reason}"[:240]
                    escrow.save(update_fields=["status", "frozen_reason", "updated_at"])
                write_audit_log(
                    actor=actor,
                    action="Rollback payout impossible",
                    action_key="orders.payout.rollback.failed",
                    metadata={"order_id": order.id, "tx_id": tx.id, "reason": reason},
                )
                return

            WalletAccountingService.mutate_wallet(
                wallet=buyer_wallet,
                amount=amount,
                entry_type=LedgerEntryType.REFUND,
                direction=LedgerDirection.CREDIT,
                locked_delta=amount,
                reference=f"order:{order.id}:payout_rollback:buyer_lock_restore",
                order=order,
                escrow=escrow,
                counterparty=tx.wallet.owner,
                created_by=actor,
                metadata={"reason": reason, "tx_id": tx.id},
            )
            if escrow:
                escrow.status = EscrowLifecycleStatus.FROZEN
                escrow.frozen_reason = reason[:240]
                escrow.save(update_fields=["status", "frozen_reason", "updated_at"])
            order.status = OrderStatus.DISPUTED
            order.escrow_status = EscrowStatus.FROZEN
            order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Rollback payout execute",
                action_key="orders.payout.rollback",
                metadata={"order_id": order.id, "tx_id": tx.id, "reason": reason},
            )

    @classmethod
    def finalize_payout_success(cls, *, tx: WalletTransaction, actor=None):
        metadata = tx.metadata or {}
        order_id = metadata.get("order_id")
        escrow_id = metadata.get("escrow_id")
        if not order_id or not escrow_id:
            return
        with transaction.atomic():
            tx = WalletTransaction.objects.select_for_update().select_related("wallet").get(id=tx.id)
            order = Order.objects.select_for_update().filter(id=order_id).first()
            escrow = OrderEscrow.objects.select_for_update().filter(id=escrow_id, order_id=order_id).first()
            if not order or not escrow:
                return
            if escrow.status == EscrowLifecycleStatus.RELEASED:
                return
            payout_amount = quantize_money(abs(tx.amount))
            beneficiary_wallet = WalletAccountingService.get_wallet_for_update(user=tx.wallet.owner)
            if beneficiary_wallet.pending_balance >= payout_amount:
                # Le payout MoMo a quitte la plateforme: on consomme uniquement
                # le pending (sans recrediter available, sinon double-credit).
                WalletAccountingService.mutate_wallet(
                    wallet=beneficiary_wallet,
                    amount=payout_amount,
                    entry_type=LedgerEntryType.PAYOUT,
                    direction=LedgerDirection.DEBIT,
                    available_delta=Decimal("0"),
                    pending_delta=-payout_amount,
                    reference=f"order:{order.id}:payout_success:beneficiary_pending",
                    order=order,
                    escrow=escrow,
                    counterparty=order.buyer,
                    created_by=actor,
                    metadata={"tx_id": tx.id},
                )
            escrow.status = EscrowLifecycleStatus.RELEASED
            escrow.released_amount = quantize_money(escrow.released_amount + payout_amount)
            escrow.released_at = timezone.now()
            escrow.frozen_reason = ""
            escrow.save(update_fields=["status", "released_amount", "released_at", "frozen_reason", "updated_at"])
            cls._refresh_order_escrow_status(order)
            if order.order_type == OrderType.LOCAL and escrow.escrow_type == EscrowType.LOCAL:
                order.status = OrderStatus.COMPLETED
            elif order.order_type == OrderType.INTERNATIONAL and escrow.escrow_type == EscrowType.LOGISTICS:
                if order.escrow_status == EscrowStatus.RELEASED:
                    order.status = OrderStatus.COMPLETED
            elif order.order_type == OrderType.INTERNATIONAL and escrow.escrow_type == EscrowType.SUPPLIER:
                order.status = OrderStatus.SHIPPING
            order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Finalisation payout escrow",
                action_key="orders.payout.success",
                metadata={"order_id": order.id, "escrow_id": escrow.id, "tx_id": tx.id},
            )

    @classmethod
    def release_supplier_escrow(cls, *, order: Order, actor):
        with transaction.atomic():
            order = Order.objects.select_for_update().select_related("buyer", "seller").get(id=order.id)
            if order.order_type != OrderType.INTERNATIONAL:
                raise ValidationError("La liberation fournisseur split est reservee aux commandes internationales.")
            if order.status not in {OrderStatus.SOURCING, OrderStatus.SUPPLIER_VERIFIED, OrderStatus.ADMIN_APPROVED, OrderStatus.SHIPPING}:
                raise ValidationError(f"Transition invalide pour liberation fournisseur: {order.status}.")
            verification = LogisticsVerification.objects.select_for_update().filter(order=order).first()
            if not verification or not verification.all_conditions_met():
                raise ValidationError("Conditions de liberation fournisseur non remplies.")
            supplier_escrow = order.escrows.select_for_update().filter(escrow_type=EscrowType.SUPPLIER).first()
            if not supplier_escrow:
                raise ValidationError("Escrow fournisseur introuvable.")
            if supplier_escrow.status == EscrowLifecycleStatus.RELEASED:
                return supplier_escrow
            if supplier_escrow.status == EscrowLifecycleStatus.FROZEN:
                raise ValidationError("Escrow fournisseur gele.")

            amount = quantize_money(supplier_escrow.amount)
            commission_rate = quantize_money(order.platform_commission_rate or DEFAULT_PLATFORM_COMMISSION_RATE)
            if commission_rate < ZERO:
                commission_rate = ZERO
            commission = quantize_money(amount * commission_rate)
            net_supplier = quantize_money(amount - commission)
            if net_supplier < ZERO:
                raise ValidationError("Commission invalide: montant net negatif.")

            buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
            if buyer_wallet.locked_balance < amount:
                raise InsufficientFundsError("Solde bloque acheteur insuffisant pour liberation fournisseur.")
            seller_wallet = WalletAccountingService.get_wallet_for_update(user=order.seller)

            WalletAccountingService.mutate_wallet(
                wallet=buyer_wallet,
                amount=amount,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.DEBIT,
                locked_delta=-amount,
                reference=f"order:{order.id}:supplier_release:buyer_lock",
                order=order,
                escrow=supplier_escrow,
                counterparty=order.seller,
                created_by=actor,
                metadata={"commission": str(commission), "net_supplier": str(net_supplier)},
            )
            WalletAccountingService.mutate_wallet(
                wallet=seller_wallet,
                amount=net_supplier,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.CREDIT,
                pending_delta=net_supplier,
                reference=f"order:{order.id}:supplier_release:seller_credit",
                order=order,
                escrow=supplier_escrow,
                counterparty=order.buyer,
                created_by=actor,
                metadata={"gross_amount": str(amount), "commission": str(commission)},
            )
            if commission > ZERO:
                WalletAccountingService.mutate_wallet(
                    wallet=buyer_wallet,
                    amount=commission,
                    entry_type=LedgerEntryType.COMMISSION,
                    direction=LedgerDirection.DEBIT,
                    reference=f"order:{order.id}:supplier_commission",
                    order=order,
                    escrow=supplier_escrow,
                    created_by=actor,
                    metadata={"rate": str(commission_rate)},
                )

            supplier_escrow.status = EscrowLifecycleStatus.PAYOUT_PENDING
            supplier_escrow.save(update_fields=["status", "updated_at"])
            cls._refresh_order_escrow_status(order)
            order.status = OrderStatus.SHIPPING
            order.save(update_fields=["status", "escrow_status", "updated_at"])
            payout_tx = cls._queue_payout_transaction(
                beneficiary_wallet=seller_wallet,
                amount=net_supplier,
                order=order,
                kind="PAYOUT_SUPPLIER",
                escrow=supplier_escrow,
            )
            if payout_tx and payout_tx.status == TransactionStatus.FAILED:
                cls.rollback_failed_payout(tx=payout_tx, reason=payout_tx.failure_reason, actor=actor)
                order.refresh_from_db(fields=["status", "escrow_status"])

            write_audit_log(
                actor=actor,
                action="Liberation escrow fournisseur",
                action_key="orders.escrow.release.supplier",
                metadata={
                    "order_id": order.id,
                    "gross_amount": str(amount),
                    "commission": str(commission),
                    "net_supplier": str(net_supplier),
                },
            )
        return supplier_escrow

    @classmethod
    def release_local_escrow_after_buyer_confirmation(cls, *, order: Order, actor):
        with transaction.atomic():
            order = Order.objects.select_for_update().select_related("buyer", "seller").get(id=order.id)
            if order.order_type != OrderType.LOCAL:
                raise ValidationError("Cette action est reservee aux commandes locales.")
            if order.status not in {OrderStatus.DELIVERED, OrderStatus.SHIPPING}:
                raise ValidationError(f"Transition invalide pour release local: {order.status}.")
            if order.buyer_id != actor.id:
                raise ValidationError("Confirmation finale reservee a l'acheteur.")
            escrow = order.escrows.select_for_update().filter(escrow_type=EscrowType.LOCAL).first()
            if not escrow:
                raise ValidationError("Escrow local introuvable.")
            if escrow.status == EscrowLifecycleStatus.RELEASED:
                return escrow
            if escrow.status == EscrowLifecycleStatus.FROZEN:
                raise ValidationError("Escrow local gele.")
            amount = quantize_money(escrow.amount)
            commission_rate = quantize_money(order.platform_commission_rate or DEFAULT_PLATFORM_COMMISSION_RATE)
            if commission_rate < ZERO:
                commission_rate = ZERO
            commission = quantize_money(amount * commission_rate)
            net_seller = quantize_money(amount - commission)
            if net_seller < ZERO:
                raise ValidationError("Commission invalide: montant net negatif.")

            buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
            if buyer_wallet.locked_balance < amount:
                raise InsufficientFundsError("Solde bloque acheteur insuffisant.")
            seller_wallet = WalletAccountingService.get_wallet_for_update(user=order.seller)
            WalletAccountingService.mutate_wallet(
                wallet=buyer_wallet,
                amount=amount,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.DEBIT,
                locked_delta=-amount,
                reference=f"order:{order.id}:local_release:buyer_lock",
                order=order,
                escrow=escrow,
                counterparty=order.seller,
                created_by=actor,
                metadata={"commission": str(commission), "net_seller": str(net_seller)},
            )
            WalletAccountingService.mutate_wallet(
                wallet=seller_wallet,
                amount=net_seller,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.CREDIT,
                pending_delta=net_seller,
                reference=f"order:{order.id}:local_release:seller_credit",
                order=order,
                escrow=escrow,
                counterparty=order.buyer,
                created_by=actor,
                metadata={"gross_amount": str(amount), "commission": str(commission)},
            )
            if commission > ZERO:
                WalletAccountingService.mutate_wallet(
                    wallet=buyer_wallet,
                    amount=commission,
                    entry_type=LedgerEntryType.COMMISSION,
                    direction=LedgerDirection.DEBIT,
                    reference=f"order:{order.id}:local_commission",
                    order=order,
                    escrow=escrow,
                    created_by=actor,
                    metadata={"rate": str(commission_rate)},
                )
            escrow.status = EscrowLifecycleStatus.PAYOUT_PENDING
            escrow.buyer_confirmed_by = actor
            escrow.buyer_confirmed_at = timezone.now()
            escrow.save(
                update_fields=[
                    "status",
                    "buyer_confirmed_by",
                    "buyer_confirmed_at",
                    "updated_at",
                ]
            )
            payout_tx = cls._queue_payout_transaction(
                beneficiary_wallet=seller_wallet,
                amount=net_seller,
                order=order,
                kind="PAYOUT_LOCAL_SUPPLIER",
                escrow=escrow,
            )
            if payout_tx.status == TransactionStatus.FAILED:
                cls.rollback_failed_payout(tx=payout_tx, reason=payout_tx.failure_reason, actor=actor)
                return escrow
            if payout_tx.status == TransactionStatus.SUCCESS:
                order.refresh_from_db(fields=["status", "escrow_status"])
            else:
                order.status = OrderStatus.DELIVERED
                cls._refresh_order_escrow_status(order)
                order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Liberation escrow local",
                action_key="orders.escrow.release.local",
                metadata={"order_id": order.id, "gross_amount": str(amount), "commission": str(commission)},
            )
        return escrow

    @classmethod
    def release_logistics_escrow_after_buyer_confirmation(cls, *, order: Order, actor):
        with transaction.atomic():
            order = Order.objects.select_for_update(of=("self",)).select_related("buyer", "preferred_transit_agent").get(id=order.id)
            # Verification d'autorisation AVANT toute mutation: la confirmation
            # finale est strictement reservee a l'acheteur de la commande.
            if order.buyer_id != getattr(actor, "id", None):
                raise ValidationError("Confirmation finale reservee a l'acheteur.")
            if order.status not in {OrderStatus.DELIVERED, OrderStatus.SHIPPING}:
                raise ValidationError(f"Transition invalide pour release logistique: {order.status}.")
            escrow = order.escrows.select_for_update().filter(escrow_type=EscrowType.LOGISTICS).first()
            if not escrow:
                cls._refresh_order_escrow_status(order)
                if order.escrow_status == EscrowStatus.RELEASED:
                    order.status = OrderStatus.COMPLETED
                    order.save(update_fields=["status", "escrow_status", "updated_at"])
                return None
            if escrow.status == EscrowLifecycleStatus.RELEASED:
                return escrow
            if escrow.status == EscrowLifecycleStatus.FROZEN:
                raise ValidationError("Escrow logistique gele.")
            amount = quantize_money(escrow.amount)

            buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
            if buyer_wallet.locked_balance < amount:
                raise InsufficientFundsError("Solde bloque acheteur insuffisant pour liberation logistique.")
            if not order.preferred_transit_agent_id:
                raise ValidationError("Aucun transitaire beneficiaire configure.")
            transit_wallet = WalletAccountingService.get_wallet_for_update(user=order.preferred_transit_agent)

            WalletAccountingService.mutate_wallet(
                wallet=buyer_wallet,
                amount=amount,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.DEBIT,
                locked_delta=-amount,
                reference=f"order:{order.id}:logistics_release:buyer_lock",
                order=order,
                escrow=escrow,
                counterparty=order.preferred_transit_agent,
                created_by=actor,
            )
            WalletAccountingService.mutate_wallet(
                wallet=transit_wallet,
                amount=amount,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.CREDIT,
                pending_delta=amount,
                reference=f"order:{order.id}:logistics_release:agent_credit",
                order=order,
                escrow=escrow,
                counterparty=order.buyer,
                created_by=actor,
            )

            escrow.status = EscrowLifecycleStatus.PAYOUT_PENDING
            escrow.buyer_confirmed_by = actor
            escrow.buyer_confirmed_at = timezone.now()
            escrow.save(
                update_fields=[
                    "status",
                    "buyer_confirmed_by",
                    "buyer_confirmed_at",
                    "updated_at",
                ]
            )
            payout_tx = cls._queue_payout_transaction(
                beneficiary_wallet=transit_wallet,
                amount=amount,
                order=order,
                kind="PAYOUT_LOGISTICS",
                escrow=escrow,
            )
            if payout_tx.status == TransactionStatus.FAILED:
                cls.rollback_failed_payout(tx=payout_tx, reason=payout_tx.failure_reason, actor=actor)
                return escrow
            if payout_tx.status == TransactionStatus.SUCCESS:
                order.refresh_from_db(fields=["status", "escrow_status"])
            else:
                order.status = OrderStatus.DELIVERED
                cls._refresh_order_escrow_status(order)
                order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Liberation escrow logistique",
                action_key="orders.escrow.release.logistics",
                metadata={"order_id": order.id, "amount": str(amount)},
            )
        return escrow

    @classmethod
    def freeze_order_escrows(cls, *, order: Order, actor, reason: str):
        with transaction.atomic():
            order = Order.objects.select_for_update().get(id=order.id)
            escrows = list(order.escrows.select_for_update().all())
            now = timezone.now()
            for escrow in escrows:
                if escrow.status == EscrowLifecycleStatus.RELEASED:
                    continue
                escrow.status = EscrowLifecycleStatus.FROZEN
                escrow.frozen_reason = (reason or "Litige").strip()[:240]
                escrow.updated_at = now
                escrow.save(update_fields=["status", "frozen_reason", "updated_at"])
            order.status = OrderStatus.DISPUTED
            order.escrow_status = EscrowStatus.FROZEN
            order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Gel escrows commande",
                action_key="orders.escrow.freeze",
                metadata={"order_id": order.id, "reason": reason},
            )
        return True

    @classmethod
    def _apply_locked_refund(cls, *, order: Order, actor, reason: str = ""):
        """Refund every still-locked escrow of *order* back to the buyer's
        available balance and mark them REFUNDED.

        MUST be called inside an open ``transaction.atomic()`` block. Returns
        ``(order, refund_amount)`` where ``order`` is re-fetched with
        ``select_for_update`` and has its ``escrow_status`` refreshed in memory.

        Permission-agnostic core shared by the admin/transit refund flow
        (:meth:`refund_order_locked_funds`) and the buyer/seller cancellation
        flow (:meth:`cancel_order`). Audit ref: [C-3].
        """
        order = Order.objects.select_for_update().select_related("buyer").get(id=order.id)
        escrows = list(order.escrows.select_for_update().all())
        refund_amount = ZERO
        for escrow in escrows:
            if escrow.status in {EscrowLifecycleStatus.REFUNDED, EscrowLifecycleStatus.RELEASED}:
                continue
            refund_amount += quantize_money(escrow.amount - escrow.released_amount)
            escrow.status = EscrowLifecycleStatus.REFUNDED
            escrow.refunded_at = timezone.now()
            escrow.save(update_fields=["status", "refunded_at", "updated_at"])

        refund_amount = quantize_money(refund_amount)
        if refund_amount > ZERO:
            buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
            WalletAccountingService.unlock_to_available(
                wallet=buyer_wallet,
                amount=refund_amount,
                entry_type=LedgerEntryType.REFUND,
                reference=f"order:{order.id}:refund",
                order=order,
                created_by=actor,
                metadata={"reason": reason},
            )
        cls._refresh_order_escrow_status(order)
        return order, refund_amount

    @classmethod
    def refund_order_locked_funds(cls, *, order: Order, actor, reason: str = ""):
        # Defense en profondeur: seuls admin, staff et transit_agent (gestion
        # litige logistique) peuvent declencher un remboursement systeme.
        if not actor or not getattr(actor, "is_authenticated", False) or not (
            getattr(actor, "is_superuser", False)
            or getattr(actor, "role", None) in {UserRole.GENERAL_ADMIN, UserRole.TRANSIT_AGENT}
        ):
            raise ValidationError("Action de remboursement reservee a l'administration ou au transitaire.")
        with transaction.atomic():
            order, refund_amount = cls._apply_locked_refund(order=order, actor=actor, reason=reason)
            if order.escrow_status == EscrowStatus.REFUNDED:
                order.status = OrderStatus.REFUNDED
            elif order.escrow_status == EscrowStatus.PARTIALLY_RELEASED:
                order.status = OrderStatus.COMPLETED
            else:
                order.status = OrderStatus.DISPUTED
            order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Remboursement commande",
                action_key="orders.refund",
                metadata={"order_id": order.id, "amount": str(refund_amount), "reason": reason},
            )
        return refund_amount

    # Audit ref: [C-3] Atomic buyer/seller cancellation.
    # Statuses from which a still-funded order may be cancelled (escrow not yet
    # fully released/refunded). Terminal states are rejected.
    CANCELLABLE_ORDER_STATUSES = frozenset({
        OrderStatus.PENDING,
        OrderStatus.SOURCING,
        OrderStatus.SUPPLIER_VERIFIED,
        OrderStatus.ADMIN_APPROVED,
        OrderStatus.SHIPPING,
        OrderStatus.CONFIRMED,
    })

    @classmethod
    def cancel_order(cls, *, order: Order, actor, reason: str = "Annulation commande"):
        """Cancel *order* and refund the buyer's still-locked escrow in a single
        atomic operation.

        Audit ref: [C-3]. Fixes the previous defect where the logistics
        ``update_status`` view persisted ``order.status = CANCELLED`` and *then*
        called :meth:`refund_order_locked_funds` (which rejects the buyer),
        leaving the order CANCELLED with escrow still LOCKED — buyer funds stuck.
        Here the cancellation and the refund commit or roll back together, and
        the order's own parties (buyer / seller) are authorized alongside
        admin / transit.
        """
        if not actor or not getattr(actor, "is_authenticated", False):
            raise ValidationError("Authentification requise.")
        is_party = actor.id in {order.buyer_id, order.seller_id}
        is_staff = getattr(actor, "is_superuser", False) or getattr(actor, "role", None) in {
            UserRole.GENERAL_ADMIN,
            UserRole.TRANSIT_AGENT,
        }
        if not (is_party or is_staff):
            raise ValidationError(
                "Annulation reservee aux parties de la commande ou a l'administration."
            )
        with transaction.atomic():
            locked = Order.objects.select_for_update().get(id=order.id)
            if locked.status not in cls.CANCELLABLE_ORDER_STATUSES:
                raise ValidationError(
                    f"Commande non annulable (statut actuel: {locked.status})."
                )
            refreshed, refund_amount = cls._apply_locked_refund(
                order=locked, actor=actor, reason=reason
            )
            refreshed.status = OrderStatus.CANCELLED
            refreshed.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Annulation commande",
                action_key="orders.cancel",
                metadata={"order_id": refreshed.id, "amount": str(refund_amount), "reason": reason},
            )
        return refund_amount

    @classmethod
    def admin_force_release_locked_escrows(cls, *, order: Order, actor, escrow_types: set[str] | None = None):
        if not actor or not actor.is_authenticated or not (actor.is_superuser or actor.role == UserRole.GENERAL_ADMIN):
            raise ValidationError("Action reservee a l'administration.")
        with transaction.atomic():
            order = Order.objects.select_for_update().select_related("buyer").get(id=order.id)
            buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
            escrows = list(order.escrows.select_for_update(of=("self",)).select_related("beneficiary"))
            released = []
            for escrow in escrows:
                if escrow_types and escrow.escrow_type not in escrow_types:
                    continue
                if escrow.status in {EscrowLifecycleStatus.RELEASED, EscrowLifecycleStatus.REFUNDED}:
                    continue
                beneficiary = escrow.beneficiary
                if not beneficiary:
                    continue
                amount = quantize_money(escrow.amount - escrow.released_amount)
                if amount <= ZERO:
                    continue
                if buyer_wallet.locked_balance < amount:
                    raise InsufficientFundsError("Solde bloque acheteur insuffisant pour release admin.")
                beneficiary_wallet = WalletAccountingService.get_wallet_for_update(user=beneficiary)
                WalletAccountingService.mutate_wallet(
                    wallet=buyer_wallet,
                    amount=amount,
                    entry_type=LedgerEntryType.ESCROW_RELEASE,
                    direction=LedgerDirection.DEBIT,
                    locked_delta=-amount,
                    reference=f"order:{order.id}:force_release:buyer_lock:{escrow.escrow_type}",
                    order=order,
                    escrow=escrow,
                    counterparty=beneficiary,
                    created_by=actor,
                    metadata={"forced_by_admin": True},
                )
                WalletAccountingService.credit_available(
                    wallet=beneficiary_wallet,
                    amount=amount,
                    entry_type=LedgerEntryType.ESCROW_RELEASE,
                    reference=f"order:{order.id}:force_release:beneficiary:{escrow.escrow_type}",
                    order=order,
                    escrow=escrow,
                    counterparty=order.buyer,
                    created_by=actor,
                    metadata={"forced_by_admin": True},
                )
                escrow.status = EscrowLifecycleStatus.RELEASED
                escrow.released_amount = quantize_money(escrow.released_amount + amount)
                escrow.released_at = timezone.now()
                escrow.frozen_reason = ""
                escrow.save(update_fields=["status", "released_amount", "released_at", "frozen_reason", "updated_at"])
                released.append(escrow.escrow_type)
            cls._refresh_order_escrow_status(order)
            if order.escrow_status == EscrowStatus.RELEASED:
                order.status = OrderStatus.COMPLETED
            order.save(update_fields=["status", "escrow_status", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Liberation admin escrows",
                action_key="admin.disputes.decide",
                metadata={"order_id": order.id, "escrow_types": released},
            )
        return released

    @classmethod
    def dispute_split_release(
        cls,
        *,
        order: Order,
        actor,
        buyer_refund: Decimal,
        seller_release: Decimal,
        reason: str = "",
    ) -> dict:
        """
        Audit ref: [FIN-005] dispute decision must execute the financial action.

        Settle a disputed order by splitting locked escrow funds between the
        buyer (partial refund) and the beneficiaries (partial payout).

        Invariants enforced under SELECT FOR UPDATE:
          * actor is GENERAL_ADMIN or superuser
          * buyer_refund + seller_release == sum of still-locked escrow amounts
          * amounts are Decimal-quantized (no float arithmetic)
        """
        if not actor or not actor.is_authenticated or not (
            actor.is_superuser or getattr(actor, "role", None) == UserRole.GENERAL_ADMIN
        ):
            raise ValidationError("Action reservee a l'administration.")

        buyer_refund = quantize_money(buyer_refund or ZERO)
        seller_release = quantize_money(seller_release or ZERO)
        if buyer_refund < ZERO or seller_release < ZERO:
            raise ValidationError("Montants negatifs interdits dans un split.")
        if buyer_refund == ZERO and seller_release == ZERO:
            raise ValidationError("Au moins un montant doit etre strictement positif.")

        with transaction.atomic():
            order = Order.objects.select_for_update().select_related("buyer").get(id=order.id)
            escrows = list(order.escrows.select_for_update().all())

            active = [
                e for e in escrows
                if e.status not in {EscrowLifecycleStatus.RELEASED, EscrowLifecycleStatus.REFUNDED}
            ]
            total_locked = quantize_money(
                sum((quantize_money(e.amount - e.released_amount) for e in active), ZERO)
            )
            requested = quantize_money(buyer_refund + seller_release)
            if requested != total_locked:
                raise ValidationError(
                    f"Somme buyer_refund + seller_release ({requested}) "
                    f"doit egaler le total verrouille ({total_locked})."
                )

            # ---- Buyer refund: unlock to available balance ----------------
            if buyer_refund > ZERO:
                buyer_wallet = WalletAccountingService.get_wallet_for_update(user=order.buyer)
                WalletAccountingService.unlock_to_available(
                    wallet=buyer_wallet,
                    amount=buyer_refund,
                    entry_type=LedgerEntryType.REFUND,
                    reference=f"order:{order.id}:dispute_split_refund",
                    order=order,
                    created_by=actor,
                    metadata={"dispute_split": True, "reason": reason[:240]},
                )

            # ---- Seller release: distribute across beneficiary escrows ----
            remaining_release = seller_release
            now = timezone.now()
            for escrow in active:
                avail = quantize_money(escrow.amount - escrow.released_amount)
                if avail <= ZERO:
                    continue
                # Cap each escrow at its own ceiling.
                portion_to_beneficiary = min(remaining_release, avail) if remaining_release > ZERO else ZERO
                portion_to_buyer = quantize_money(avail - portion_to_beneficiary)

                if portion_to_beneficiary > ZERO and escrow.beneficiary_id:
                    ben_wallet = WalletAccountingService.get_wallet_for_update(user=escrow.beneficiary)
                    cls._queue_payout_transaction(
                        beneficiary_wallet=ben_wallet,
                        amount=portion_to_beneficiary,
                        order=order,
                        kind="DISPUTE_RELEASE",
                        escrow=escrow,
                    )
                    escrow.released_amount = quantize_money(escrow.released_amount + portion_to_beneficiary)
                    remaining_release = quantize_money(remaining_release - portion_to_beneficiary)

                # If anything remains as buyer share for this escrow, it was
                # already unlocked above via the global buyer_refund call,
                # so we just mark the escrow's lifecycle here.
                if portion_to_beneficiary >= avail:
                    escrow.status = EscrowLifecycleStatus.RELEASED
                    escrow.released_at = now
                elif portion_to_beneficiary > ZERO:
                    escrow.status = EscrowLifecycleStatus.PARTIALLY_RELEASED if hasattr(EscrowLifecycleStatus, "PARTIALLY_RELEASED") else EscrowLifecycleStatus.REFUNDED
                    escrow.refunded_at = now
                else:
                    escrow.status = EscrowLifecycleStatus.REFUNDED
                    escrow.refunded_at = now
                escrow.save(update_fields=[
                    "released_amount", "status", "released_at", "refunded_at", "updated_at",
                ])

            cls._refresh_order_escrow_status(order)
            if order.escrow_status == EscrowStatus.RELEASED:
                order.status = OrderStatus.COMPLETED
            elif order.escrow_status == EscrowStatus.REFUNDED:
                order.status = OrderStatus.REFUNDED
            else:
                order.status = OrderStatus.DISPUTED
            order.save(update_fields=["status", "escrow_status", "updated_at"])

            write_audit_log(
                actor=actor,
                action="Litige split settlement",
                action_key="orders.dispute.split",
                metadata={
                    "order_id": order.id,
                    "buyer_refund": str(buyer_refund),
                    "seller_release": str(seller_release),
                    "total_locked": str(total_locked),
                    "reason": reason[:240],
                },
            )
        return {
            "buyer_refund": buyer_refund,
            "seller_release": seller_release,
            "total_locked": total_locked,
        }

    @classmethod
    def _refresh_order_escrow_status(cls, order: Order) -> str:
        escrows = list(order.escrows.all())
        if not escrows:
            order.escrow_status = EscrowStatus.HELD
            return order.escrow_status
        statuses = {esc.status for esc in escrows}
        if statuses == {EscrowLifecycleStatus.RELEASED}:
            order.escrow_status = EscrowStatus.RELEASED
        elif EscrowLifecycleStatus.FROZEN in statuses:
            order.escrow_status = EscrowStatus.FROZEN
        elif EscrowLifecycleStatus.REFUNDED in statuses and len(statuses) == 1:
            order.escrow_status = EscrowStatus.REFUNDED
        else:
            order.escrow_status = EscrowStatus.PARTIALLY_RELEASED
        return order.escrow_status
