import uuid
from django.conf import settings
from django.db import models


class RiskLevel(models.TextChoices):
    LOW = "LOW", "Faible (0-30)"
    MEDIUM = "MEDIUM", "Moyen (31-60)"
    HIGH = "HIGH", "Élevé (61-80)"
    CRITICAL = "CRITICAL", "Critique (81-100)"


class FraudDecision(models.TextChoices):
    ALLOW = "ALLOW", "Autorisé"
    REVIEW = "REVIEW", "En révision"
    BLOCK = "BLOCK", "Bloqué"


class FraudSignalType(models.TextChoices):
    VELOCITY = "VELOCITY", "Vélocité (trop de txn)"
    AMOUNT_SPIKE = "AMOUNT_SPIKE", "Montant anormal"
    DEVICE_MISMATCH = "DEVICE_MISMATCH", "Appareil inconnu"
    GEO_ANOMALY = "GEO_ANOMALY", "Anomalie géographique"
    MULTIPLE_ACCOUNTS = "MULTIPLE_ACCOUNTS", "Comptes multiples"
    SUSPICIOUS_PATTERN = "SUSPICIOUS_PATTERN", "Pattern suspect"
    KYC_MISMATCH = "KYC_MISMATCH", "Incohérence KYC"
    AML_FLAG = "AML_FLAG", "Signal AML"
    DUPLICATE_DOC = "DUPLICATE_DOC", "Document en double"
    BLACKLISTED = "BLACKLISTED", "Liste noire"


class FraudAssessment(models.Model):
    """
    Result of a fraud scoring assessment.
    One per significant user action (withdrawal, order, KYC, etc.)
    Immutable after creation.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="fraud_assessments",
    )
    action_type = models.CharField(max_length=40, db_index=True)  # WITHDRAWAL, ORDER, KYC_SUBMIT, etc.
    risk_score = models.PositiveSmallIntegerField()  # 0–100
    risk_level = models.CharField(max_length=10, choices=RiskLevel.choices)
    decision = models.CharField(max_length=8, choices=FraudDecision.choices)
    signals = models.JSONField(default=list)  # list of {type, weight, detail}
    entity_type = models.CharField(max_length=60, blank=True)
    entity_id = models.CharField(max_length=80, blank=True)
    correlation_id = models.CharField(max_length=80, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    device_fingerprint = models.CharField(max_length=64, blank=True)
    reviewed = models.BooleanField(default=False)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reviewed_fraud_assessments",
    )
    review_outcome = models.CharField(max_length=10, blank=True)  # CONFIRMED | DISMISSED
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = "fraud"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "decision", "reviewed"], name="idx_fraud_user_decision"),
            models.Index(fields=["risk_score", "reviewed"], name="idx_fraud_score_reviewed"),
            models.Index(fields=["action_type", "created_at"], name="idx_fraud_action_ts"),
        ]


class UserRiskProfile(models.Model):
    """Rolling risk profile per user — updated after each assessment."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="risk_profile",
    )
    overall_score = models.PositiveSmallIntegerField(default=0)
    assessment_count = models.PositiveIntegerField(default=0)
    last_assessed_at = models.DateTimeField(null=True, blank=True)
    is_watchlisted = models.BooleanField(default=False)
    watchlist_reason = models.CharField(max_length=300, blank=True)
    is_blocked = models.BooleanField(default=False)
    blocked_reason = models.CharField(max_length=300, blank=True)
    blocked_at = models.DateTimeField(null=True, blank=True)
    lifetime_withdrawal_total = models.DecimalField(max_digits=16, decimal_places=2, default=0)
    last_30d_withdrawal_total = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    failed_auth_count = models.PositiveSmallIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = "fraud"


class BlacklistEntry(models.Model):
    """Global blacklist — phone numbers, IPs, device fingerprints."""
    ENTRY_TYPES = [
        ("PHONE", "Numéro de téléphone"),
        ("IP", "Adresse IP"),
        ("DEVICE", "Empreinte appareil"),
        ("EMAIL", "Email"),
        ("IBAN", "IBAN"),
    ]
    entry_type = models.CharField(max_length=10, choices=ENTRY_TYPES)
    value = models.CharField(max_length=200, db_index=True)
    reason = models.CharField(max_length=300)
    added_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="blacklist_additions",
    )
    expires_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = "fraud"
        unique_together = [("entry_type", "value")]
