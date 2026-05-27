"""
Ledger Service — the ONLY layer that may post ledger entries.

NEVER modify balances directly. ALWAYS post via LedgerService.

Design:
  - All posting is atomic (SELECT FOR UPDATE on accounts)
  - Entries are immutable after posting
  - Idempotency enforced via LedgerTransaction.idempotency_key (unique constraint)
  - Running balance computed as: previous_balance ± amount
"""
from __future__ import annotations

import logging
from decimal import Decimal
from typing import TypedDict

from django.conf import settings
from django.db import transaction

from .models import (
    AccountSubType,
    AccountType,
    EntryDirection,
    LedgerAccount,
    LedgerEntry,
    LedgerTransaction,
    TransactionType,
)

logger = logging.getLogger(__name__)


class EntrySpec(TypedDict):
    account: LedgerAccount
    direction: str  # DEBIT | CREDIT
    amount: Decimal
    description: str


class LedgerService:
    """
    Posts balanced double-entry ledger transactions.
    All methods run in an atomic transaction.
    """

    def get_or_create_user_wallet_account(self, user) -> LedgerAccount:
        account, _ = LedgerAccount.objects.get_or_create(
            sub_type=AccountSubType.USER_WALLET,
            owner=user,
            defaults={
                "account_type": AccountType.ASSET,
                "currency": "XAF",
                "description": f"Wallet {user.username}",
            },
        )
        return account

    def get_or_create_escrow_account(self, user) -> LedgerAccount:
        account, _ = LedgerAccount.objects.get_or_create(
            sub_type=AccountSubType.ESCROW_HOLD,
            owner=user,
            defaults={
                "account_type": AccountType.ASSET,
                "currency": "XAF",
                "description": f"Escrow hold {user.username}",
            },
        )
        return account

    def get_platform_revenue_account(self) -> LedgerAccount:
        account, _ = LedgerAccount.objects.get_or_create(
            sub_type=AccountSubType.PLATFORM_REVENUE,
            owner=None,
            defaults={
                "account_type": AccountType.REVENUE,
                "currency": "XAF",
                "description": "Revenus plateforme Marché CM",
            },
        )
        return account

    def get_provider_float_account(self) -> LedgerAccount:
        account, _ = LedgerAccount.objects.get_or_create(
            sub_type=AccountSubType.PROVIDER_FLOAT,
            owner=None,
            defaults={
                "account_type": AccountType.ASSET,
                "currency": "XAF",
                "description": "Float fournisseur paiement (NotchPay)",
            },
        )
        return account

    def get_payout_clearing_account(self) -> LedgerAccount:
        account, _ = LedgerAccount.objects.get_or_create(
            sub_type=AccountSubType.PAYOUT_CLEARING,
            owner=None,
            defaults={
                "account_type": AccountType.ASSET,
                "currency": "XAF",
                "description": "Compensation payout en transit",
            },
        )
        return account

    def get_dispute_reserve_account(self, user=None) -> LedgerAccount:
        account, _ = LedgerAccount.objects.get_or_create(
            sub_type=AccountSubType.DISPUTE_RESERVE,
            owner=user,
            defaults={
                "account_type": AccountType.ASSET,
                "currency": "XAF",
                "description": "Réserve litige",
            },
        )
        return account

    def _get_account_balance(self, account: LedgerAccount) -> Decimal:
        """Return the current balance.

        Audit ref: V11.3 — prefer the materialised `cached_balance` column so
        we no longer scan the LedgerEntry index on every post. Falls back to
        the historical SELECT MAX path only when `cached_balance_updated_at`
        is NULL (fresh account, pre-V11.3 row). The reconciliation task
        `verify_cached_balances` repairs drift if it ever appears.
        """
        if account.cached_balance_updated_at is not None:
            return account.cached_balance
        last_entry = account.entries.order_by("-created_at").first()
        if last_entry is None:
            return Decimal("0.00")
        return last_entry.running_balance

    def _post_entries(
        self,
        transaction_type: str,
        idempotency_key: str,
        total_amount: Decimal,
        entries: list[EntrySpec],
        initiated_by=None,
        reference: str = "",
        description: str = "",
        correlation_id: str = "",
        metadata: dict | None = None,
    ) -> LedgerTransaction:
        """
        Core posting method. Creates LedgerTransaction + LedgerEntries atomically.
        Validates that debits == credits.
        Uses SELECT FOR UPDATE on all accounts to prevent race conditions.
        """
        total_debits = sum(e["amount"] for e in entries if e["direction"] == EntryDirection.DEBIT)
        total_credits = sum(e["amount"] for e in entries if e["direction"] == EntryDirection.CREDIT)
        if total_debits != total_credits:
            raise ValueError(
                f"Ledger imbalance: debits={total_debits} != credits={total_credits}"
            )

        with transaction.atomic():
            # Lock all accounts to prevent concurrent writes
            account_ids = [e["account"].pk for e in entries]
            locked_accounts = {
                acc.pk: acc
                for acc in LedgerAccount.objects.select_for_update().filter(pk__in=account_ids)
            }

            ledger_tx = LedgerTransaction.objects.create(
                transaction_type=transaction_type,
                idempotency_key=idempotency_key,
                reference=reference,
                description=description,
                currency="XAF",
                total_amount=total_amount,
                initiated_by=initiated_by,
                correlation_id=correlation_id or "",
                metadata=metadata or {},
            )

            # Audit ref: V11.3 — track the running balance per account inside
            # this transaction. Multiple entries can hit the same account
            # (e.g. commission split) and we must apply them in order before
            # writing back to cached_balance.
            from django.utils import timezone as _tz
            running_per_account: dict = {}

            entry_instances = []
            for spec in entries:
                account = locked_accounts[spec["account"].pk]
                if account.pk in running_per_account:
                    prev_balance = running_per_account[account.pk]
                else:
                    prev_balance = self._get_account_balance(account)

                if spec["direction"] == EntryDirection.DEBIT:
                    if account.is_debit_normal:
                        new_balance = prev_balance + spec["amount"]
                    else:
                        new_balance = prev_balance - spec["amount"]
                else:
                    if account.is_debit_normal:
                        new_balance = prev_balance - spec["amount"]
                    else:
                        new_balance = prev_balance + spec["amount"]

                running_per_account[account.pk] = new_balance
                entry_instances.append(LedgerEntry(
                    transaction=ledger_tx,
                    account=account,
                    direction=spec["direction"],
                    amount=spec["amount"],
                    running_balance=new_balance,
                    description=spec.get("description", ""),
                ))

            LedgerEntry.objects.bulk_create(entry_instances)

            # Materialise the new balances on the account rows in one UPDATE
            # per account — still under the SELECT FOR UPDATE locks above.
            now = _tz.now()
            for acc_pk, balance in running_per_account.items():
                LedgerAccount.objects.filter(pk=acc_pk).update(
                    cached_balance=balance,
                    cached_balance_updated_at=now,
                )

            logger.info(
                "ledger_transaction_posted",
                extra={
                    "tx_type": transaction_type,
                    "idempotency_key": idempotency_key,
                    "total": str(total_amount),
                    "entries": len(entries),
                },
            )
            return ledger_tx

    def post_topup(
        self,
        user,
        amount: Decimal,
        idempotency_key: str,
        reference: str = "",
        correlation_id: str = "",
    ) -> LedgerTransaction:
        """
        User topup: money arrives from payment provider.
        DR User Wallet Asset (+)
        CR Provider Float (platform records receipt)
        """
        wallet_account = self.get_or_create_user_wallet_account(user)
        provider_account = self.get_provider_float_account()

        return self._post_entries(
            transaction_type=TransactionType.TOPUP,
            idempotency_key=idempotency_key,
            total_amount=amount,
            entries=[
                {"account": wallet_account, "direction": EntryDirection.DEBIT, "amount": amount,
                 "description": f"Topup wallet {user.username}"},
                {"account": provider_account, "direction": EntryDirection.CREDIT, "amount": amount,
                 "description": "Provider float credit"},
            ],
            initiated_by=user,
            reference=reference,
            correlation_id=correlation_id,
        )

    def post_withdrawal(
        self,
        user,
        amount: Decimal,
        idempotency_key: str,
        reference: str = "",
        correlation_id: str = "",
    ) -> LedgerTransaction:
        """
        User withdrawal:
        DR Provider Float (decreases — money leaves provider)
        CR User Wallet (user's balance decreases)
        """
        wallet_account = self.get_or_create_user_wallet_account(user)
        provider_account = self.get_provider_float_account()

        return self._post_entries(
            transaction_type=TransactionType.WITHDRAWAL,
            idempotency_key=idempotency_key,
            total_amount=amount,
            entries=[
                {"account": provider_account, "direction": EntryDirection.DEBIT, "amount": amount,
                 "description": "Provider float debit (withdrawal)"},
                {"account": wallet_account, "direction": EntryDirection.CREDIT, "amount": amount,
                 "description": f"Retrait wallet {user.username}"},
            ],
            initiated_by=user,
            reference=reference,
            correlation_id=correlation_id,
        )

    def post_escrow_lock(
        self,
        buyer,
        seller,
        amount: Decimal,
        idempotency_key: str,
        order_reference: str = "",
        correlation_id: str = "",
    ) -> LedgerTransaction:
        """
        Order payment — lock funds in escrow:
        DR Seller Escrow Hold (escrow increases for seller)
        CR Buyer Wallet (buyer's balance decreases)
        """
        buyer_wallet = self.get_or_create_user_wallet_account(buyer)
        seller_escrow = self.get_or_create_escrow_account(seller)

        return self._post_entries(
            transaction_type=TransactionType.ESCROW_LOCK,
            idempotency_key=idempotency_key,
            total_amount=amount,
            entries=[
                {"account": seller_escrow, "direction": EntryDirection.DEBIT, "amount": amount,
                 "description": f"Escrow lock - commande {order_reference}"},
                {"account": buyer_wallet, "direction": EntryDirection.CREDIT, "amount": amount,
                 "description": f"Débit acheteur - commande {order_reference}"},
            ],
            initiated_by=buyer,
            reference=order_reference,
            correlation_id=correlation_id,
        )

    def post_escrow_release(
        self,
        seller,
        amount: Decimal,
        commission: Decimal,
        idempotency_key: str,
        order_reference: str = "",
        correlation_id: str = "",
    ) -> LedgerTransaction:
        """
        Release escrow to seller (minus commission):
        DR Provider Float (payout in transit)
        DR Platform Revenue (commission)
        CR Seller Escrow Hold
        """
        seller_wallet = self.get_or_create_user_wallet_account(seller)
        seller_escrow = self.get_or_create_escrow_account(seller)
        platform_revenue = self.get_platform_revenue_account()
        total = amount + commission

        entries = [
            {"account": seller_escrow, "direction": EntryDirection.CREDIT, "amount": total,
             "description": f"Libération escrow - {order_reference}"},
            {"account": seller_wallet, "direction": EntryDirection.DEBIT, "amount": amount,
             "description": f"Paiement vendeur - {order_reference}"},
        ]
        if commission > 0:
            entries.append({
                "account": platform_revenue,
                "direction": EntryDirection.DEBIT,
                "amount": commission,
                "description": f"Commission plateforme - {order_reference}",
            })

        return self._post_entries(
            transaction_type=TransactionType.ESCROW_RELEASE,
            idempotency_key=idempotency_key,
            total_amount=total,
            entries=entries,
            initiated_by=seller,
            reference=order_reference,
            correlation_id=correlation_id,
        )

    def post_escrow_refund(
        self,
        buyer,
        seller,
        amount: Decimal,
        idempotency_key: str,
        order_reference: str = "",
        correlation_id: str = "",
    ) -> LedgerTransaction:
        """
        Refund buyer (escrow → buyer wallet):
        DR Buyer Wallet (buyer gets money back)
        CR Seller Escrow Hold (escrow decreases)
        """
        buyer_wallet = self.get_or_create_user_wallet_account(buyer)
        seller_escrow = self.get_or_create_escrow_account(seller)

        return self._post_entries(
            transaction_type=TransactionType.ESCROW_REFUND,
            idempotency_key=idempotency_key,
            total_amount=amount,
            entries=[
                {"account": seller_escrow, "direction": EntryDirection.CREDIT, "amount": amount,
                 "description": f"Remboursement escrow - {order_reference}"},
                {"account": buyer_wallet, "direction": EntryDirection.DEBIT, "amount": amount,
                 "description": f"Remboursement acheteur - {order_reference}"},
            ],
            initiated_by=buyer,
            reference=order_reference,
            correlation_id=correlation_id,
        )

    def post_dispute_freeze(
        self,
        seller,
        amount: Decimal,
        idempotency_key: str,
        dispute_reference: str = "",
        correlation_id: str = "",
    ) -> LedgerTransaction:
        """
        Freeze escrow funds for dispute:
        DR Dispute Reserve (frozen)
        CR Seller Escrow Hold (escrow decreases)
        """
        seller_escrow = self.get_or_create_escrow_account(seller)
        dispute_reserve = self.get_dispute_reserve_account(seller)

        return self._post_entries(
            transaction_type=TransactionType.DISPUTE_FREEZE,
            idempotency_key=idempotency_key,
            total_amount=amount,
            entries=[
                {"account": seller_escrow, "direction": EntryDirection.CREDIT, "amount": amount,
                 "description": f"Gel litige {dispute_reference}"},
                {"account": dispute_reserve, "direction": EntryDirection.DEBIT, "amount": amount,
                 "description": f"Réserve litige {dispute_reference}"},
            ],
            reference=dispute_reference,
            correlation_id=correlation_id,
        )

    def get_account_balance(self, account: LedgerAccount) -> Decimal:
        return self._get_account_balance(account)

    def get_user_wallet_balance(self, user) -> Decimal:
        account = self.get_or_create_user_wallet_account(user)
        return self._get_account_balance(account)


ledger_service = LedgerService()
