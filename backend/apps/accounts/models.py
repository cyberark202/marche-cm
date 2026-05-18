from django.contrib.auth.models import AbstractUser
from django.db import models
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.utils import timezone
import random
import string
from datetime import timedelta

from .encrypted_fields import EncryptedTextField


class UserRole(models.TextChoices):
    GENERAL_ADMIN = "GENERAL_ADMIN", "Administrateur General"
    SUPPLIER = "SUPPLIER", "Fournisseur"
    WHOLESALER = "WHOLESALER", "Grossiste"
    TRANSIT_AGENT = "TRANSIT_AGENT", "Transitaire"
    BUYER = "BUYER", "Acheteur"


class User(AbstractUser):
    REF_PREFIX = "USR"
    role = models.CharField(max_length=20, choices=UserRole.choices, default=UserRole.BUYER)
    reference_code = models.CharField(max_length=24, unique=True, blank=True, null=True, db_index=True)
    phone_number = EncryptedTextField(blank=True, default="")
    avatar = models.ImageField(upload_to="avatars/", blank=True, null=True)
    country_code = models.CharField(max_length=4, default="CM")
    city = EncryptedTextField(blank=True, default="")
    location_label = EncryptedTextField(blank=True, default="")
    location_latitude = models.FloatField(null=True, blank=True)
    location_longitude = models.FloatField(null=True, blank=True)
    location_provider = models.CharField(max_length=40, blank=True)
    location_updated_at = models.DateTimeField(null=True, blank=True)
    is_verified = models.BooleanField(default=False)
    trust_score = models.DecimalField(max_digits=4, decimal_places=2, default=0)
    is_online = models.BooleanField(default=False)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    kyc_level = models.PositiveSmallIntegerField(default=0)  # 0=none, 1=basic, 2=advanced
    wallet_pin_hash = models.CharField(max_length=128, blank=True)
    wallet_pin_failed_attempts = models.PositiveSmallIntegerField(default=0)
    wallet_pin_locked_until = models.DateTimeField(null=True, blank=True)

    def __str__(self) -> str:
        return f"{self.username} ({self.role})"

    @classmethod
    def _generate_reference_code(cls) -> str:
        alphabet = string.ascii_uppercase + string.digits
        return f"{cls.REF_PREFIX}-{''.join(random.choice(alphabet) for _ in range(10))}"

    @classmethod
    def _next_available_reference_code(cls) -> str:
        for _ in range(50):
            candidate = cls._generate_reference_code()
            if not cls.objects.filter(reference_code=candidate).exists():
                return candidate
        raise RuntimeError("Impossible de generer un code de reference utilisateur unique.")

    def save(self, *args, **kwargs):
        if not self.reference_code:
            self.reference_code = self._next_available_reference_code()
        super().save(*args, **kwargs)

    def set_wallet_pin(self, pin: str) -> None:
        self.wallet_pin_hash = make_password(pin)

    def check_wallet_pin(self, pin: str) -> bool:
        if not self.wallet_pin_hash:
            return False
        return check_password(pin, self.wallet_pin_hash)

    def is_wallet_pin_locked(self) -> bool:
        if not self.wallet_pin_locked_until:
            return False
        return self.wallet_pin_locked_until > timezone.now()

    def register_wallet_pin_failure(self, *, max_attempts: int, lock_minutes: int) -> bool:
        self.wallet_pin_failed_attempts = (self.wallet_pin_failed_attempts or 0) + 1
        locked = False
        if self.wallet_pin_failed_attempts >= max(1, int(max_attempts)):
            self.wallet_pin_locked_until = timezone.now() + timedelta(minutes=max(1, int(lock_minutes)))
            self.wallet_pin_failed_attempts = 0
            locked = True
        self.save(update_fields=["wallet_pin_failed_attempts", "wallet_pin_locked_until"])
        return locked

    def reset_wallet_pin_failures(self) -> None:
        if self.wallet_pin_failed_attempts == 0 and self.wallet_pin_locked_until is None:
            return
        self.wallet_pin_failed_attempts = 0
        self.wallet_pin_locked_until = None
        self.save(update_fields=["wallet_pin_failed_attempts", "wallet_pin_locked_until"])


class AuditLog(models.Model):
    actor = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name="audit_logs")
    action = models.CharField(max_length=120)
    action_key = models.CharField(max_length=120, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class ComplianceDocument(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="compliance_documents")
    doc_type = models.CharField(max_length=40)  # RCCM, ID_CARD, TAX_CERT, INSURANCE
    file = models.FileField(upload_to="compliance/")
    preview_image = models.ImageField(upload_to="compliance/previews/", blank=True, null=True)
    status = models.CharField(max_length=20, default="PENDING")  # PENDING, APPROVED, REJECTED
    reviewed_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True, related_name="reviewed_compliance_documents"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["user", "doc_type"], name="uniq_user_compliance_doc_type"),
        ]


class EmailVerificationToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="email_verification_tokens")
    token = models.CharField(max_length=128, unique=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class LoginVerificationCode(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="login_verification_codes")
    challenge_token = models.CharField(max_length=128, unique=True)
    code = models.CharField(max_length=6)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class SensitiveActionChallenge(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="sensitive_action_challenges")
    action_key = models.CharField(max_length=80)
    challenge_token = models.CharField(max_length=128, unique=True, db_index=True)
    # PBKDF2-SHA256 hash of the OTP — plaintext is NEVER persisted (OWASP ASVS V2.7).
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    used_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


# ---------------------------------------------------------------------------
# TOTP MFA — OWASP ASVS V2.8
# ---------------------------------------------------------------------------

class UserMFAConfig(models.Model):
    """Stores TOTP configuration and hashed backup codes per user."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="mfa_config",
    )
    # TOTP secret encrypted at rest via EncryptedTextField.
    totp_secret = EncryptedTextField(blank=True, default="")
    totp_enabled = models.BooleanField(default=False)
    # JSON list of PBKDF2-hashed backup codes.
    backup_code_hashes = models.JSONField(default=list, blank=True)
    totp_enrolled_at = models.DateTimeField(null=True, blank=True)
    last_used_step = models.BigIntegerField(default=0)  # anti-replay
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "MFA Configuration"

    def __str__(self) -> str:
        return f"MFA({self.user_id}, enabled={self.totp_enabled})"


# ---------------------------------------------------------------------------
# Trusted Device — device binding & fingerprinting
# ---------------------------------------------------------------------------

class TrustedDevice(models.Model):
    """
    Tracks known devices per user for anomaly detection and progressive trust.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="trusted_devices",
    )
    device_fingerprint = models.CharField(max_length=64, db_index=True)
    user_agent_hash = models.CharField(max_length=64, blank=True)
    ip_address_last = models.GenericIPAddressField(null=True, blank=True)
    is_trusted = models.BooleanField(default=False)
    trust_granted_at = models.DateTimeField(null=True, blank=True)
    first_seen_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [("user", "device_fingerprint")]
        ordering = ["-last_seen_at"]

    def __str__(self) -> str:
        return f"Device({self.user_id}, trusted={self.is_trusted})"


class FCMToken(models.Model):
    """Firebase Cloud Messaging registration token per device."""

    DEVICE_TYPES = [("android", "Android"), ("ios", "iOS"), ("web", "Web")]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="fcm_tokens",
    )
    registration_id = models.TextField(unique=True)
    type = models.CharField(max_length=10, choices=DEVICE_TYPES, default="android")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self) -> str:
        return f"FCMToken({self.user_id}, {self.type})"
