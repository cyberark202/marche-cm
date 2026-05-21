"""
Driver-specific API views.

Endpoints reserved for role=DRIVER users only. All sensitive write operations
require IsAuthenticated + IsDriver permission.
"""

import re

from django.conf import settings
from rest_framework import permissions, response, serializers, status
from rest_framework.parsers import FormParser, MultiPartParser, JSONParser
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import ComplianceDocument, DriverProfile, User, UserRole, VehicleType
from .serializers import UserSerializer, validate_phone_format
from .security import write_audit_log
from .upload_security import scrub_image_metadata, validate_uploaded_file


class IsDriver(permissions.BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == UserRole.DRIVER
        )


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

class DriverRegisterSerializer(serializers.ModelSerializer):
    name = serializers.CharField(write_only=True, required=True, min_length=2, max_length=150)
    phone_number = serializers.CharField(required=True, min_length=8, max_length=30)
    password = serializers.CharField(write_only=True, min_length=8)
    vehicle_type = serializers.ChoiceField(
        choices=VehicleType.choices, default=VehicleType.MOTO, required=False
    )

    class Meta:
        model = User
        fields = ("name", "phone_number", "email", "password", "country_code", "vehicle_type")
        extra_kwargs = {"email": {"required": True}}

    def validate_email(self, value):
        normalized = (value or "").strip().lower()
        if not normalized:
            raise serializers.ValidationError("Email obligatoire.")
        if User.objects.filter(email__iexact=normalized).exists():
            raise serializers.ValidationError(
                "Ce compte ne peut pas être créé. Essayez de vous connecter ou utilisez un autre email."
            )
        return normalized

    def validate_name(self, value):
        name = (value or "").strip()
        if len(name) < 2:
            raise serializers.ValidationError("Nom obligatoire.")
        return name

    def validate_phone_number(self, value):
        return validate_phone_format(value)

    def create(self, validated_data):
        full_name = validated_data.pop("name").strip()
        password = validated_data.pop("password")
        vehicle_type = validated_data.pop("vehicle_type", VehicleType.MOTO)

        base_username = re.sub(r"[^a-zA-Z0-9_]+", "_", full_name.lower()).strip("_") or "driver"
        username = base_username[:120]
        suffix = 1
        while User.objects.filter(username__iexact=username).exists():
            username = f"{base_username[:115]}_{suffix}"
            suffix += 1

        user = User(
            username=username,
            email=validated_data.get("email", ""),
            first_name=full_name,
            phone_number=validated_data.get("phone_number", ""),
            country_code=validated_data.get("country_code", "CM"),
            role=UserRole.DRIVER,
            is_active=True,
            is_verified=False,
        )
        user.set_password(password)
        user.save()

        DriverProfile.objects.create(user=user, vehicle_type=vehicle_type)
        return user


class DriverRegisterView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "register"

    def post(self, request):
        if getattr(settings, "AUTH_LOCKDOWN", False):
            return response.Response(
                {"detail": "Les inscriptions sont temporairement désactivées."},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        serializer = DriverRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        write_audit_log(
            actor=user,
            action="Inscription livreur",
            metadata={"user_id": user.id, "country_code": user.country_code},
        )
        refresh = RefreshToken.for_user(user)
        return response.Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": UserSerializer(user).data,
            },
            status=status.HTTP_201_CREATED,
        )


# ---------------------------------------------------------------------------
# Driver profile
# ---------------------------------------------------------------------------

class DriverProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source="user.username", read_only=True)
    email = serializers.EmailField(source="user.email", read_only=True)
    name = serializers.CharField(source="user.first_name", read_only=True)
    is_approved = serializers.BooleanField(read_only=True)
    rating = serializers.DecimalField(max_digits=3, decimal_places=2, read_only=True)
    completed_deliveries = serializers.IntegerField(read_only=True)

    class Meta:
        model = DriverProfile
        fields = (
            "id", "username", "email", "name",
            "vehicle_type", "license_number",
            "rating", "completed_deliveries", "is_approved",
            "created_at", "updated_at",
        )
        read_only_fields = ("id", "created_at", "updated_at")


class DriverProfileView(APIView):
    permission_classes = [IsDriver]

    def _get_profile(self, user):
        profile, _ = DriverProfile.objects.get_or_create(user=user)
        return profile

    def get(self, request):
        profile = self._get_profile(request.user)
        return response.Response(DriverProfileSerializer(profile).data)

    def patch(self, request):
        profile = self._get_profile(request.user)
        serializer = DriverProfileSerializer(profile, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return response.Response(DriverProfileSerializer(profile).data)


# ---------------------------------------------------------------------------
# Driver KYC document upload
# ---------------------------------------------------------------------------

class DriverKYCView(APIView):
    permission_classes = [IsDriver]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        doc_type = request.data.get("document_type", "")
        front_file = request.FILES.get("front")
        back_file = request.FILES.get("back")
        license_file = request.FILES.get("license")

        if not doc_type or not front_file:
            return response.Response(
                {"detail": "document_type et front sont obligatoires."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        allowed_ext = {".jpg", ".jpeg", ".png", ".webp"}
        allowed_ct = {"image/jpeg", "image/png", "image/webp"}
        max_mb = getattr(settings, "MAX_UPLOAD_IMAGE_MB", 10)

        for label, f in [("front", front_file), ("back", back_file), ("license", license_file)]:
            if f is None:
                continue
            try:
                validate_uploaded_file(
                    f,
                    field_label=label,
                    allowed_extensions=allowed_ext,
                    max_mb=max_mb,
                    allowed_content_types=allowed_ct,
                )
            except Exception as exc:
                return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        docs_to_create = [(f"DRIVER_{doc_type}_FRONT", scrub_image_metadata(front_file))]
        if back_file:
            docs_to_create.append((f"DRIVER_{doc_type}_BACK", scrub_image_metadata(back_file)))
        if license_file:
            docs_to_create.append(("DRIVER_LICENSE", scrub_image_metadata(license_file)))

        for dtype, f in docs_to_create:
            ComplianceDocument.objects.update_or_create(
                user=request.user,
                doc_type=dtype,
                defaults={"file": f, "status": "PENDING"},
            )

        write_audit_log(
            actor=request.user,
            action="KYC livreur soumis",
            metadata={"user_id": request.user.id, "doc_type": doc_type},
        )
        return response.Response(
            {"detail": "Documents soumis. Vérification sous 24-48h."},
            status=status.HTTP_201_CREATED,
        )


# ---------------------------------------------------------------------------
# Driver wallet stubs (wired to existing WalletViewSet via URL aliases)
# ---------------------------------------------------------------------------

class DriverWalletView(APIView):
    """Returns the driver's wallet balance."""
    permission_classes = [IsDriver]

    def get(self, request):
        from apps.wallets.models import Wallet
        try:
            wallet = Wallet.objects.get(owner=request.user)
            return response.Response({
                "balance": str(wallet.available_balance),
                "currency": "XAF",
            })
        except Wallet.DoesNotExist:
            return response.Response({"balance": "0", "currency": "XAF"})


class DriverTransactionsView(APIView):
    """Returns the driver's recent transactions."""
    permission_classes = [IsDriver]

    def get(self, request):
        from apps.wallets.models import WalletTransaction
        txs = WalletTransaction.objects.filter(
            wallet__owner=request.user
        ).order_by("-created_at")[:50]
        data = [
            {
                "id": t.id,
                "amount": str(t.amount),
                "transaction_type": t.kind,
                "description": t.reference,
                "created_at": t.created_at.isoformat(),
            }
            for t in txs
        ]
        return response.Response(data)


class DriverEarningsView(APIView):
    """Returns the driver's earnings summary."""
    permission_classes = [IsDriver]

    def get(self, request):
        from apps.wallets.models import WalletTransaction
        from django.db.models import Sum
        from django.utils import timezone
        import datetime

        now = timezone.now()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        week_start = now - datetime.timedelta(days=now.weekday())

        qs = WalletTransaction.objects.filter(
            wallet__owner=request.user,
            kind__in=["ESCROW_RELEASE", "TOPUP"],
        )

        total = qs.aggregate(s=Sum("amount"))["s"] or 0
        this_month = qs.filter(created_at__gte=month_start).aggregate(s=Sum("amount"))["s"] or 0
        this_week = qs.filter(created_at__gte=week_start).aggregate(s=Sum("amount"))["s"] or 0

        profile = getattr(request.user, "driver_profile", None)
        deliveries = profile.completed_deliveries if profile else 0

        history = list(qs.order_by("-created_at")[:30].values(
            "id", "amount", "kind", "reference", "created_at"
        ))
        for h in history:
            h["amount"] = str(h["amount"])
            h["created_at"] = h["created_at"].isoformat()
            h["mission_reference"] = h.pop("reference") or f"Livraison #{h['id']}"

        return response.Response({
            "total_earned": str(total),
            "this_month": str(this_month),
            "this_week": str(this_week),
            "total_deliveries": deliveries,
            "history": history,
        })


class DriverWithdrawView(APIView):
    """Initiates a withdrawal request for the driver."""
    permission_classes = [IsDriver]
    parser_classes = [JSONParser]

    def post(self, request):
        from django.db import transaction as db_transaction
        from apps.wallets.models import Wallet, WalletTransaction

        amount_raw = request.data.get("amount")
        provider = request.data.get("provider", "")
        phone = request.data.get("phone_number", "")

        try:
            amount = int(amount_raw)
        except (TypeError, ValueError):
            return response.Response(
                {"detail": "Montant invalide."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if amount < 500:
            return response.Response(
                {"detail": "Montant minimum de retrait : 500 FCFA."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not provider or not phone:
            return response.Response(
                {"detail": "provider et phone_number sont obligatoires."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            with db_transaction.atomic():
                wallet = Wallet.objects.select_for_update().get(owner=request.user)
                if wallet.available_balance < amount:
                    return response.Response(
                        {"detail": "Solde insuffisant."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                wallet.available_balance -= amount
                wallet.save(update_fields=["available_balance"])
                WalletTransaction.objects.create(
                    wallet=wallet,
                    amount=amount,
                    kind="WITHDRAWAL",
                    provider=provider,
                    reference=f"Retrait vers {phone}",
                    status="PENDING",
                )
        except Wallet.DoesNotExist:
            return response.Response(
                {"detail": "Portefeuille introuvable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        write_audit_log(
            actor=request.user,
            action="Retrait livreur",
            metadata={"user_id": request.user.id, "amount": str(amount), "provider": provider},
        )
        return response.Response({"detail": "Demande de retrait enregistrée."})
