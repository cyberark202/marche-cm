from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
import re
import secrets
from django.conf import settings
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from .kyc_constants import CERTIFICATION_DOC_TYPES, IDENTITY_DOC_TYPES
from .location_service import enqueue_user_geocode
from .upload_security import scrub_image_metadata, validate_uploaded_file
from .models import ComplianceDocument, User, UserRole

def validate_phone_format(value):
    """Utilitaire de validation centralisé pour les numéros de téléphone."""
    phone = (value or "").strip()
    cleaned = "".join(ch for ch in phone if ch.isdigit() or ch == "+")
    if not cleaned.startswith("+"):
        raise serializers.ValidationError(
            _("Numéro de téléphone invalide : indicatif pays obligatoire (ex: +237...).")
        )
    digits = cleaned[1:]
    if not digits.isdigit() or len(digits) < 8:
        raise serializers.ValidationError(_("Numéro de téléphone invalide."))
    return f"+{digits}"


def generate_unique_username(full_name):
    """Derive a unique username from a display name (anti-enumeration safe).

    Audit ref: [H-005] — collisions are resolved silently with a numeric suffix
    (then a random suffix past 50 attempts) so registration never leaks whether
    an account already exists.
    """
    base_username = re.sub(r"[^a-zA-Z0-9_]+", "_", (full_name or "").lower()).strip("_") or "user"
    username = base_username[:120]
    suffix = 1
    while User.objects.filter(username__iexact=username).exists():
        if suffix > 50:
            return f"{base_username[:110]}_{secrets.token_hex(4)}"
        suffix += 1
        username = f"{base_username[:117]}_{suffix}"
    return username


def validate_registration_email(value):
    """Shared registration email check (M2 anti-enumeration)."""
    normalized = (value or "").strip().lower()
    if not normalized:
        raise serializers.ValidationError("Email obligatoire.")
    if User.objects.filter(email__iexact=normalized).exists():
        raise serializers.ValidationError(
            "Ce compte ne peut pas etre cree. Essayez de vous connecter ou utilisez un autre email."
        )
    return normalized

class UserSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="first_name", read_only=True)
    avatar_url = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id",
            "reference_code",
            "username",
            "name",
            "email",
            "role",
            "avatar_url",
            "country_code",
            "city",
            "location_label",
            "location_latitude",
            "location_longitude",
            "is_verified",
            "trust_score",
            "kyc_level",
            "is_online",
            "last_seen_at",
        )

    def get_avatar_url(self, obj):
        if not obj.avatar:
            return ""
        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.avatar.url)
        return obj.avatar.url


class ProfileUpdateSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source="first_name", required=False, allow_blank=True, max_length=150)
    remove_avatar = serializers.BooleanField(required=False, default=False, write_only=True)

    class Meta:
        model = User
        fields = ("username", "name", "email", "phone_number", "avatar", "remove_avatar")
        extra_kwargs = {
            "username": {"required": False},
            "email": {"required": False},
            "phone_number": {"required": False},
            "avatar": {"required": False},
        }

    def validate_username(self, value):
        username = (value or "").strip()
        if len(username) < 3:
            raise serializers.ValidationError(_("Le nom du compte doit contenir au moins 3 caractères."))
        exists = User.objects.filter(username__iexact=username).exclude(id=self.instance.id)
        if exists.exists():
            raise serializers.ValidationError(_("Ce nom de compte est déjà utilisé."))
        return username

    def validate_name(self, value):
        # Audit ref: [m-1] Display name (first_name) is NOT globally unique —
        # harmonised with RegisterSerializer, which dropped this check (H-005,
        # anti-enumeration). Two users may legitimately share a display name.
        name = (value or "").strip()
        if not name:
            return name
        if len(name) < 2:
            raise serializers.ValidationError(_("Le nom affiché doit contenir au moins 2 caractères."))
        return name

    def validate_email(self, value):
        email = (value or "").strip().lower()
        if not email:
            raise serializers.ValidationError(_("Email invalide."))
        exists = User.objects.filter(email__iexact=email).exclude(id=self.instance.id)
        if exists.exists():
            raise serializers.ValidationError(_("Cet email est déjà utilisé."))
        return email

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def validate_avatar(self, value):
        validate_uploaded_file(
            value,
            field_label="Avatar",
            allowed_extensions={".png", ".jpg", ".jpeg", ".webp"},
            max_mb=settings.MAX_UPLOAD_IMAGE_MB,
            allowed_content_types={"image/png", "image/jpeg", "image/webp"},
        )
        return scrub_image_metadata(value)

    def update(self, instance, validated_data):
        remove_avatar = bool(validated_data.pop("remove_avatar", False))
        first_name = validated_data.pop("first_name", None)

        if "username" in validated_data:
            instance.username = validated_data["username"].strip()
        if "email" in validated_data:
            instance.email = validated_data["email"].strip().lower()
        if "phone_number" in validated_data:
            instance.phone_number = validated_data["phone_number"].strip()
        if first_name is not None:
            instance.first_name = first_name.strip()
        if "avatar" in validated_data:
            instance.avatar = validated_data["avatar"]
        elif remove_avatar:
            if instance.avatar:
                instance.avatar.delete(save=False)
            instance.avatar = None

        instance.save()
        return instance


class ComplianceDocumentSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()
    preview_url = serializers.SerializerMethodField()
    signature_url = serializers.SerializerMethodField()
    # Write-only KYC consent inputs (catalogue screen 46). The PNG signature is
    # stored as `signature_image`; accepting the consent stamps a server-side
    # timestamp + version (legal proof of record).
    signature = serializers.ImageField(write_only=True, required=False)
    consent_accepted = serializers.BooleanField(write_only=True, required=False, default=False)

    # Audit ref: [M-2][M-3] single source of truth — see apps/accounts/kyc_constants.py.
    # CERTIFICATION_TYPES are unique-per-user; DRIVER_DOC_TYPES (identity docs,
    # incl. PROOF_ADDRESS / SELFIE) are re-submittable (replace on re-upload).
    CERTIFICATION_TYPES = CERTIFICATION_DOC_TYPES
    DRIVER_DOC_TYPES = IDENTITY_DOC_TYPES
    ALLOWED_DOC_TYPES = CERTIFICATION_DOC_TYPES | IDENTITY_DOC_TYPES

    class Meta:
        model = ComplianceDocument
        fields = (
            "id",
            "user",
            "doc_type",
            "file",
            "file_url",
            "preview_image",
            "preview_url",
            "status",
            "reviewed_by",
            "created_at",
            "reviewed_at",
            "signature",
            "signature_url",
            "consent_accepted",
            "consent_accepted_at",
            "consent_version",
        )
        read_only_fields = (
            "user",
            "status",
            "reviewed_by",
            "created_at",
            "reviewed_at",
            "preview_image",
            "consent_accepted_at",
            "consent_version",
        )

    def validate_doc_type(self, value):
        if value not in self.ALLOWED_DOC_TYPES:
            raise serializers.ValidationError(_("Type de document invalide."))
        request = self.context.get("request")
        if request and request.user and request.user.is_authenticated:
            # Driver KYC documents can be replaced (overwrite old ones)
            # Business certifications are unique per user.
            if value not in self.DRIVER_DOC_TYPES:
                exists = ComplianceDocument.objects.filter(user=request.user, doc_type=value)
                if self.instance:
                    exists = exists.exclude(id=self.instance.id)
                if exists.exists():
                    raise serializers.ValidationError(_("Une certification de ce type existe déjà pour cet utilisateur."))
        return value

    def validate_file(self, value):
        ext = str(getattr(value, "name", "") or "").lower()
        if ext.endswith((".png", ".jpg", ".jpeg", ".webp")):
            validate_uploaded_file(
                value,
                field_label="Certification image",
                allowed_extensions={".png", ".jpg", ".jpeg", ".webp"},
                max_mb=settings.MAX_UPLOAD_IMAGE_MB,
                allowed_content_types={"image/png", "image/jpeg", "image/webp"},
            )
            return scrub_image_metadata(value)
        validate_uploaded_file(
            value,
            field_label="Certification document",
            allowed_extensions={".pdf"},
            max_mb=settings.MAX_UPLOAD_DOCUMENT_MB,
            allowed_content_types={"application/pdf"},
        )
        return value

    def validate_signature(self, value):
        validate_uploaded_file(
            value,
            field_label="Signature",
            allowed_extensions={".png", ".jpg", ".jpeg"},
            max_mb=settings.MAX_UPLOAD_IMAGE_MB,
            allowed_content_types={"image/png", "image/jpeg"},
        )
        return scrub_image_metadata(value)

    def _apply_consent(self, validated_data):
        # Map the write-only consent inputs onto the model. Accepting consent
        # stamps a server-side timestamp + version for legal proof of record.
        signature = validated_data.pop("signature", None)
        consent = bool(validated_data.pop("consent_accepted", False))
        if signature is not None:
            validated_data["signature_image"] = signature
        if consent:
            validated_data["consent_accepted_at"] = timezone.now()
            validated_data["consent_version"] = getattr(
                settings, "KYC_CONSENT_VERSION", "1.0"
            )
        return validated_data

    def create(self, validated_data):
        return super().create(self._apply_consent(validated_data))

    def update(self, instance, validated_data):
        return super().update(instance, self._apply_consent(validated_data))

    def get_signature_url(self, obj):
        if not obj.signature_image:
            return ""
        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.signature_image.url)
        return obj.signature_image.url

    def get_file_url(self, obj):
        if not obj.file:
            return ""
        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.file.url)
        return obj.file.url

    def get_preview_url(self, obj):
        if not obj.preview_image:
            return ""
        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.preview_image.url)
        return obj.preview_image.url


class ManagedUserCreateSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=8)
    air_price_per_kg = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        required=False,
        write_only=True,
    )
    sea_price_per_kg = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        required=False,
        write_only=True,
    )

    class Meta:
        model = User
        fields = (
            "username",
            "email",
            "password",
            "role",
            "phone_number",
            "country_code",
            "city",
            "air_price_per_kg",
            "sea_price_per_kg",
        )

    def validate_role(self, value):
        allowed = {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}
        if value not in allowed:
            raise serializers.ValidationError("L'admin ne peut creer que fournisseur, grossiste ou transitaire.")
        return value

    def validate_username(self, value):
        username = (value or "").strip()
        if len(username) < 3:
            raise serializers.ValidationError("Le nom du compte doit contenir au moins 3 caracteres.")
        if User.objects.filter(username__iexact=username).exists():
            raise serializers.ValidationError("Ce nom de compte est deja utilise.")
        return username

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def validate(self, attrs):
        """Validation croisée pour les transitaires."""
        role = attrs.get("role")
        if role == UserRole.TRANSIT_AGENT:
            air = attrs.get("air_price_per_kg")
            sea = attrs.get("sea_price_per_kg")
            if air is None or air <= 0:
                raise serializers.ValidationError({"air_price_per_kg": "Prix par avion requis et > 0."})
            if sea is None or sea <= 0:
                raise serializers.ValidationError({"sea_price_per_kg": "Prix par bateau requis et > 0."})
        return attrs

    def create(self, validated_data):
        from apps.logistics.models import TransportProfile

        air_price_per_kg = validated_data.pop("air_price_per_kg", None)
        sea_price_per_kg = validated_data.pop("sea_price_per_kg", None)
        role = validated_data.get("role")

        password = validated_data.pop("password")
        user = User(**validated_data)
        user.set_password(password)
        # Aucun PIN par defaut: l'utilisateur le definira via /api/wallets/wallet/set_pin/.
        user.save()
        if role == UserRole.TRANSIT_AGENT:
            TransportProfile.objects.update_or_create(
                user=user,
                defaults={
                    "company_name": f"Transit {user.username}",
                    "coverage_countries": user.country_code or "CM",
                    "air_price_per_kg": air_price_per_kg,
                    "sea_price_per_kg": sea_price_per_kg,
                    "is_active": True,
                },
            )
        # Audit ref: [M-1] geocoding is offloaded to Celery so registration
        # returns immediately and is never blocked by the Nominatim HTTP call.
        enqueue_user_geocode(user)
        return user


class RegisterSerializer(serializers.ModelSerializer):
    name = serializers.CharField(write_only=True, required=True, min_length=2, max_length=150)
    phone_number = serializers.CharField(required=True, min_length=8, max_length=30)
    password = serializers.CharField(write_only=True, min_length=8)
    city = serializers.CharField(required=False, allow_blank=True, max_length=120)

    # M1 — Public self-registration is restricted to BUYER only.
    # Professional roles (SUPPLIER, WHOLESALER, TRANSIT_AGENT) require admin
    # approval and are assigned via ManagedUserCreateSerializer (admin-only).
    # Any role value submitted by the client is silently overridden.
    role = serializers.HiddenField(default=UserRole.BUYER)

    class Meta:
        model = User
        fields = (
            "name", "phone_number", "email", "password",
            "country_code", "city", "role",
        )
        extra_kwargs = {"email": {"required": True}}

    def validate_email(self, value):
        normalized = (value or "").strip().lower()
        if not normalized:
            raise serializers.ValidationError("Email obligatoire.")
        # M2 — Anti-enumeration: do not confirm whether the email is already
        # registered. A genuine user can log in or use password reset.
        if User.objects.filter(email__iexact=normalized).exists():
            raise serializers.ValidationError(
                "Ce compte ne peut pas etre cree. Essayez de vous connecter ou utilisez un autre email."
            )
        return normalized

    def validate_name(self, value):
        # Audit ref: [H-005] enum bypass via validate_name.
        # The previous existence check leaked whether a first_name was already
        # registered, breaking the anti-enumeration effort done on email. The
        # collision is now resolved silently in create() with a numeric suffix
        # on the derived username — first_name itself stays free-form.
        name = (value or "").strip()
        if len(name) < 2:
            raise serializers.ValidationError("Nom obligatoire.")
        if len(name) > 150:
            raise serializers.ValidationError("Nom trop long (150 caracteres max).")
        return name

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def validate(self, attrs):
        # Role is always BUYER for public registration (HiddenField above).
        return attrs

    def create(self, validated_data):
        # M1 — role is always BUYER (HiddenField). Professional accounts are
        # created exclusively via ManagedUserCreateSerializer (admin endpoint).
        full_name = validated_data.pop("name").strip()
        password = validated_data.pop("password")
        role = validated_data.get("role", UserRole.BUYER)

        base_username = re.sub(r"[^a-zA-Z0-9_]+", "_", full_name.lower()).strip("_") or "user"
        # Audit ref: [H-005] silently disambiguate username collisions instead of
        # leaking existence of accounts. Append a numeric suffix until free,
        # capped at 50 attempts (then random suffix) to bound DB hits.
        username = base_username[:120]
        suffix = 1
        while User.objects.filter(username__iexact=username).exists():
            if suffix > 50:
                username = f"{base_username[:110]}_{secrets.token_hex(4)}"
                break
            suffix += 1
            username = f"{base_username[:117]}_{suffix}"
        user = User(
            username=username,
            email=validated_data.get("email", ""),
            first_name=full_name,
            phone_number=validated_data.get("phone_number", ""),
            country_code=validated_data.get("country_code", "CM"),
            city=(validated_data.get("city", "") or "").strip(),
            role=role,
            is_active=True,
            is_verified=False,
        )
        user.set_password(password)
        user.save()
        # Audit ref: [M-1] geocoding is offloaded to Celery so registration
        # returns immediately and is never blocked by the Nominatim HTTP call.
        enqueue_user_geocode(user)
        return user


class SellerRegisterSerializer(serializers.ModelSerializer):
    """Role-scoped self-registration for the professional (seller) app.

    ISOLATION GUARANTEE: the role is constrained server-side to SUPPLIER or
    WHOLESALER. TRANSIT_AGENT has its own dedicated endpoint and GENERAL_ADMIN
    is never self-assignable. Any other value is rejected at validation time, so
    a tampered client cannot escalate privileges through this endpoint.
    """

    name = serializers.CharField(write_only=True, required=True, min_length=2, max_length=150)
    phone_number = serializers.CharField(required=True, min_length=8, max_length=30)
    password = serializers.CharField(write_only=True, min_length=8)
    city = serializers.CharField(required=False, allow_blank=True, max_length=120)
    # company_name is accepted for UX parity but is not stored on User; the
    # business identity is established later through compliance documents.
    company_name = serializers.CharField(write_only=True, required=False, allow_blank=True, max_length=180)
    role = serializers.ChoiceField(
        choices=[
            (UserRole.SUPPLIER, UserRole.SUPPLIER.label),
            (UserRole.WHOLESALER, UserRole.WHOLESALER.label),
        ]
    )

    class Meta:
        model = User
        fields = (
            "name", "phone_number", "email", "password",
            "country_code", "city", "role", "company_name",
        )
        extra_kwargs = {"email": {"required": True}}

    def validate_email(self, value):
        return validate_registration_email(value)

    def validate_name(self, value):
        name = (value or "").strip()
        if len(name) < 2:
            raise serializers.ValidationError("Nom obligatoire.")
        if len(name) > 150:
            raise serializers.ValidationError("Nom trop long (150 caracteres max).")
        return name

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def create(self, validated_data):
        full_name = validated_data.pop("name").strip()
        password = validated_data.pop("password")
        validated_data.pop("company_name", None)
        user = User(
            username=generate_unique_username(full_name),
            email=validated_data.get("email", ""),
            first_name=full_name,
            phone_number=validated_data.get("phone_number", ""),
            country_code=validated_data.get("country_code", "CM"),
            city=(validated_data.get("city", "") or "").strip(),
            role=validated_data["role"],
            is_active=True,
            is_verified=False,
        )
        user.set_password(password)
        user.save()
        # Audit ref: [M-1] geocoding is offloaded to Celery so registration
        # returns immediately and is never blocked by the Nominatim HTTP call.
        enqueue_user_geocode(user)
        return user


class DriverRegisterSerializer(serializers.ModelSerializer):
    """Role-scoped self-registration for the driver (transit) app.

    ISOLATION GUARANTEE: the role is forced to TRANSIT_AGENT via a HiddenField,
    so any role submitted by the client is ignored. A TransportProfile is
    provisioned with default (zero) pricing that the agent completes after KYC.
    """

    name = serializers.CharField(write_only=True, required=True, min_length=2, max_length=150)
    phone_number = serializers.CharField(required=True, min_length=8, max_length=30)
    password = serializers.CharField(write_only=True, min_length=8)
    vehicle_type = serializers.CharField(write_only=True, required=False, allow_blank=True, max_length=40)
    role = serializers.HiddenField(default=UserRole.TRANSIT_AGENT)

    class Meta:
        model = User
        fields = (
            "name", "phone_number", "email", "password",
            "country_code", "role", "vehicle_type",
        )
        extra_kwargs = {"email": {"required": True}}

    def validate_email(self, value):
        return validate_registration_email(value)

    def validate_name(self, value):
        name = (value or "").strip()
        if len(name) < 2:
            raise serializers.ValidationError("Nom obligatoire.")
        if len(name) > 150:
            raise serializers.ValidationError("Nom trop long (150 caracteres max).")
        return name

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def create(self, validated_data):
        from apps.logistics.models import TransportProfile

        full_name = validated_data.pop("name").strip()
        password = validated_data.pop("password")
        vehicle_type = (validated_data.pop("vehicle_type", "") or "").strip()
        user = User(
            username=generate_unique_username(full_name),
            email=validated_data.get("email", ""),
            first_name=full_name,
            phone_number=validated_data.get("phone_number", ""),
            country_code=validated_data.get("country_code", "CM"),
            role=UserRole.TRANSIT_AGENT,
            is_active=True,
            is_verified=False,
        )
        user.set_password(password)
        user.save()
        TransportProfile.objects.update_or_create(
            user=user,
            defaults={
                "company_name": f"Transit {user.username}",
                "coverage_countries": user.country_code or "CM",
                "vehicle_types": vehicle_type,
                "is_active": True,
            },
        )
        # Audit ref: [M-1] geocoding is offloaded to Celery so registration
        # returns immediately and is never blocked by the Nominatim HTTP call.
        enqueue_user_geocode(user)
        return user


class LoginRequestSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    password = serializers.CharField(required=True, write_only=True)

    # M2 — Constant-time dummy hash used when the user is not found.
    # This ensures the response time is indistinguishable from a real
    # failed authentication, preventing user enumeration via timing.
    _DUMMY_HASH = (
        "pbkdf2_sha256$600000$dummysalt0000000$"
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
    )

    def validate(self, attrs):
        from django.contrib.auth.hashers import check_password as _check_pw

        email = (attrs.get("email") or "").strip().lower()
        password = attrs.get("password") or ""
        user = User.objects.filter(email__iexact=email).first()

        if user is None:
            # Always run a real PBKDF2 comparison to equalise response time
            # regardless of whether the email exists in the database.
            _check_pw(password, self._DUMMY_HASH)
            raise AuthenticationFailed("Identifiants invalides.")

        if not user.check_password(password):
            raise AuthenticationFailed("Identifiants invalides.")

        # Audit ref: [M-6] suspended accounts get a clear message (checked before
        # the generic is_active branch, since suspension also clears is_active).
        if getattr(user, "is_suspended", False):
            raise AuthenticationFailed("Compte suspendu. Contactez le support.")

        if not user.is_active:
            raise AuthenticationFailed("Compte non active. Verifiez votre email.")

        attrs["email"] = email
        attrs["user"] = user
        return attrs


class LoginCodeVerifySerializer(serializers.Serializer):
    challenge_token = serializers.CharField(required=True)
    code = serializers.RegexField(r"^\d{6}$", required=True)
