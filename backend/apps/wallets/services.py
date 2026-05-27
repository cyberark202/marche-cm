from __future__ import annotations

import logging
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import transaction

from .models import LedgerDirection, LedgerEntryType, Wallet, WalletLedgerEntry

logger = logging.getLogger(__name__)

MONEY_QUANT = Decimal("0.01")
ZERO = Decimal("0.00")


class FinancialInvariantError(Exception):
    pass


class InsufficientFundsError(FinancialInvariantError):
    pass


def quantize_money(value) -> Decimal:
    try:
        amount = Decimal(str(value))
    except (InvalidOperation, TypeError) as exc:
        raise FinancialInvariantError("Montant invalide.") from exc
    return amount.quantize(MONEY_QUANT)


# Audit ref: [FIN-001] LedgerService was never branched in production.
# This mapping wires the simplified wallet ledger (WalletLedgerEntry) to the
# double-entry accounting ledger (LedgerService → LedgerTransaction +
# LedgerEntry). The double-entry side is the auditable source for accounting,
# regulator reporting and reconciliation. Failure to mirror rolls the WHOLE
# wallet mutation back (we share the parent transaction), guaranteeing the
# two ledgers never drift.
#
# Cases that have no equivalent double-entry transaction yet (commissions,
# internal transfers, etc.) return None — the wallet mutation still commits
# but no LedgerTransaction is created. A reconciliation job (Vague 6/7) will
# detect any missing mirror and surface it for engineering review.
def _mirror_wallet_entry_to_ledger(entry: WalletLedgerEntry):
    """Post a balanced LedgerTransaction matching a WalletLedgerEntry.

    Called from within mutate_wallet's atomic block — any exception raised
    here rolls back the wallet mutation as well.
    """
    # Operators can disable the mirror in emergencies via env flag. The wallet
    # operational ledger keeps working; the double-entry ledger pauses until
    # the flag is removed. Default ON.
    if not getattr(settings, "LEDGER_DOUBLE_ENTRY_ENABLED", True):
        return None

    # Lazy import — apps.ledger imports apps.wallets implicitly via models in
    # some paths; defer to avoid bootstrap-order issues.
    from apps.ledger.services import ledger_service

    user = entry.wallet.owner
    amount = entry.amount
    # Audit ref: [FIN-001-bis] LedgerTransaction.idempotency_key has a GLOBAL
    # unique constraint, while WalletLedgerEntry.idempotency_key is unique
    # only per wallet. Two users with the same wallet-level key (e.g.
    # "tx-success:42") would collide on the ledger side and crash the second
    # user's mutation. Scoping by (user_id, entry_type) eliminates cross-user
    # interference while keeping intra-user idempotency.
    user_id = getattr(user, "id", None) or "anon"
    if entry.idempotency_key:
        idem = f"wle:{user_id}:{entry.entry_type}:{entry.idempotency_key}"
    else:
        idem = f"wle:{user_id}:{entry.entry_type}:pk={entry.pk}"
    ref = entry.reference or ""
    counterparty = entry.counterparty
    if counterparty is None and entry.escrow is not None:
        counterparty = getattr(entry.escrow, "beneficiary", None)

    etype = entry.entry_type
    direction = entry.direction

    if etype == LedgerEntryType.DEPOSIT and direction == LedgerDirection.CREDIT:
        return ledger_service.post_topup(
            user=user, amount=amount, idempotency_key=idem, reference=ref,
        )
    if etype == LedgerEntryType.WITHDRAWAL and direction == LedgerDirection.DEBIT:
        return ledger_service.post_withdrawal(
            user=user, amount=amount, idempotency_key=idem, reference=ref,
        )
    if etype == LedgerEntryType.ESCROW_TRANSFER and counterparty is not None:
        return ledger_service.post_escrow_lock(
            buyer=user, seller=counterparty, amount=amount,
            idempotency_key=idem, order_reference=ref,
        )
    if etype == LedgerEntryType.REFUND and counterparty is not None:
        return ledger_service.post_escrow_refund(
            buyer=user, seller=counterparty, amount=amount,
            idempotency_key=idem, order_reference=ref,
        )
    if etype == LedgerEntryType.ESCROW_RELEASE:
        return ledger_service.post_escrow_release(
            seller=user, amount=amount, commission=ZERO,
            idempotency_key=idem, order_reference=ref,
        )

    # Unmapped entry types — log so reconciliation can pick them up.
    logger.info(
        "ledger_mirror_skip",
        extra={
            "entry_id": entry.pk,
            "entry_type": etype,
            "direction": direction,
            "reason": "no_ledger_mapping",
        },
    )
    return None


def _ensure_ledger_mirror_present(entry: WalletLedgerEntry):
    """Idempotent helper: post the ledger mirror only if it doesn't exist yet.

    Used on replay paths (mutate_wallet returning a previously-created entry)
    to converge the two ledgers without double-posting. The mirror's
    idempotency_key is deterministic (see _mirror_wallet_entry_to_ledger),
    so we can probe for it by exact match before posting.
    """
    if not getattr(settings, "LEDGER_DOUBLE_ENTRY_ENABLED", True):
        return None
    from apps.ledger.models import LedgerTransaction

    user_id = getattr(entry.wallet.owner, "id", None) or "anon"
    if entry.idempotency_key:
        idem = f"wle:{user_id}:{entry.entry_type}:{entry.idempotency_key}"
    else:
        idem = f"wle:{user_id}:{entry.entry_type}:pk={entry.pk}"
    if LedgerTransaction.objects.filter(idempotency_key=idem).exists():
        return None
    return _mirror_wallet_entry_to_ledger(entry)


class WalletAccountingService:
    @staticmethod
    def get_wallet_for_update(*, user) -> Wallet:
        wallet, _ = Wallet.objects.select_for_update().get_or_create(owner=user)
        return wallet

    @staticmethod
    def _apply_deltas(
        *,
        wallet: Wallet,
        available_delta: Decimal,
        locked_delta: Decimal,
        pending_delta: Decimal,
    ) -> None:
        wallet.available_balance = quantize_money(wallet.available_balance + available_delta)
        wallet.locked_balance = quantize_money(wallet.locked_balance + locked_delta)
        wallet.pending_balance = quantize_money(wallet.pending_balance + pending_delta)
        if wallet.available_balance < ZERO:
            raise InsufficientFundsError("Solde disponible insuffisant.")
        if wallet.locked_balance < ZERO or wallet.pending_balance < ZERO:
            raise FinancialInvariantError("Etat wallet invalide apres operation.")

    @classmethod
    def mutate_wallet(
        cls,
        *,
        wallet: Wallet,
        amount: Decimal,
        entry_type: str,
        direction: str,
        available_delta: Decimal = ZERO,
        locked_delta: Decimal = ZERO,
        pending_delta: Decimal = ZERO,
        reference: str = "",
        idempotency_key: str = "",
        order=None,
        escrow=None,
        counterparty=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> WalletLedgerEntry:
        with transaction.atomic():
            wallet = Wallet.objects.select_for_update().get(id=wallet.id)
            amount = quantize_money(amount)
            if amount < ZERO:
                raise FinancialInvariantError("Le montant ledger doit etre positif.")

            if idempotency_key:
                existing = WalletLedgerEntry.objects.filter(wallet=wallet, idempotency_key=idempotency_key).first()
                if existing:
                    # Audit ref: [NEW-001] replay-safe mirror — if the previous
                    # mutate_wallet was killed between WalletLedgerEntry creation
                    # and the ledger post, the entry exists but the
                    # LedgerTransaction does NOT. Re-attempt the mirror so the
                    # two ledgers converge instead of drifting permanently.
                    if getattr(settings, "LEDGER_DOUBLE_ENTRY_ENABLED", True):
                        _ensure_ledger_mirror_present(existing)
                    return existing

            available_before = quantize_money(wallet.available_balance)
            locked_before = quantize_money(wallet.locked_balance)
            pending_before = quantize_money(wallet.pending_balance)

            cls._apply_deltas(
                wallet=wallet,
                available_delta=quantize_money(available_delta),
                locked_delta=quantize_money(locked_delta),
                pending_delta=quantize_money(pending_delta),
            )
            wallet.sync_legacy_balances()
            wallet.save(
                update_fields=[
                    "available_balance",
                    "locked_balance",
                    "pending_balance",
                    "balance",
                    "blocked_balance",
                    "updated_at",
                ]
            )
            wallet_entry = WalletLedgerEntry.objects.create(
                wallet=wallet,
                direction=direction,
                entry_type=entry_type,
                amount=amount,
                available_before=available_before,
                available_after=wallet.available_balance,
                locked_before=locked_before,
                locked_after=wallet.locked_balance,
                pending_before=pending_before,
                pending_after=wallet.pending_balance,
                reference=reference,
                idempotency_key=idempotency_key,
                order=order,
                escrow=escrow,
                counterparty=counterparty,
                created_by=created_by,
                metadata=metadata or {},
            )

            # Audit ref: [FIN-001] mirror to double-entry ledger inside the
            # same atomic block — if it raises, the wallet mutation rolls back
            # and the two ledgers stay consistent.
            _mirror_wallet_entry_to_ledger(wallet_entry)

            return wallet_entry

    @classmethod
    def credit_available(
        cls,
        *,
        wallet: Wallet,
        amount,
        entry_type: str = LedgerEntryType.DEPOSIT,
        reference: str = "",
        idempotency_key: str = "",
        order=None,
        escrow=None,
        counterparty=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> WalletLedgerEntry:
        money = quantize_money(amount)
        return cls.mutate_wallet(
            wallet=wallet,
            amount=money,
            entry_type=entry_type,
            direction=LedgerDirection.CREDIT,
            available_delta=money,
            reference=reference,
            idempotency_key=idempotency_key,
            order=order,
            escrow=escrow,
            counterparty=counterparty,
            created_by=created_by,
            metadata=metadata,
        )

    @classmethod
    def debit_available(
        cls,
        *,
        wallet: Wallet,
        amount,
        entry_type: str = LedgerEntryType.WITHDRAWAL,
        reference: str = "",
        idempotency_key: str = "",
        order=None,
        escrow=None,
        counterparty=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> WalletLedgerEntry:
        money = quantize_money(amount)
        return cls.mutate_wallet(
            wallet=wallet,
            amount=money,
            entry_type=entry_type,
            direction=LedgerDirection.DEBIT,
            available_delta=-money,
            reference=reference,
            idempotency_key=idempotency_key,
            order=order,
            escrow=escrow,
            counterparty=counterparty,
            created_by=created_by,
            metadata=metadata,
        )

    @classmethod
    def lock_from_available(
        cls,
        *,
        wallet: Wallet,
        amount,
        reference: str = "",
        idempotency_key: str = "",
        order=None,
        escrow=None,
        counterparty=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> WalletLedgerEntry:
        money = quantize_money(amount)
        return cls.mutate_wallet(
            wallet=wallet,
            amount=money,
            entry_type=LedgerEntryType.ESCROW_TRANSFER,
            direction=LedgerDirection.DEBIT,
            available_delta=-money,
            locked_delta=money,
            reference=reference,
            idempotency_key=idempotency_key,
            order=order,
            escrow=escrow,
            counterparty=counterparty,
            created_by=created_by,
            metadata=metadata,
        )

    @classmethod
    def unlock_to_available(
        cls,
        *,
        wallet: Wallet,
        amount,
        entry_type: str = LedgerEntryType.REFUND,
        reference: str = "",
        idempotency_key: str = "",
        order=None,
        escrow=None,
        counterparty=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> WalletLedgerEntry:
        money = quantize_money(amount)
        return cls.mutate_wallet(
            wallet=wallet,
            amount=money,
            entry_type=entry_type,
            direction=LedgerDirection.CREDIT,
            available_delta=money,
            locked_delta=-money,
            reference=reference,
            idempotency_key=idempotency_key,
            order=order,
            escrow=escrow,
            counterparty=counterparty,
            created_by=created_by,
            metadata=metadata,
        )

    @classmethod
    def release_locked_to_available(
        cls,
        *,
        wallet: Wallet,
        amount,
        entry_type: str = LedgerEntryType.ESCROW_RELEASE,
        reference: str = "",
        idempotency_key: str = "",
        order=None,
        escrow=None,
        counterparty=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> WalletLedgerEntry:
        return cls.unlock_to_available(
            wallet=wallet,
            amount=amount,
            entry_type=entry_type,
            reference=reference,
            idempotency_key=idempotency_key,
            order=order,
            escrow=escrow,
            counterparty=counterparty,
            created_by=created_by,
            metadata=metadata,
        )

    @classmethod
    def transfer_available(
        cls,
        *,
        from_wallet: Wallet,
        to_wallet: Wallet,
        amount,
        entry_type: str,
        reference: str,
        order=None,
        escrow=None,
        created_by=None,
        metadata: dict | None = None,
    ) -> tuple[WalletLedgerEntry, WalletLedgerEntry]:
        money = quantize_money(amount)
        with transaction.atomic():
            debit = cls.debit_available(
                wallet=from_wallet,
                amount=money,
                entry_type=entry_type,
                reference=reference,
                order=order,
                escrow=escrow,
                counterparty=to_wallet.owner,
                created_by=created_by,
                metadata=metadata,
            )
            credit = cls.credit_available(
                wallet=to_wallet,
                amount=money,
                entry_type=entry_type,
                reference=reference,
                order=order,
                escrow=escrow,
                counterparty=from_wallet.owner,
                created_by=created_by,
                metadata=metadata,
            )
        return debit, credit
