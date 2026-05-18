from __future__ import annotations

from decimal import Decimal, InvalidOperation

from django.db import transaction

from .models import LedgerDirection, LedgerEntryType, Wallet, WalletLedgerEntry

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
            return WalletLedgerEntry.objects.create(
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
