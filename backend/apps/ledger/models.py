"""
Double-entry ledger for Marché CM.

Accounting model:
  - LedgerAccount: an account in the chart of accounts
  - LedgerTransaction: the header (what happened, idempotency key)
  - LedgerEntry: the lines (debit/credit) — must balance per transaction

Rule: SUM(DEBIT entries) == SUM(CREDIT entries) for every LedgerTransaction.

Account types (normal balance):
  ASSET       → normal debit  (wallet balances, escrow holds)
  LIABILITY   → normal credit (money owed to external provider)
  EQUITY      → normal credit
  REVENUE     → normal credit (platform commission)
  EXPENSE     → normal debit

Sub-account types:
  USER_WALLET          → user's available balance (ASSET)
  ESCROW_HOLD          → funds locked in escrow (ASSET)
  PROVIDER_FLOAT       → funds deposited with payment provider (ASSET)
  PLATFORM_REVENUE     → platform commission earned (REVENUE)
  PLATFORM_LIABILITY   → funds owed to users (LIABILITY)
  PAYOUT_CLEARING      → funds in transit for payout (ASSET)
  DISPUTE_RESERVE      → funds frozen for dispute (ASSET)
  SYSTEM_SUSPENSE      → suspense account for reconciliation (ASSET)
"""
import uuid
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class AccountType(models.TextChoices):
    ASSET = "ASSET", "Actif"
    LIABILITY = "LIABILITY", "Passif"
    EQUITY = "EQUITY", "Capitaux propres"
    REVENUE = "REVENUE", "Produits"
    EXPENSE = "EXPENSE", "Charges"


class AccountSubType(models.TextChoices):
    USER_WALLET = "USER_WALLET", "Wallet utilisateur"
    ESCROW_HOLD = "ESCROW_HOLD", "Séquestre escrow"
    PROVIDER_FLOAT = "PROVIDER_FLOAT", "Float fournisseur paiement"
    PLATFORM_REVENUE = "PLATFORM_REVENUE", "Revenus plateforme"
    PLATFORM_LIABILITY = "PLATFORM_LIABILITY", "Dettes plateforme"
    PAYOUT_CLEARING = "PAYOUT_CLEARING", "Compensation payout"
    DISPUTE_RESERVE = "DISPUTE_RESERVE", "Réserve litige"
    SYSTEM_SUSPENSE = "SYSTEM_SUSPENSE", "Compte de suspens"


DEBIT_NORMAL_TYPES = {AccountType.ASSET, AccountType.EXPENSE}


class LedgerAccount(models.Model):
    """
    Chart of accounts entry.
    One LedgerAccount per user wallet (sub_type=USER_WALLET).
    Platform accounts are shared (owner=None).
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    account_type = models.CharField(max_length=12, choices=AccountType.choices)
    sub_type = models.CharField(max_length=24, choices=AccountSubType.choices)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True, blank=True,
        on_delete=models.PROTECT,
        related_name="ledger_accounts",
    )
    currency = models.CharField(max_length=3, default="XAF")
    description = models.CharField(max_length=200, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    # Audit ref: V11.3 — materialised balance for hot-account performance.
    # Avoids `SELECT running_balance FROM ledger_entry WHERE account=... ORDER
    # BY -created_at LIMIT 1` on every post (especially painful on shared
    # platform accounts: PROVIDER_FLOAT, PLATFORM_REVENUE, PAYOUT_CLEARING).
    # Kept in sync atomically inside _post_entries under SELECT FOR UPDATE.
    # A reconciliation task (apps.ledger.tasks.verify_cached_balances) can
    # recompute from LedgerEntry and surface any drift.
    cached_balance = models.DecimalField(
        max_digits=18, decimal_places=2, default=Decimal("0.00"),
    )
    cached_balance_updated_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["sub_type", "owner"], name="idx_lacct_subtype_owner"),
            models.Index(fields=["account_type", "is_active"], name="idx_lacct_type_active"),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["sub_type", "owner"],
                condition=models.Q(owner__isnull=False),
                name="uniq_lacct_user",
            ),
        ]

    @property
    def is_debit_normal(self) -> bool:
        return self.account_type in DEBIT_NORMAL_TYPES

    def __str__(self) -> str:
        return f"LedgerAccount({self.sub_type}, owner={self.owner_id}, {self.currency})"


class TransactionType(models.TextChoices):
    TOPUP = "TOPUP", "Dépôt"
    WITHDRAWAL = "WITHDRAWAL", "Retrait"
    ORDER_PAYMENT = "ORDER_PAYMENT", "Paiement commande"
    ESCROW_LOCK = "ESCROW_LOCK", "Verrouillage escrow"
    ESCROW_RELEASE = "ESCROW_RELEASE", "Libération escrow"
    ESCROW_REFUND = "ESCROW_REFUND", "Remboursement escrow"
    ESCROW_FREEZE = "ESCROW_FREEZE", "Gel escrow"
    PAYOUT = "PAYOUT", "Payout vendeur"
    COMMISSION = "COMMISSION", "Commission plateforme"
    DISPUTE_FREEZE = "DISPUTE_FREEZE", "Gel litige"
    DISPUTE_RESOLUTION = "DISPUTE_RESOLUTION", "Résolution litige"
    REFUND = "REFUND", "Remboursement"
    ADJUSTMENT = "ADJUSTMENT", "Ajustement"
    TRANSFER = "TRANSFER", "Transfert interne"


class LedgerTransaction(models.Model):
    """
    Transaction header. Immutable after creation.
    All entries referencing this transaction must balance (sum debits == sum credits).
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    transaction_type = models.CharField(max_length=24, choices=TransactionType.choices, db_index=True)
    idempotency_key = models.CharField(max_length=120, unique=True)
    reference = models.CharField(max_length=160, blank=True)
    description = models.CharField(max_length=500, blank=True)
    currency = models.CharField(max_length=3, default="XAF")
    total_amount = models.DecimalField(
        max_digits=14, decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))],
    )
    initiated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True, blank=True,
        on_delete=models.SET_NULL,
        related_name="initiated_ledger_transactions",
    )
    correlation_id = models.CharField(max_length=80, blank=True, db_index=True)
    metadata = models.JSONField(default=dict, blank=True)
    posted_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-posted_at"]
        indexes = [
            models.Index(fields=["transaction_type", "posted_at"], name="idx_ledger_tx_type_date"),
            models.Index(fields=["idempotency_key"], name="idx_ledger_tx_idempotency"),
        ]

    def __str__(self) -> str:
        return f"LedgerTx({self.transaction_type}, {self.total_amount} {self.currency})"


class EntryDirection(models.TextChoices):
    DEBIT = "DEBIT", "Débit"
    CREDIT = "CREDIT", "Crédit"


class LedgerEntry(models.Model):
    """
    Individual ledger entry (debit or credit).
    Immutable — never update, never delete.
    Each transaction must have entries that balance: SUM(DEBIT) == SUM(CREDIT).
    running_balance = balance of the account AFTER this entry is posted.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    transaction = models.ForeignKey(
        LedgerTransaction,
        on_delete=models.PROTECT,
        related_name="entries",
    )
    account = models.ForeignKey(
        LedgerAccount,
        on_delete=models.PROTECT,
        related_name="entries",
    )
    direction = models.CharField(max_length=8, choices=EntryDirection.choices)
    amount = models.DecimalField(
        max_digits=14, decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))],
    )
    running_balance = models.DecimalField(
        max_digits=14, decimal_places=2,
        help_text="Balance of account AFTER this entry",
    )
    description = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
        indexes = [
            models.Index(fields=["account", "created_at"], name="idx_ledger_entry_account_date"),
            models.Index(fields=["transaction"], name="idx_ledger_entry_tx"),
        ]

    def __str__(self) -> str:
        return f"LedgerEntry({self.direction}, {self.amount}, account={self.account_id})"
