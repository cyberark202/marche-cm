import uuid
from django.conf import settings
from django.db import models


class KYCDocumentType(models.TextChoices):
    NATIONAL_ID = "NATIONAL_ID", "Carte nationale d'identité"
    PASSPORT = "PASSPORT", "Passeport"
    DRIVERS_LICENSE = "DRIVERS_LICENSE", "Permis de conduire"
    RCCM = "RCCM", "Registre Commerce (RCCM)"
    TAX_CERTIFICATE = "TAX_CERTIFICATE", "Attestation fiscale"
    PROOF_OF_ADDRESS = "PROOF_OF_ADDRESS", "Justificatif de domicile"
    SELFIE = "SELFIE", "Selfie liveness"


class KYCStatus(models.TextChoices):
    PENDING = "PENDING", "En attente de revue"
    UNDER_REVIEW = "UNDER_REVIEW", "En cours de revue"
    APPROVED = "APPROVED", "Approuvé"
    REJECTED = "REJECTED", "Rejeté"
    EXPIRED = "EXPIRED", "Expiré"
    RESUBMIT_REQUIRED = "RESUBMIT_REQUIRED", "Nouvelle soumission requise"


class KYCLevel(models.IntegerChoices):
    NONE = 0, "Aucun"
    BASIC = 1, "KYC Basique (ID)"
    ADVANCED = 2, "KYC Avancé (Business)"


class KYCApplication(models.Model):
    """
    KYC application submitted by a user.
    One application per KYC level attempt.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="kyc_applications",
    )
    target_level = models.PositiveSmallIntegerField(choices=KYCLevel.choices)
    status = models.CharField(
        max_length=20,
        choices=KYCStatus.choices,
        default=KYCStatus.PENDING,
        db_index=True,
    )
    submitted_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reviewed_kyc_applications",
    )
    rejection_reason = models.TextField(blank=True)
    risk_score = models.PositiveSmallIntegerField(default=0)
    ocr_result = models.JSONField(default=dict, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = "compliance"
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["user", "status"], name="idx_kyc_user_status"),
            models.Index(fields=["status", "created_at"], name="idx_kyc_status_ts"),
        ]


class KYCDocument(models.Model):
    """
    A single document uploaded as part of a KYC application.
    File stored in object storage (S3/R2) — key stored here, never local path.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    application = models.ForeignKey(
        KYCApplication,
        on_delete=models.CASCADE,
        related_name="documents",
    )
    document_type = models.CharField(max_length=24, choices=KYCDocumentType.choices)
    storage_key = models.CharField(max_length=400)  # S3/R2 object key
    file_hash = models.CharField(max_length=64)  # SHA-256 for integrity
    file_size_bytes = models.PositiveIntegerField(default=0)
    mime_type = models.CharField(max_length=60, blank=True)
    ocr_extracted = models.JSONField(default=dict, blank=True)
    is_verified = models.BooleanField(default=False)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        app_label = "compliance"


class AMLScreening(models.Model):
    """
    Anti-Money Laundering screening result for a user transaction or application.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="aml_screenings",
    )
    screening_type = models.CharField(max_length=30)  # ONBOARDING | TRANSACTION | PERIODIC
    entity_type = models.CharField(max_length=60, blank=True)
    entity_id = models.CharField(max_length=80, blank=True)
    result = models.CharField(max_length=10, default="CLEAR")  # CLEAR | HIT | PENDING
    hits = models.JSONField(default=list)  # list of matched sanctions/PEP entries
    provider = models.CharField(max_length=40, default="INTERNAL")
    screened_at = models.DateTimeField(auto_now_add=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        app_label = "compliance"
        ordering = ["-screened_at"]


class SanctionsList(models.Model):
    """Local sanctions/PEP list for offline screening."""
    list_name = models.CharField(max_length=60)  # UN_SANCTIONS | OFAC | EU_SANCTIONS
    entry_type = models.CharField(max_length=20)  # INDIVIDUAL | ENTITY | VESSEL
    full_name = models.CharField(max_length=300, db_index=True)
    aliases = models.JSONField(default=list)
    country = models.CharField(max_length=4, blank=True)
    date_of_birth = models.CharField(max_length=20, blank=True)
    reference_id = models.CharField(max_length=100, blank=True)
    is_active = models.BooleanField(default=True)
    last_updated = models.DateTimeField(auto_now=True)

    class Meta:
        app_label = "compliance"
        indexes = [
            models.Index(fields=["list_name", "is_active"], name="idx_sanctions_list_active"),
        ]
