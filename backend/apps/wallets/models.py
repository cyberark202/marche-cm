from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class PaymentProvider(models.TextChoices):
    MOBILE_MONEY = "MOBILE_MONEY", "Mobile Money"
    ORANGE_MONEY = "ORANGE_MONEY", "Orange Money"
    VISA = "VISA", "Visa"
    MASTERCARD = "MASTERCARD", "MasterCard"
    PAYPAL = "PAYPAL", "PayPal"


class Wallet(models.Model):
    owner = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="wallet")
    available_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    locked_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    pending_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # Legacy fields kept for backward compatibility with existing API clients.
    balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    blocked_balance = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(check=models.Q(available_balance__gte=0), name="wallet_available_gte_zero"),
            models.CheckConstraint(check=models.Q(locked_balance__gte=0), name="wallet_locked_gte_zero"),
            models.CheckConstraint(check=models.Q(pending_balance__gte=0), name="wallet_pending_gte_zero"),
        ]

    @property
    def total_balance(self):
        return self.available_balance + self.locked_balance + self.pending_balance

    def sync_legacy_balances(self):
        self.blocked_balance = self.locked_balance
        self.balance = self.total_balance

    def save(self, *args, **kwargs):
        update_fields = kwargs.get("update_fields")
        using_legacy_write = False
        if update_fields:
            fields = set(update_fields)
            using_legacy_write = bool(fields.intersection({"balance", "blocked_balance"})) and not bool(
                fields.intersection({"available_balance", "locked_balance", "pending_balance"})
            )
        else:
            using_legacy_write = (
                Decimal(str(self.available_balance or 0)) == Decimal("0")
                and Decimal(str(self.locked_balance or 0)) == Decimal("0")
                and Decimal(str(self.pending_balance or 0)) == Decimal("0")
                and (
                    Decimal(str(self.balance or 0)) > Decimal("0")
                    or Decimal(str(self.blocked_balance or 0)) > Decimal("0")
                )
            )
        if using_legacy_write:
            self.locked_balance = Decimal(str(self.blocked_balance or 0)).quantize(Decimal("0.01"))
            inferred_available = Decimal(str(self.balance or 0)) - self.locked_balance - Decimal(str(self.pending_balance or 0))
            if inferred_available < 0:
                inferred_available = Decimal("0.00")
            self.available_balance = inferred_available.quantize(Decimal("0.01"))
        self.sync_legacy_balances()
        if update_fields:
            merged = set(update_fields)
            merged.update({"available_balance", "locked_balance", "pending_balance", "balance", "blocked_balance"})
            kwargs["update_fields"] = list(merged)
        super().save(*args, **kwargs)


class TransactionStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    SUCCESS = "SUCCESS", "Succes"
    FAILED = "FAILED", "Echec"
    REVERSED = "REVERSED", "Annule"


class WalletTransaction(models.Model):
    wallet = models.ForeignKey(Wallet, on_delete=models.CASCADE, related_name="transactions")
    provider = models.CharField(max_length=20, choices=PaymentProvider.choices, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    kind = models.CharField(max_length=30)  # TOPUP, WITHDRAWAL, ORDER_DEBIT, ESCROW_RELEASE
    status = models.CharField(max_length=10, choices=TransactionStatus.choices, default=TransactionStatus.PENDING)
    reference = models.CharField(max_length=120, blank=True)
    external_transaction_id = models.CharField(max_length=80, blank=True, db_index=True)
    idempotency_key = models.CharField(max_length=80, blank=True, db_index=True)
    failure_reason = models.CharField(max_length=240, blank=True)
    cinetpay_transfered = models.BooleanField(default=False)
    metadata = models.JSONField(default=dict, blank=True)
    reconciled_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["wallet", "idempotency_key"],
                condition=~models.Q(idempotency_key=""),
                name="uniq_wallet_idempotency_key",
            ),
            models.UniqueConstraint(
                fields=["external_transaction_id"],
                condition=~models.Q(external_transaction_id=""),
                name="uniq_wallet_external_transaction_id",
            ),
        ]


class WalletOtpChallenge(models.Model):
    PURPOSE_CHOICES = (
        ("TOPUP", "Topup"),
        ("WITHDRAW", "Withdraw"),
    )

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="wallet_otp_challenges")
    purpose = models.CharField(max_length=16, choices=PURPOSE_CHOICES)
    otp_code = models.CharField(max_length=6)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class WalletWebhookEvent(models.Model):
    provider = models.CharField(max_length=40, default="NOTCHPAY")
    event_id = models.CharField(max_length=120, unique=True)
    payload = models.JSONField(default=dict, blank=True)
    processed = models.BooleanField(default=False)
    processed_at = models.DateTimeField(null=True, blank=True)
    processing_error = models.CharField(max_length=240, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class LedgerDirection(models.TextChoices):
    CREDIT = "CREDIT", "Credit"
    DEBIT = "DEBIT", "Debit"


class LedgerEntryType(models.TextChoices):
    DEPOSIT = "DEPOSIT", "Depot"
    WITHDRAWAL = "WITHDRAWAL", "Retrait"
    REFUND = "REFUND", "Remboursement"
    ESCROW_TRANSFER = "ESCROW_TRANSFER", "Transfert vers escrow"
    ESCROW_RELEASE = "ESCROW_RELEASE", "Liberation escrow"
    PAYOUT = "PAYOUT", "Payout"
    COMMISSION = "COMMISSION", "Commission"


class WalletLedgerEntry(models.Model):
    wallet = models.ForeignKey(Wallet, on_delete=models.CASCADE, related_name="ledger_entries")
    direction = models.CharField(max_length=8, choices=LedgerDirection.choices)
    entry_type = models.CharField(max_length=20, choices=LedgerEntryType.choices)
    amount = models.DecimalField(max_digits=12, decimal_places=2, validators=[MinValueValidator(0)])
    status = models.CharField(max_length=10, choices=TransactionStatus.choices, default=TransactionStatus.SUCCESS)
    available_before = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    available_after = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    locked_before = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    locked_after = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    pending_before = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    pending_after = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    reference = models.CharField(max_length=160, blank=True)
    idempotency_key = models.CharField(max_length=100, blank=True, db_index=True)
    order = models.ForeignKey("orders.Order", null=True, blank=True, on_delete=models.SET_NULL, related_name="ledger_entries")
    escrow = models.ForeignKey(
        "orders.OrderEscrow",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="ledger_entries",
    )
    counterparty = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="wallet_ledger_counterparty_entries",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="wallet_ledger_created_entries",
    )
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["wallet", "idempotency_key"],
                condition=~models.Q(idempotency_key=""),
                name="uniq_wallet_ledger_idempotency_key",
            ),
        ]


class PayoutRetryStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    RETRYING = "RETRYING", "Retry en cours"
    SUCCESS = "SUCCESS", "Succes"
    FAILED = "FAILED", "Echec definitif"


class PayoutRetryJob(models.Model):
    transaction = models.OneToOneField(WalletTransaction, on_delete=models.CASCADE, related_name="payout_retry")
    status = models.CharField(max_length=10, choices=PayoutRetryStatus.choices, default=PayoutRetryStatus.PENDING)
    attempt_count = models.PositiveSmallIntegerField(default=0)
    max_attempts = models.PositiveSmallIntegerField(default=5)
    next_retry_at = models.DateTimeField()
    last_error = models.CharField(max_length=240, blank=True)
    locked_at = models.DateTimeField(null=True, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["next_retry_at", "created_at"]
        indexes = [
            models.Index(fields=["status", "next_retry_at"], name="idx_payout_retry_status_due"),
        ]


class ReconciliationStatus(models.TextChoices):
    OK = "OK", "Conforme"
    ALERT = "ALERT", "Alerte"
    FAILED = "FAILED", "Echec"


class DailyReconciliationReport(models.Model):
    provider = models.CharField(max_length=40, default="NOTCHPAY")
    report_date = models.DateField(unique=True)
    provider_reported_balance = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    provider_net_flow = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    wallets_available_total = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    wallets_locked_total = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    wallets_pending_total = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    escrow_locked_total = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    platform_commission_total = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    unresolved_payout_count = models.PositiveIntegerField(default=0)
    variance = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    status = models.CharField(max_length=10, choices=ReconciliationStatus.choices, default=ReconciliationStatus.OK)
    details = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-report_date", "-created_at"]


# ---------------------------------------------------------------------------
# Fraud detection — persisted fraud events for audit trail
# ---------------------------------------------------------------------------

class FraudDecision(models.TextChoices):
    ALLOW = "allow", "Autorise"
    HOLD = "hold", "En attente de revue"
    BLOCK = "block", "Bloque"


class FraudEvent(models.Model):
    """
    Immutable record of every fraud evaluation that produced a non-zero score.
    Used for: manual review, compliance audit, ML training, pattern analysis.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="fraud_events",
    )
    event_type = models.CharField(max_length=40)        # withdraw, transfer, etc.
    risk_score = models.PositiveSmallIntegerField()      # 0–100
    decision = models.CharField(max_length=10, choices=FraudDecision.choices)
    metadata = models.JSONField(default=dict, blank=True)
    resolved = models.BooleanField(default=False)
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="resolved_fraud_events",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "decision", "resolved"]),
            models.Index(fields=["risk_score", "resolved"]),
        ]

    def __str__(self) -> str:
        return f"FraudEvent({self.user_id}, score={self.risk_score}, {self.decision})"
