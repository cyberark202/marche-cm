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
    currency = models.CharField(max_length=3, default="XAF")
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
        """Mirror modern fields into the legacy fields (one-way).

        Audit ref: [FIN-002] Wallet.save() previously had a "legacy write"
        branch that inferred the modern fields from `balance` and
        `blocked_balance` when the modern fields looked zero. That branch
        corrupted state whenever a caller (admin script, test, legacy code)
        touched the legacy fields after a successful mutation — silently
        zeroing `pending_balance` and producing phantom losses.

        The legacy fields are now strictly DERIVED from the modern fields:
          * `blocked_balance` mirrors `locked_balance`
          * `balance` mirrors `available + locked + pending`
        Any direct assignment to a legacy field is overwritten on save.
        Use WalletAccountingService.mutate_wallet() to change balances.
        """
        self.blocked_balance = self.locked_balance
        self.balance = self.total_balance

    def save(self, *args, **kwargs):
        # Always re-derive legacy fields from modern fields (one-way mirror).
        # The previous "legacy write" inference path is removed — see
        # sync_legacy_balances docstring for the [FIN-002] rationale.
        self.sync_legacy_balances()
        update_fields = kwargs.get("update_fields")
        if update_fields:
            merged = set(update_fields)
            # Whenever any balance moves we must also persist the derived
            # legacy mirrors so they stay consistent on partial saves.
            if merged & {"available_balance", "locked_balance", "pending_balance"}:
                merged.update({"balance", "blocked_balance"})
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


# ---------------------------------------------------------------------------
# Idempotency — dedicated request-level lock table (Phase 1)
# ---------------------------------------------------------------------------

class IdempotencyRecord(models.Model):
    """
    Dedicated idempotency table providing:
      - Request-body hash validation (prevents key reuse with different payload)
      - SELECT FOR UPDATE locking (eliminates concurrent-request race conditions)
      - Response snapshot (idempotent replays return identical responses)
      - TTL-based expiry (24 h for financial ops, configurable per endpoint)

    This sits ABOVE the WalletTransaction.idempotency_key DB constraint.
    The constraint remains as a last-resort safety net; this table provides
    the correct UX (clean cached response instead of IntegrityError).
    """

    STATUS_PROCESSING = "processing"
    STATUS_COMPLETE = "complete"
    STATUS_FAILED = "failed"

    STATUS_CHOICES = [
        (STATUS_PROCESSING, "En cours"),
        (STATUS_COMPLETE, "Termine"),
        (STATUS_FAILED, "Echec"),
    ]

    key = models.CharField(max_length=120)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="idempotency_records",
    )
    endpoint = models.CharField(max_length=60)
    # SHA-256 of request body with PIN/secrets stripped — prevents key reuse fraud.
    request_hash = models.CharField(max_length=64)
    response_snapshot = models.JSONField(null=True, blank=True)
    status = models.CharField(max_length=12, choices=STATUS_CHOICES, default=STATUS_PROCESSING)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["key", "user", "endpoint"],
                name="uniq_idempotency_key_user_endpoint",
            ),
        ]
        indexes = [
            models.Index(fields=["expires_at"], name="idx_idempotency_expires_at"),
        ]

    def __str__(self) -> str:
        return f"IdempotencyRecord({self.endpoint}, {self.status})"


# ---------------------------------------------------------------------------
# Transaction state audit log (Phase 2)
# ---------------------------------------------------------------------------

class WalletTransactionStateLog(models.Model):
    """
    Immutable log of every state transition for a WalletTransaction.

    Rules:
      - Never update rows — append only.
      - Records the from/to status, optional extended_status, reason, and actor.
      - Used for: compliance audit, debugging, reconciliation, ML training.
    """

    transaction = models.ForeignKey(
        WalletTransaction,
        on_delete=models.CASCADE,
        related_name="state_logs",
    )
    from_status = models.CharField(max_length=20, blank=True)
    to_status = models.CharField(max_length=20)
    # Richer status detail that does not replace the API-visible status field.
    # Examples: "provider_pending", "provider_confirmed", "settlement_pending",
    #           "failed_retryable", "failed_final", "reconciliation_pending".
    extended_status = models.CharField(max_length=40, blank=True)
    reason = models.CharField(max_length=240, blank=True)
    actor_id = models.IntegerField(null=True, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
        indexes = [
            models.Index(fields=["transaction", "created_at"], name="idx_tx_state_log_tx_ts"),
        ]

    def __str__(self) -> str:
        return f"StateLog(tx={self.transaction_id}, {self.from_status}->{self.to_status})"
