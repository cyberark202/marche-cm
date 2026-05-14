from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
import re
from django.conf import settings

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

    CERTIFICATION_TYPES = {
        "CERT_BUSINESS_REGISTRATION",
        "CERT_TAX_CLEARANCE",
        "CERT_EXPORT_LICENSE",
        "CERT_IMPORT_LICENSE",
        "CERT_QUALITY_STANDARD",
        "CERT_INSURANCE",
    }

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
        )
        read_only_fields = (
            "user",
            "status",
            "reviewed_by",
            "created_at",
            "reviewed_at",
            "preview_image",
        )

    def validate_doc_type(self, value):
        if value not in self.CERTIFICATION_TYPES:
            raise serializers.ValidationError(_("Le document doit être une certification valide."))
        request = self.context.get("request")
        if request and request.user and request.user.is_authenticated:
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
    role = serializers.ChoiceField(
        choices=[UserRole.BUYER, UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT],
        default=UserRole.BUYER,
        required=False,
    )
    company_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    air_price_per_kg = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True,
    )
    sea_price_per_kg = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True,
    )

    class Meta:
        model = User
        fields = (
            "name", "phone_number", "email", "password",
            "country_code", "city", "role",
            "company_name", "air_price_per_kg", "sea_price_per_kg",
        )
        extra_kwargs = {"email": {"required": True}}

    def validate_email(self, value):
        normalized = (value or "").strip().lower()
        if not normalized:
            raise serializers.ValidationError("Email obligatoire.")
        if User.objects.filter(email__iexact=normalized).exists():
            raise serializers.ValidationError("Cet email est deja utilise.")
        return normalized

    def validate_name(self, value):
        name = (value or "").strip()
        if len(name) < 2:
            raise serializers.ValidationError("Nom obligatoire.")
        if User.objects.filter(first_name__iexact=name).exists():
            raise serializers.ValidationError("Ce nom est deja utilise. Choisissez un autre nom.")
        return name

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def validate(self, attrs):
        role = attrs.get("role", UserRole.BUYER)
        if role in {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}:
            if not (attrs.get("company_name") or "").strip():
                raise serializers.ValidationError(
                    {"company_name": "Nom de l'entreprise requis pour les comptes professionnels."}
                )
        if role == UserRole.TRANSIT_AGENT:
            air = attrs.get("air_price_per_kg")
            sea = attrs.get("sea_price_per_kg")
            if air is None or air <= 0:
                raise serializers.ValidationError(
                    {"air_price_per_kg": "Prix transport aerien requis et superieur a 0."}
                )
            if sea is None or sea <= 0:
                raise serializers.ValidationError(
                    {"sea_price_per_kg": "Prix transport maritime requis et superieur a 0."}
                )
        return attrs

    def create(self, validated_data):
        from apps.logistics.models import TransportProfile

        full_name = validated_data.pop("name").strip()
        password = validated_data.pop("password")
        company_name = (validated_data.pop("company_name", "") or "").strip()
        air_price_per_kg = validated_data.pop("air_price_per_kg", None)
        sea_price_per_kg = validated_data.pop("sea_price_per_kg", None)
        role = validated_data.get("role", UserRole.BUYER)

        base_username = re.sub(r"[^a-zA-Z0-9_]+", "_", full_name.lower()).strip("_") or "user"
        username = base_username[:120]
        if User.objects.filter(username__iexact=username).exists():
            raise serializers.ValidationError({"name": "Ce nom de compte est deja utilise."})
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
        # Aucun PIN par defaut: l'utilisateur le definira via /api/wallets/wallet/set_pin/.
        user.save()
        if role == UserRole.TRANSIT_AGENT:
            TransportProfile.objects.update_or_create(
                user=user,
                defaults={
                    "company_name": company_name or f"Transit {user.username}",
                    "coverage_countries": user.country_code or "CM",
                    "air_price_per_kg": air_price_per_kg,
                    "sea_price_per_kg": sea_price_per_kg,
                    "is_active": True,
                },
            )
        update_user_location(user, force=True)
        return user


class LoginRequestSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    password = serializers.CharField(required=True, write_only=True)

    def validate(self, attrs):
        email = (attrs.get("email") or "").strip().lower()
        password = attrs.get("password") or ""
        user = User.objects.filter(email__iexact=email).first()
        if user is None or not user.check_password(password):
            raise AuthenticationFailed("Identifiants invalides.")
        if not user.is_active:
            raise AuthenticationFailed("Compte non active. Verifiez votre email.")
        attrs["email"] = email
        attrs["user"] = user
        return attrs


class LoginCodeVerifySerializer(serializers.Serializer):
    challenge_token = serializers.CharField(required=True)
    code = serializers.RegexField(r"^\d{6}$", required=True)
