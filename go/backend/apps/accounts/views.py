"""
Accounts views: auth, profile, compliance, sensitive actions, admin.

Security posture:
  OWASP A01 — Broken Access Control:
    • ComplianceDocumentViewSet uses RELATIONAL authorization (not role-only).
    • Unauthorized access returns 404, not 403, to prevent user enumeration.
    • verification_status exposes only {is_verified, kyc_level} — no documents.
  OWASP A02 — Cryptographic Failures:
    • OTP codes are hashed with PBKDF2 (make_password) before storage.
  OWASP A09 — Security Logging:
    • write_audit_log strips PII via sanitize_audit_metadata (see security.py).
    • No phone numbers, emails, or tokens appear in AuditLog.metadata.
"""

import csv
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import make_password
from django.core.mail import send_mail
from django.db.models import Q
from django.http import Http404, HttpResponse
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

from apps.analytics.models import RFQStatus
from apps.logistics.models import DisputeStatus, QuoteStatus, ShipmentStatus
from apps.notifications.realtime import broadcast_event
from apps.orders.models import OrderStatus
from apps.wallets.models import PaymentProvider, TransactionStatus
from .compliance_preview import generate_compliance_preview
from .location_service import update_user_location
from .models import AuditLog, ComplianceDocument, FCMToken, SensitiveActionChallenge, User, UserRole
from .security import (
    has_action_permission,
    is_sensitive_action_2fa_required,
    verify_sensitive_action_challenge,
    write_audit_log,
)
from .serializers import (
    ComplianceDocumentSerializer,
    LoginRequestSerializer,
    ManagedUserCreateSerializer,
    ProfileUpdateSerializer,
    RegisterSerializer,
    UserSerializer,
)


# ---------------------------------------------------------------------------
# Internal role helpers
# ---------------------------------------------------------------------------

def _is_general_admin(user: User) -> bool:
    return bool(user and user.is_authenticated and (user.is_superuser or user.role == UserRole.GENERAL_ADMIN))


def _require_action(user: User, action_key: str, message: str):
    if not has_action_permission(user, action_key):
        raise PermissionDenied(message)


def _auth_disabled_response():
    return response.Response(
        {"detail": "Authentification temporairement desactivee."},
        status=status.HTTP_403_FORBIDDEN,
    )


def _choices_payload(choices):
    return [{"value": value, "label": label} for value, label in choices]


def _is_compliance_actor(user: User) -> bool:
    if not user or not user.is_authenticated:
        return False
    return user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}


def _sync_business_user_verification(user: User) -> bool:
    if user.role not in {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}:
        return bool(user.is_verified)
    has_approved_cert = user.compliance_documents.filter(status="APPROVED").exists()
    if user.is_verified != has_approved_cert:
        user.is_verified = has_approved_cert
        user.save(update_fields=["is_verified"])
    return has_approved_cert


# ---------------------------------------------------------------------------
# OWASP A01 — Relational authorization for KYC document access
# ---------------------------------------------------------------------------

def _has_business_relationship_with(actor: User, target_id: int) -> bool:
    """
    Return True iff *actor* and *target_id* share at least one order or shipment.

    This enforces RELATIONAL authorization: a compliance actor may only inspect
    counterparty KYC documents when a legitimate business relationship exists.
    Role membership alone is NOT sufficient.

    Late imports prevent circular dependencies between the accounts and orders apps.
    """
    from apps.orders.models import Order  # noqa: PLC0415

    # Supplier / Wholesaler: shared order (buyer ↔ seller)
    if Order.objects.filter(
        Q(buyer=actor, seller_id=target_id) | Q(seller=actor, buyer_id=target_id)
    ).exists():
        return True

    # Transit agent: shipment where the agent is assigned to buyer/seller
    if actor.role == UserRole.TRANSIT_AGENT:
        from apps.logistics.models import Shipment  # noqa: PLC0415

        return Shipment.objects.filter(transit_agent=actor).filter(
            Q(buyer_id=target_id) | Q(seller_id=target_id)
        ).exists()

    return False


# ---------------------------------------------------------------------------

SENSITIVE_ACTION_LABELS = {
    "wallet.withdraw": "Retrait wallet",
    "profile.update": "Mise a jour profil",
    "auth.password.change": "Changement de mot de passe",
    "auth.email.change": "Changement email",
    "auth.phone.change": "Changement telephone",
}


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------

class UiConfigView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        default_country_code = User._meta.get_field("country_code").default
        managed_roles = [UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT]
        allowed_wallet_providers = list(PaymentProvider.choices)
        if settings.NOTCHPAY_ENABLED and settings.NOTCHPAY_ONLY_MTN:
            allowed_wallet_providers = [
                choice for choice in PaymentProvider.choices if choice[0] == PaymentProvider.MOBILE_MONEY
            ]
        config = {
            "defaults": {
                "country_code": default_country_code,
                "rfq_city": "Douala",
                "rfq_country_code": default_country_code,
                "campaign_target_quantity": 500,
                "product_available_qty": 10,
                "product_unit_price": 1000,
                "product_min_qty": 1,
                "product_max_qty": 10,
                "product_min_price": 900,
                "product_max_price": 1000,
                "shipment_quote_eta_days": 2,
                "shipment_dispute_reason": "Retard",
                "transport_air_price_per_kg": 3500,
                "transport_sea_price_per_kg": 1800,
                "wallet_reconcile_reason": "Reconciliation manuelle admin",
                "transit_rating_score": 5,
                "feed_search_hint": "Rechercher un produit",
            },
            "choices": {
                "user_roles": _choices_payload(UserRole.choices),
                "managed_user_roles": [
                    {"value": value, "label": label}
                    for value, label in UserRole.choices
                    if value in managed_roles
                ],
                "compliance_doc_types": sorted(ComplianceDocumentSerializer.CERTIFICATION_TYPES),
                "order_timeline_steps": [
                    OrderStatus.CONFIRMED,
                    ShipmentStatus.IN_TRANSIT,
                    ShipmentStatus.DELIVERED,
                    OrderStatus.COMPLETED,
                ],
                "shipment_statuses": _choices_payload(ShipmentStatus.choices),
                "shipment_update_statuses": [
                    ShipmentStatus.IN_TRANSIT,
                    ShipmentStatus.AT_CUSTOMS,
                    ShipmentStatus.OUT_FOR_DELIVERY,
                ],
                "transport_modes": [
                    {"value": "AIR", "label": "Avion"},
                    {"value": "SEA", "label": "Bateau"},
                ],
                "shipment_filters": [
                    {"value": "ALL", "label": "Tout"},
                    {"value": "PENDING", "label": "A traiter"},
                    {"value": "IN_TRANSIT", "label": "En transit"},
                    {"value": "LATE", "label": "En retard"},
                    {"value": "DISPUTED", "label": "Litiges ouverts"},
                ],
                "quote_statuses": _choices_payload(QuoteStatus.choices),
                "rfq_statuses": _choices_payload(RFQStatus.choices),
                "dispute_statuses": _choices_payload(DisputeStatus.choices),
                "dispute_decisions": [
                    {"value": "REFUND_BUYER", "label": "Refund buyer"},
                    {"value": "RELEASE_SELLER", "label": "Release seller"},
                    {"value": "SPLIT", "label": "Split"},
                ],
                "wallet_payment_providers": _choices_payload(allowed_wallet_providers),
                "wallet_reconcile_statuses": [
                    TransactionStatus.SUCCESS,
                    TransactionStatus.FAILED,
                ],
                "wallet_provider_route_phone": {
                    PaymentProvider.MOBILE_MONEY: "",
                    PaymentProvider.ORANGE_MONEY: "",
                },
                "wallet_provider_transfer_code": {
                    PaymentProvider.MOBILE_MONEY: settings.WALLET_MTN_TRANSFER_CODE_TEMPLATE,
                    PaymentProvider.ORANGE_MONEY: settings.WALLET_ORANGE_TRANSFER_CODE_TEMPLATE,
                },
                "wallet_provider_logo_url": {
                    PaymentProvider.MOBILE_MONEY: "asset:assets/payment/mtn.png",
                    PaymentProvider.ORANGE_MONEY: "asset:assets/payment/orange.png",
                    PaymentProvider.VISA: "https://logo.clearbit.com/visa.com",
                    PaymentProvider.MASTERCARD: "https://logo.clearbit.com/mastercard.com",
                    PaymentProvider.PAYPAL: "https://logo.clearbit.com/paypal.com",
                },
                "feed_sort_modes": [
                    {"value": "relevance", "label": "Relevance"},
                    {"value": "priceAsc", "label": "Prix croissant"},
                    {"value": "priceDesc", "label": "Prix decroissant"},
                    {"value": "trust", "label": "Trust score"},
                ],
                "feed_image_blocked_keywords": [
                    "img", "image", "photo", "pic", "screenshot", "whatsapp",
                    "camera", "scan", "jpg", "jpeg", "png", "heic", "webp",
                ],
                "feed_comment_emojis": ["😀", "😍", "🔥", "👏", "🙏", "👍", "💯", "🎉"],
                "feed_comment_stickers": [
                    "[Sticker: Merci]",
                    "[Sticker: Valide]",
                    "[Sticker: Super prix]",
                ],
            },
        }
        return response.Response(config, status=status.HTTP_200_OK)


class UserViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = User.objects.order_by("id")

    def get_queryset(self):
        if _is_general_admin(self.request.user):
            return self.queryset
        return self.queryset.filter(id=self.request.user.id)

    @decorators.action(detail=False, methods=["get"])
    def online(self, request):
        users = self.get_queryset().filter(is_online=True)
        return response.Response(UserSerializer(users, many=True).data)

    @decorators.action(detail=False, methods=["post"])
    def create_managed_user(self, request):
        _require_action(request.user, "admin.users.manage", "Action reservee a l'admin general.")
        serializer = ManagedUserCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        write_audit_log(
            actor=request.user,
            action="Creation utilisateur gere",
            action_key="admin.users.manage",
            metadata={"user_id": user.id, "role": user.role},
        )
        broadcast_event("profiles", "managed_user_created", {"id": user.id, "role": user.role})
        return response.Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)

    @decorators.action(detail=True, methods=["get"], url_path="verification-status")
    def verification_status(self, request, pk=None):
        """
        Return minimal verification status for a counterparty — no documents, no PII.

        Access rules (deny-by-default):
          • GENERAL_ADMIN: unrestricted.
          • Compliance actors (SUPPLIER / WHOLESALER / TRANSIT_AGENT):
            only allowed when a business relationship exists with the target.
          • All others: 404 (prevents role enumeration).

        Response: {"is_verified": bool, "kyc_level": int}
        """
        actor = request.user

        # Only compliance actors and admins may use this endpoint.
        if not _is_general_admin(actor) and not _is_compliance_actor(actor):
            raise Http404

        try:
            target_id = int(pk)
        except (TypeError, ValueError):
            raise Http404

        # Compliance actors must share a business relationship with the target.
        if not _is_general_admin(actor):
            if not _has_business_relationship_with(actor, target_id):
                # Return 404 — not 403 — to prevent confirming the user exists.
                raise Http404

        try:
            target = User.objects.get(pk=target_id)
        except User.DoesNotExist:
            raise Http404

        return response.Response(
            {"is_verified": target.is_verified, "kyc_level": target.kyc_level},
            status=status.HTTP_200_OK,
        )


class ComplianceDocumentViewSet(viewsets.ModelViewSet):
    serializer_class = ComplianceDocumentSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = ComplianceDocument.objects.select_related("user", "reviewed_by").all()

    def get_queryset(self):
        """
        RELATIONAL authorization — role alone is NOT sufficient.

        Rules (deny-by-default; unauthorized → Http404 to prevent enumeration):
          1. GENERAL_ADMIN: unrestricted.
          2. Own documents (any role): always allowed.
          3. Compliance actors with a verified business relationship:
             may see only APPROVED documents of their counterparty.
          4. All other combinations: Http404.

        OWASP A01 — Broken Object Level Authorization (BOLA/IDOR) mitigation.
        """
        actor = self.request.user
        if not getattr(actor, "is_authenticated", False):
            return self.queryset.none()

        user_id_param = self.request.query_params.get("user_id")

        if self.action == "list" and user_id_param is not None:
            try:
                target_id = int(user_id_param)
            except (TypeError, ValueError):
                # Malformed user_id → 404 (prevents probing)
                raise Http404

            # Self-access is always allowed
            if target_id == actor.id:
                return self.queryset.filter(user_id=target_id).order_by("-created_at")

            # Admin: unrestricted access to all documents
            if _is_general_admin(actor):
                return self.queryset.filter(user_id=target_id).order_by("-created_at")

            # Compliance actors: MUST have a real business relationship
            if _is_compliance_actor(actor) and _has_business_relationship_with(actor, target_id):
                return (
                    self.queryset
                    .filter(user_id=target_id, status="APPROVED")
                    .order_by("-created_at")
                )

            # Deny: return 404 (not 403) — prevents user enumeration
            raise Http404

        # No user_id filter: return own documents or admin view
        if _is_general_admin(actor):
            return self.queryset
        if not _is_compliance_actor(actor):
            return self.queryset.none()
        return self.queryset.filter(user=actor)

    def perform_create(self, serializer):
        if not _is_compliance_actor(self.request.user):
            raise PermissionDenied("Seuls fournisseur, grossiste et transitaire soumettent des certifications.")
        document = serializer.save(user=self.request.user)
        if document.user.is_verified:
            document.user.is_verified = False
            document.user.save(update_fields=["is_verified"])
        generate_compliance_preview(document)
        broadcast_event(
            "compliance",
            "document_created",
            {"id": document.id, "user_id": document.user_id, "doc_type": document.doc_type},
        )

    @decorators.action(detail=True, methods=["post"])
    def review(self, request, pk=None):
        _require_action(request.user, "compliance.review", "Reserve aux admins.")
        document = self.get_object()
        new_status = request.data.get("status")
        if new_status not in {"APPROVED", "REJECTED"}:
            return response.Response({"detail": "Statut invalide."}, status=status.HTTP_400_BAD_REQUEST)
        document.status = new_status
        document.reviewed_by = request.user
        document.reviewed_at = timezone.now()
        document.save(update_fields=["status", "reviewed_by", "reviewed_at"])
        _sync_business_user_verification(document.user)
        broadcast_event(
            "compliance",
            "document_reviewed",
            {"id": document.id, "status": document.status, "user_id": document.user_id},
        )
        write_audit_log(
            actor=request.user,
            action="Revue document conformite",
            action_key="compliance.review",
            metadata={
                "document_id": document.id,
                "status": document.status,
                "user_id": document.user_id,
            },
        )
        broadcast_event("profiles", "user_verified_changed", {"user_id": document.user_id})
        return response.Response({"detail": "Document revise."})


class RegisterView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "register"

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        # Audit: use user_id only — NEVER log phone_number, email, or any PII.
        write_audit_log(
            actor=user,
            action="Inscription utilisateur",
            metadata={"user_id": user.id, "country_code": user.country_code},
        )
        return response.Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


class LoginRequestView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "login"

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        serializer = LoginRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        # Audit: user_id only — do not log the email address.
        write_audit_log(
            actor=user,
            action="Connexion email mot de passe",
            metadata={"user_id": user.id},
        )
        refresh = RefreshToken.for_user(user)
        return response.Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": UserSerializer(user).data,
            },
            status=status.HTTP_200_OK,
        )


class LoginVerifyView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "otp"

    def post(self, request):
        return response.Response(
            {"detail": "Verification OTP desactivee. Utilisez /api/auth/login/ avec email et mot de passe."},
            status=status.HTTP_410_GONE,
        )


class MeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return response.Response(UserSerializer(request.user).data)


class ProfileUpdateView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def post(self, request):
        verified, message = verify_sensitive_action_challenge(
            user=request.user,
            action_key="profile.update",
            challenge_token=str(request.data.get("challenge_token") or ""),
            verification_code=str(request.data.get("verification_code") or ""),
        )
        if not verified:
            return response.Response({"detail": message}, status=status.HTTP_403_FORBIDDEN)

        new_email = (request.data.get("email") or "").strip().lower()
        if new_email and new_email != (request.user.email or "").strip().lower():
            ok_email, msg_email = verify_sensitive_action_challenge(
                user=request.user,
                action_key="auth.email.change",
                challenge_token=str(request.data.get("email_challenge_token") or ""),
                verification_code=str(request.data.get("email_verification_code") or ""),
            )
            if not ok_email:
                return response.Response(
                    {"detail": msg_email or "Confirmation requise pour changer l'email."},
                    status=status.HTTP_403_FORBIDDEN,
                )

        new_phone = (request.data.get("phone_number") or "").strip()
        if new_phone and new_phone != (request.user.phone_number or "").strip():
            ok_phone, msg_phone = verify_sensitive_action_challenge(
                user=request.user,
                action_key="auth.phone.change",
                challenge_token=str(request.data.get("phone_challenge_token") or ""),
                verification_code=str(request.data.get("phone_verification_code") or ""),
            )
            if not ok_phone:
                return response.Response(
                    {"detail": msg_phone or "Confirmation requise pour changer le telephone."},
                    status=status.HTTP_403_FORBIDDEN,
                )

        serializer = ProfileUpdateSerializer(instance=request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        write_audit_log(
            actor=request.user,
            action="Mise a jour profil",
            action_key="profile.update",
            metadata={"user_id": user.id},
        )
        broadcast_event("profiles", "profile_updated", {"user_id": user.id})
        return response.Response(UserSerializer(user).data, status=status.HTTP_200_OK)

    def patch(self, request):
        return self.post(request)


class ResolveLocationView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user = request.user
        update_fields = []

        if "country_code" in request.data:
            country_code = (request.data.get("country_code") or "").strip().upper()[:4]
            if country_code and user.country_code != country_code:
                user.country_code = country_code
                update_fields.append("country_code")

        if "city" in request.data:
            city = (request.data.get("city") or "").strip()[:120]
            if user.city != city:
                user.city = city
                update_fields.append("city")

        if update_fields:
            user.save(update_fields=update_fields)

        localized = update_user_location(user, force=True)
        return response.Response(
            {"localized": localized, "user": UserSerializer(user).data},
            status=status.HTTP_200_OK,
        )


class LogoutView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        refresh_token = (request.data.get("refresh") or "").strip()
        if not refresh_token:
            return response.Response({"detail": "Token refresh requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            token = RefreshToken(refresh_token)
            token.blacklist()
        except Exception:
            return response.Response({"detail": "Token refresh invalide."}, status=status.HTTP_400_BAD_REQUEST)
        write_audit_log(actor=request.user, action="Logout", metadata={"user_id": request.user.id})
        return response.Response({"detail": "Session revoquee."}, status=status.HTTP_200_OK)


class WalletPinView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "wallet"

    def post(self, request):
        pin = str(request.data.get("pin") or "").strip()
        if len(pin) != 4 or not pin.isdigit():
            return response.Response({"detail": "PIN invalide: 4 chiffres requis."}, status=status.HTTP_400_BAD_REQUEST)
        request.user.set_wallet_pin(pin)
        request.user.wallet_pin_failed_attempts = 0
        request.user.wallet_pin_locked_until = None
        request.user.save(update_fields=["wallet_pin_hash", "wallet_pin_failed_attempts", "wallet_pin_locked_until"])
        write_audit_log(
            actor=request.user,
            action="Configuration PIN wallet",
            metadata={"user_id": request.user.id},
        )
        return response.Response({"detail": "PIN wallet enregistre."})


class SensitiveActionRequestView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "otp"

    def post(self, request):
        action_key = str(request.data.get("action_key") or "").strip()
        if action_key not in SENSITIVE_ACTION_LABELS:
            return response.Response({"detail": "Action sensible invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if not is_sensitive_action_2fa_required(action_key):
            return response.Response(
                {"detail": "Verification supplementaire desactivee pour cette action."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        email = (request.user.email or "").strip().lower()
        if not email:
            return response.Response(
                {"detail": "Aucun email lie au compte. Impossible d'envoyer le code de securite."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Generate a cryptographically secure 6-digit OTP.
        code = f"{secrets.randbelow(1000000):06d}"
        # PBKDF2-hash the OTP before storage — NEVER persist plaintext codes.
        code_hash = make_password(code)
        challenge_token = secrets.token_urlsafe(32)
        expires_at = timezone.now() + timedelta(minutes=max(1, settings.SENSITIVE_ACTION_CODE_TTL_MINUTES))

        # Expire any pending challenge for this user + action (prevent accumulation).
        SensitiveActionChallenge.objects.filter(
            user=request.user,
            action_key=action_key,
            used_at__isnull=True,
            expires_at__gt=timezone.now(),
        ).update(expires_at=timezone.now())

        SensitiveActionChallenge.objects.create(
            user=request.user,
            action_key=action_key,
            challenge_token=challenge_token,
            code_hash=code_hash,   # hashed — plaintext code is discarded after email send
            expires_at=expires_at,
        )

        subject = f"Code de securite - {SENSITIVE_ACTION_LABELS[action_key]}"
        message = (
            f"Bonjour {request.user.username},\n\n"
            f"Votre code de verification est: {code}\n"
            f"Ce code expire dans {max(1, settings.SENSITIVE_ACTION_CODE_TTL_MINUTES)} minute(s).\n\n"
            "Si vous n'etes pas a l'origine de cette action, ignorez ce message."
        )
        try:
            send_mail(
                subject=subject,
                message=message,
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
        except Exception:
            return response.Response(
                {"detail": "Echec d'envoi du code de securite. Reessayez plus tard."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        # Audit: log only the action key — the OTP itself must never be logged.
        write_audit_log(
            actor=request.user,
            action="Demande code action sensible",
            action_key=action_key,
            metadata={"user_id": request.user.id, "action_key": action_key},
        )
        return response.Response(
            {
                "detail": f"Code envoye par email pour: {SENSITIVE_ACTION_LABELS[action_key]}.",
                "challenge_token": challenge_token,
                "expires_in_seconds": max(60, settings.SENSITIVE_ACTION_CODE_TTL_MINUTES * 60),
            },
            status=status.HTTP_200_OK,
        )


class SessionManagementView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        current_jti = str(getattr(request.auth, "payload", {}).get("jti", "") or "")
        tokens = list(OutstandingToken.objects.filter(user=request.user).order_by("-created_at")[:50])
        blacklisted_ids = set(
            BlacklistedToken.objects.filter(token__in=tokens).values_list("token_id", flat=True)
        )
        rows = [
            {
                "jti": token.jti,
                "created_at": token.created_at.isoformat() if token.created_at else "",
                "expires_at": token.expires_at.isoformat() if token.expires_at else "",
                "is_blacklisted": token.id in blacklisted_ids,
                "is_current": bool(current_jti and token.jti == current_jti),
            }
            for token in tokens
        ]
        return response.Response({"sessions": rows}, status=status.HTTP_200_OK)

    def post(self, request):
        current_jti = str(getattr(request.auth, "payload", {}).get("jti", "") or "")
        target_jti = str(request.data.get("jti") or "").strip()
        revoke_all_except_current = bool(request.data.get("all_except_current"))
        queryset = OutstandingToken.objects.filter(user=request.user)
        if revoke_all_except_current:
            if current_jti:
                queryset = queryset.exclude(jti=current_jti)
        else:
            if not target_jti:
                return response.Response({"detail": "jti requis."}, status=status.HTTP_400_BAD_REQUEST)
            queryset = queryset.filter(jti=target_jti)
        revoked = 0
        for token in queryset:
            BlacklistedToken.objects.get_or_create(token=token)
            revoked += 1
        write_audit_log(
            actor=request.user,
            action="Revocation sessions actives",
            action_key="auth.sessions.revoke",
            metadata={"user_id": request.user.id, "revoked": revoked, "all_except_current": revoke_all_except_current},
        )
        return response.Response({"detail": "Sessions revoquees.", "revoked": revoked}, status=status.HTTP_200_OK)


class PasswordChangeView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "password_change"

    def post(self, request):
        current_password = str(request.data.get("current_password") or "")
        new_password = str(request.data.get("new_password") or "")
        if not request.user.check_password(current_password):
            return response.Response({"detail": "Mot de passe actuel invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if len(new_password) < 8:
            return response.Response(
                {"detail": "Nouveau mot de passe invalide (minimum 8 caracteres)."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if new_password == current_password:
            return response.Response(
                {"detail": "Le nouveau mot de passe doit etre different de l'ancien."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        verified, msg = verify_sensitive_action_challenge(
            user=request.user,
            action_key="auth.password.change",
            challenge_token=str(request.data.get("challenge_token") or ""),
            verification_code=str(request.data.get("verification_code") or ""),
        )
        if not verified:
            return response.Response({"detail": msg}, status=status.HTTP_403_FORBIDDEN)

        request.user.set_password(new_password)
        request.user.save(update_fields=["password"])
        for token in OutstandingToken.objects.filter(user=request.user):
            BlacklistedToken.objects.get_or_create(token=token)
        write_audit_log(
            actor=request.user,
            action="Changement mot de passe",
            action_key="auth.password.change",
            metadata={"user_id": request.user.id},
        )
        return response.Response({"detail": "Mot de passe mis a jour. Reconnectez-vous."}, status=status.HTTP_200_OK)


class AuditLogExportView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        _require_action(request.user, "audit.export", "Action reservee aux administrateurs.")
        logs = AuditLog.objects.select_related("actor").all()[:2000]
        output = HttpResponse(content_type="text/csv")
        output["Content-Disposition"] = 'attachment; filename="audit_logs.csv"'
        writer = csv.writer(output)
        writer.writerow(["created_at", "actor_id", "actor_username", "action", "action_key", "metadata"])
        for row in logs:
            writer.writerow(
                [
                    row.created_at.isoformat(),
                    row.actor_id or "",
                    row.actor.username if row.actor else "",
                    row.action,
                    row.action_key,
                    row.metadata,
                ]
            )
        return output


class AdminDashboardView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        _require_action(request.user, "admin.dashboard.view", "Action reservee aux administrateurs.")
        data = {
            "users_total": User.objects.count(),
            "users_verified": User.objects.filter(is_verified=True).count(),
            "active_login_challenges": 0,
            "open_compliance": ComplianceDocument.objects.filter(status="PENDING").count(),
        }
        return response.Response(data, status=status.HTTP_200_OK)


class VerifyEmailView(APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        return response.Response(
            {"detail": "Confirmation email desactivee. Le compte est actif des l'inscription."},
            status=status.HTTP_410_GONE,
        )


class GoogleAuthView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "google_auth"

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        raw_id_token = (request.data.get("id_token") or "").strip()
        if not raw_id_token:
            return response.Response({"detail": "id_token manquant."}, status=status.HTTP_400_BAD_REQUEST)
        if not settings.GOOGLE_CLIENT_ID:
            return response.Response(
                {"detail": "GOOGLE_CLIENT_ID non configure sur le backend."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        try:
            payload = id_token.verify_oauth2_token(
                raw_id_token,
                google_requests.Request(),
                settings.GOOGLE_CLIENT_ID or None,
            )
        except Exception:
            return response.Response({"detail": "Token Google invalide."}, status=status.HTTP_400_BAD_REQUEST)

        email = (payload.get("email") or "").strip().lower()
        if not email:
            return response.Response({"detail": "Email Google introuvable."}, status=status.HTTP_400_BAD_REQUEST)

        username = (payload.get("name") or email.split("@")[0] or "google_user").strip().replace(" ", "_")
        base_username = username[:120]
        username = base_username
        idx = 1
        while User.objects.filter(username=username).exclude(email=email).exists():
            username = f"{base_username}_{idx}"
            idx += 1

        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                "username": username,
                "country_code": "CM",
                "city": "",
                "role": UserRole.BUYER,
                "is_active": True,
                "is_verified": True,
            },
        )
        if not created:
            updates = []
            if not user.is_active:
                user.is_active = True
                updates.append("is_active")
            if not user.is_verified:
                user.is_verified = True
                updates.append("is_verified")
            if updates:
                user.save(update_fields=updates)
        update_user_location(user, force=created)
        # Audit: user_id only — no email in logs.
        write_audit_log(
            actor=user,
            action="Connexion Google",
            metadata={"user_id": user.id, "created": created},
        )

        refresh = RefreshToken.for_user(user)
        return response.Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": UserSerializer(user).data,
            }
        )


class AuthDisabledView(APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        return _auth_disabled_response()


class FCMTokenView(APIView):
    """Register or remove an FCM device token for push notifications."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        registration_id = (request.data.get("registration_id") or "").strip()
        device_type = (request.data.get("type") or "android").strip()
        if not registration_id:
            return response.Response({"detail": "registration_id requis."}, status=status.HTTP_400_BAD_REQUEST)
        if device_type not in ("android", "ios", "web"):
            device_type = "android"
        FCMToken.objects.update_or_create(
            registration_id=registration_id,
            defaults={"user": request.user, "type": device_type},
        )
        return response.Response({"ok": True})

    def delete(self, request):
        registration_id = (request.data.get("registration_id") or "").strip()
        if registration_id:
            FCMToken.objects.filter(
                user=request.user, registration_id=registration_id
            ).delete()
        return response.Response(status=status.HTTP_204_NO_CONTENT)
