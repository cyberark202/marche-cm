from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
import re
import secrets
from django.conf import settings
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from .location_service import update_user_location
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
        name = (value or "").strip()
        if not name:
            return name
        if len(name) < 2:
            raise serializers.ValidationError(_("Le nom affiché doit contenir au moins 2 caractères."))
        exists = User.objects.filter(first_name__iexact=name).exclude(id=self.instance.id)
        if exists.exists():
            raise serializers.ValidationError(_("Ce nom affiché est déjà utilisé."))
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

    CERTIFICATION_TYPES = {
        "CERT_BUSINESS_REGISTRATION",
        "CERT_TAX_CLEARANCE",
        "CERT_EXPORT_LICENSE",
        "CERT_IMPORT_LICENSE",
        "CERT_QUALITY_STANDARD",
        "CERT_INSURANCE",
    }

    # KYC identity documents (transitaire / driver onboarding).
    DRIVER_DOC_TYPES = {
        "CNI",
        "CNI_VERSO",
        "PASSPORT",
        "DRIVER_LICENSE",
    }

    ALLOWED_DOC_TYPES = CERTIFICATION_TYPES | DRIVER_DOC_TYPES

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
        update_user_location(user, force=True)
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
        update_user_location(user, force=True)
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

        if not user.is_active:
            raise AuthenticationFailed("Compte non active. Verifiez votre email.")

        attrs["email"] = email
        attrs["user"] = user
        return attrs


class LoginCodeVerifySerializer(serializers.Serializer):
    challenge_token = serializers.CharField(required=True)
    code = serializers.RegexField(r"^\d{6}$", required=True)
