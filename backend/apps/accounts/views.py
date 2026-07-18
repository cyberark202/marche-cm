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
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.db.models import Q
from django.http import Http404, HttpResponse
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError as DRFValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.views import TokenRefreshView
from rest_framework_simplejwt.exceptions import InvalidToken
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

logger = logging.getLogger(__name__)
security_logger = logging.getLogger("security")

from apps.analytics.models import RFQStatus
from apps.logistics.models import DisputeStatus, QuoteStatus, ShipmentStatus
from apps.notifications.realtime import broadcast_event
from apps.orders.models import OrderStatus
from apps.wallets.models import PaymentProvider, TransactionStatus
from .compliance_preview import generate_compliance_preview
from .kyc_constants import BUYER_IDENTITY_DOC_TYPES
from .location_service import update_user_location
from config.throttles import GlobalAnonThrottle, PasswordResetThrottle
from .models import (
    AuditLog,
    ComplianceDocument,
    FCMToken,
    PasswordResetChallenge,
    SensitiveActionChallenge,
    User,
    UserRole,
)
from .security import (
    has_action_permission,
    is_sensitive_action_2fa_required,
    verify_sensitive_action_challenge,
    write_audit_log,
)
from .serializers import (
    ComplianceDocumentSerializer,
    DriverRegisterSerializer,
    LoginRequestSerializer,
    ManagedUserCreateSerializer,
    ProfileUpdateSerializer,
    RegisterSerializer,
    SellerRegisterSerializer,
    UserSerializer,
    validate_password_strength,
)


def _password_strength_error(new_password):
    """Return a 400 Response if *new_password* fails AUTH_PASSWORD_VALIDATORS,
    else None. Audit ref: [BUG-01] — bridge the validators to the change/reset
    flows, which previously enforced only the 8-char minimum."""
    try:
        validate_password_strength(new_password)
    except DRFValidationError as exc:
        detail = exc.detail
        msg = detail[0] if isinstance(detail, (list, tuple)) and detail else str(detail)
        return response.Response({"detail": str(msg)}, status=status.HTTP_400_BAD_REQUEST)
    return None


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
        # Non-admins are hard-scoped to their own record (anti-IDOR).
        if not _is_general_admin(self.request.user):
            return self.queryset.filter(id=self.request.user.id)

        qs = self.queryset

        # A-01 fix — server-side search so the admin directory is not capped at
        # the first paginated page (PAGE_SIZE=20). Without this, any user past
        # the first page was invisible and unsearchable. Admin only.
        q = (self.request.query_params.get("q") or "").strip()
        if q:
            qs = qs.filter(
                Q(username__icontains=q)
                | Q(email__icontains=q)
                | Q(first_name__icontains=q)
                | Q(reference_code__icontains=q)
            )

        # Optional role filter (?role=BUYER|SUPPLIER|...) — server-side so the
        # bucket chips work across the whole table, not just the loaded page.
        role = (self.request.query_params.get("role") or "").strip().upper()
        if role in dict(UserRole.choices):
            qs = qs.filter(role=role)

        return qs

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

    # Audit ref: [M-6] Admin user suspension / reactivation.
    def _get_admin_target(self, request, pk):
        """Resolve the target user for an admin action, enforcing the suspend
        permission. Returns (user, error_response). The target is looked up on
        the FULL user table (not get_queryset, which is self-scoped)."""
        _require_action(request.user, "admin.users.suspend", "Action reservee a l'administration.")
        target = User.objects.filter(pk=pk).first()
        if target is None:
            return None, response.Response({"detail": "Utilisateur introuvable."}, status=status.HTTP_404_NOT_FOUND)
        return target, None

    @decorators.action(detail=True, methods=["post"])
    def suspend(self, request, pk=None):
        target, err = self._get_admin_target(request, pk)
        if err is not None:
            return err
        if target.id == request.user.id:
            return response.Response(
                {"detail": "Un administrateur ne peut pas se suspendre lui-meme."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if target.is_superuser or target.role == UserRole.GENERAL_ADMIN:
            return response.Response(
                {"detail": "Impossible de suspendre un compte administrateur."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        reason = str(request.data.get("reason") or "").strip()
        target.suspend(by=request.user, reason=reason)
        write_audit_log(
            actor=request.user,
            action="Suspension utilisateur",
            action_key="admin.users.suspend",
            metadata={"user_id": target.id, "reason": reason[:240]},
        )
        broadcast_event("profiles", "user_suspended", {"id": target.id})
        return response.Response(UserSerializer(target).data, status=status.HTTP_200_OK)

    @decorators.action(detail=True, methods=["post"])
    def unsuspend(self, request, pk=None):
        target, err = self._get_admin_target(request, pk)
        if err is not None:
            return err
        target.lift_suspension(by=request.user)
        write_audit_log(
            actor=request.user,
            action="Reactivation utilisateur",
            action_key="admin.users.suspend",
            metadata={"user_id": target.id},
        )
        broadcast_event("profiles", "user_unsuspended", {"id": target.id})
        return response.Response(UserSerializer(target).data, status=status.HTTP_200_OK)

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
            raise PermissionDenied("Seuls fournisseur, grossiste et livreur soumettent des certifications.")
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

    @decorators.action(detail=False, methods=["get"], url_path="public-certifications")
    def public_certifications(self, request):
        """
        Public trust signal — a seller's APPROVED *business* certifications
        (RCCM, tax clearance, licences, insurance...), shown on the buyer-facing
        product / video pages.

        Deliberately NOT subject to the relational-authorization get_queryset:
        it returns ONLY CERTIFICATION_DOC_TYPES — never identity documents / PII
        (CNI, passport, selfie, proof of address, driver licence) — and only
        APPROVED ones. Any authenticated user may therefore read them, while
        identity KYC stays strictly private (OWASP A01 preserved).
        """
        try:
            target_id = int(request.query_params.get("user_id"))
        except (TypeError, ValueError):
            return response.Response([], status=status.HTTP_200_OK)
        docs = (
            ComplianceDocument.objects.filter(
                user_id=target_id,
                status="APPROVED",
                doc_type__in=ComplianceDocumentSerializer.CERTIFICATION_TYPES,
            )
            .select_related("user", "reviewed_by")
            .order_by("-created_at")
        )
        return response.Response(
            ComplianceDocumentSerializer(
                docs, many=True, context={"request": request}
            ).data
        )


class BuyerKycSubmitView(APIView):
    """
    Dedicated identity-KYC submission for any authenticated user — notably
    BUYERS, who cannot use the compliance-actor-only ComplianceDocumentViewSet
    (`perform_create` rejects non-compliance roles).

    Accepts (multipart): doc_type ∈ {CNI, CNI_VERSO, PASSPORT, PROOF_ADDRESS,
    SELFIE}, file, and the optional handwritten `signature` + `consent_accepted`
    (catalogue screen 46 / KYC design — CNI + justificatif domicile + selfie).
    A re-submission replaces the existing document of the same type and resets
    it to PENDING.
    """

    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    # Audit ref: [M-2][M-3] single source of truth — apps/accounts/kyc_constants.py.
    # The serializer's ALLOWED_DOC_TYPES is derived from the same module, so the
    # view can never again advertise a type the serializer rejects.
    IDENTITY_DOC_TYPES = BUYER_IDENTITY_DOC_TYPES

    def post(self, request):
        doc_type = str(request.data.get("doc_type") or "").strip().upper()
        if doc_type not in self.IDENTITY_DOC_TYPES:
            return response.Response(
                {
                    "detail": (
                        "Type de document KYC invalide "
                        "(CNI, CNI_VERSO, PASSPORT, PROOF_ADDRESS ou SELFIE)."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing = ComplianceDocument.objects.filter(
            user=request.user, doc_type=doc_type
        ).first()
        serializer = ComplianceDocumentSerializer(
            instance=existing, data=request.data, context={"request": request}
        )
        serializer.is_valid(raise_exception=True)
        document = serializer.save(user=request.user)

        # Any (re)submission re-enters the review queue.
        document.status = "PENDING"
        document.reviewed_by = None
        document.reviewed_at = None
        document.save(update_fields=["status", "reviewed_by", "reviewed_at"])

        if document.user.is_verified:
            document.user.is_verified = False
            document.user.save(update_fields=["is_verified"])

        generate_compliance_preview(document)
        broadcast_event(
            "compliance",
            "document_created",
            {"id": document.id, "user_id": document.user_id, "doc_type": document.doc_type},
        )
        write_audit_log(
            actor=request.user,
            action="Soumission KYC acheteur",
            action_key="kyc.buyer.submit",
            metadata={
                "user_id": document.user_id,
                "reference_code": document.user.reference_code,
                "doc_type": document.doc_type,
            },
        )
        return response.Response(
            ComplianceDocumentSerializer(document, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


def _issue_session_tokens(user):
    """Build the standard authenticated-session payload {access, refresh, user}.

    Used by registration endpoints so a freshly created account is logged in
    immediately (no separate login round-trip). Mirrors the shape returned by
    LoginRequestView / GoogleAuthView for a single client-side code path.
    """
    refresh = RefreshToken.for_user(user)
    return {
        "access": str(refresh.access_token),
        "refresh": str(refresh),
        "user": UserSerializer(user).data,
    }


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
        return response.Response(_issue_session_tokens(user), status=status.HTTP_201_CREATED)


class SellerRegisterView(APIView):
    """Self-registration for the professional app — SUPPLIER / WHOLESALER only.

    The role is constrained inside SellerRegisterSerializer; this endpoint can
    never create a BUYER, TRANSIT_AGENT or GENERAL_ADMIN, which keeps account
    creation strictly partitioned per app.
    """

    permission_classes = [permissions.AllowAny]
    throttle_scope = "register"

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        serializer = SellerRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        write_audit_log(
            actor=user,
            action="Inscription vendeur",
            metadata={"user_id": user.id, "role": user.role, "country_code": user.country_code},
        )
        return response.Response(_issue_session_tokens(user), status=status.HTTP_201_CREATED)


class DriverRegisterView(APIView):
    """Self-registration for the driver app — role forced to TRANSIT_AGENT."""

    permission_classes = [permissions.AllowAny]
    throttle_scope = "register"

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        serializer = DriverRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        write_audit_log(
            actor=user,
            action="Inscription chauffeur",
            metadata={"user_id": user.id, "role": user.role, "country_code": user.country_code},
        )
        return response.Response(_issue_session_tokens(user), status=status.HTTP_201_CREATED)


class LoginRequestView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "login"

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        serializer = LoginRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        # Audit ref: [M-6] suspended / deactivated accounts cannot obtain tokens.
        if getattr(user, "is_suspended", False) or not user.is_active:
            return response.Response(
                {"detail": "Compte suspendu. Contactez le support."},
                status=status.HTTP_403_FORBIDDEN,
            )
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


class CustomTokenRefreshView(TokenRefreshView):
    """
    Token refresh with rotation: invalidate old refresh token, issue new one.

    Security benefit: Reduces window of opportunity for stolen refresh tokens.
    Each refresh generates a fresh token, so an attacker's captured token
    becomes useless after the legitimate user refreshes.
    """

    def post(self, request, *args, **kwargs):
        try:
            refresh = request.data.get('refresh')
            if not refresh:
                return response.Response(
                    {"detail": "Refresh token required."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            # Validate & decode the old refresh token
            old_refresh_token = RefreshToken(refresh)
            user = old_refresh_token.get('user_id')

            # Blacklist the old refresh token immediately
            from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
            try:
                outstanding = OutstandingToken.objects.get(token=old_refresh_token)
                BlacklistedToken.objects.get_or_create(token=outstanding)
            except OutstandingToken.DoesNotExist:
                pass  # Token not tracked, proceed

            # Issue new access + refresh tokens
            new_refresh = RefreshToken.for_user(request.user)

            write_audit_log(
                actor=request.user,
                action="Token refresh (rotated)",
                action_key="auth.token.refresh",
                metadata={"user_id": request.user.id},
            )

            return response.Response(
                {
                    "access": str(new_refresh.access_token),
                    "refresh": str(new_refresh),
                },
                status=status.HTTP_200_OK,
            )
        except InvalidToken:
            return response.Response(
                {"detail": "Invalid or expired refresh token."},
                status=status.HTTP_401_UNAUTHORIZED,
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
            logger.debug("logout_invalid_refresh_token user=%d", request.user.id, exc_info=True)
            return response.Response({"detail": "Token refresh invalide."}, status=status.HTTP_400_BAD_REQUEST)
        write_audit_log(actor=request.user, action="Logout", metadata={"user_id": request.user.id})
        return response.Response({"detail": "Session revoquee."}, status=status.HTTP_200_OK)


class WalletPinView(APIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_scope = "wallet"

    def post(self, request):
        # Wallet PIN removed (product decision). The endpoint is kept so older
        # app builds don't crash, but it no longer sets anything. Money-out
        # operations are protected by the emailed OTP (wallet.withdraw).
        return response.Response(
            {"detail": "Le PIN wallet a ete supprime. Aucune configuration n'est requise."},
            status=status.HTTP_410_GONE,
        )


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
            logger.exception("sensitive_action_otp_email_failed user=%d action=%s", request.user.id, action_key)
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
        strength_error = _password_strength_error(new_password)
        if strength_error is not None:
            return strength_error
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


class PasswordResetRequestView(APIView):
    """Forgot-password step 1 — email a single-use 6-digit reset code.

    Anti-enumeration: always returns the SAME 200 response whether or not the
    email maps to an account (and even if the email send fails). The code is
    PBKDF2-hashed before storage — plaintext is never persisted.
    """

    permission_classes = [permissions.AllowAny]
    throttle_classes = [GlobalAnonThrottle, PasswordResetThrottle]

    _GENERIC = (
        "Si un compte existe pour cet email, un code de reinitialisation vient "
        "d'etre envoye."
    )

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        email = (request.data.get("email") or "").strip().lower()
        generic = response.Response({"detail": self._GENERIC}, status=status.HTTP_200_OK)
        if not email:
            return generic
        user = User.objects.filter(email__iexact=email, is_active=True).first()
        if not user or getattr(user, "is_suspended", False):
            return generic

        now = timezone.now()
        # Invalidate any pending code for this user (one live code at a time).
        PasswordResetChallenge.objects.filter(
            user=user, used_at__isnull=True, expires_at__gt=now
        ).update(expires_at=now)

        code = f"{secrets.randbelow(1000000):06d}"
        ttl = max(1, settings.PASSWORD_RESET_CODE_TTL_MINUTES)
        PasswordResetChallenge.objects.create(
            user=user,
            code_hash=make_password(code),  # hashed — plaintext discarded after send
            expires_at=now + timedelta(minutes=ttl),
        )
        try:
            send_mail(
                subject="Reinitialisation de votre mot de passe",
                message=(
                    f"Bonjour {user.username},\n\n"
                    f"Votre code de reinitialisation est: {code}\n"
                    f"Ce code expire dans {ttl} minute(s).\n\n"
                    "Si vous n'etes pas a l'origine de cette demande, ignorez ce message."
                ),
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
        except Exception:
            # Never leak send failures — keep the response indistinguishable.
            return generic

        # Audit: user_id only — NEVER log the code or the email address.
        write_audit_log(
            actor=user,
            action="Demande reinitialisation mot de passe",
            action_key="auth.password.reset.request",
            metadata={"user_id": user.id},
        )
        return generic


class PasswordResetConfirmView(APIView):
    """Forgot-password step 2 — verify the code and set a new password.

    On success every refresh token of the account is blacklisted, so all
    existing sessions are revoked (a reset implies the old password is no
    longer trusted). The 6-digit code is attempt-capped per challenge.
    """

    permission_classes = [permissions.AllowAny]
    # No tight per-IP throttle here: the per-challenge attempt cap already bounds
    # brute-force (a burned code forces a fresh, throttled request), so a user
    # mistyping the code is not locked out by the request limiter. The global
    # anon throttle still applies as a backstop.
    throttle_classes = [GlobalAnonThrottle]

    _INVALID = "Code invalide ou expire. Recommencez la procedure."

    def post(self, request):
        if settings.AUTH_LOCKDOWN:
            return _auth_disabled_response()
        email = (request.data.get("email") or "").strip().lower()
        code = str(request.data.get("code") or "").strip()
        new_password = str(request.data.get("new_password") or "")

        if len(new_password) < 8:
            return response.Response(
                {"detail": "Nouveau mot de passe invalide (minimum 8 caracteres)."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        strength_error = _password_strength_error(new_password)
        if strength_error is not None:
            return strength_error

        user = User.objects.filter(email__iexact=email, is_active=True).first()
        if not user:
            return response.Response({"detail": self._INVALID}, status=status.HTTP_400_BAD_REQUEST)

        now = timezone.now()
        challenge = (
            PasswordResetChallenge.objects
            .filter(user=user, used_at__isnull=True, expires_at__gt=now)
            .order_by("-created_at")
            .first()
        )
        if challenge is None:
            return response.Response({"detail": self._INVALID}, status=status.HTTP_400_BAD_REQUEST)

        max_attempts = max(1, settings.PASSWORD_RESET_MAX_ATTEMPTS)
        if challenge.attempts >= max_attempts:
            challenge.expires_at = now  # burn an over-tried code
            challenge.save(update_fields=["expires_at"])
            return response.Response({"detail": self._INVALID}, status=status.HTTP_400_BAD_REQUEST)

        if not check_password(code, challenge.code_hash):
            challenge.attempts += 1
            challenge.save(update_fields=["attempts"])
            remaining = max(0, max_attempts - challenge.attempts)
            return response.Response(
                {"detail": f"Code invalide. Tentatives restantes: {remaining}."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Success — consume the challenge and rotate the password.
        challenge.used_at = now
        challenge.save(update_fields=["used_at"])
        user.set_password(new_password)
        user.save(update_fields=["password"])
        # Revoke every existing session — the old password is no longer trusted.
        for token in OutstandingToken.objects.filter(user=user):
            BlacklistedToken.objects.get_or_create(token=token)
        write_audit_log(
            actor=user,
            action="Reinitialisation mot de passe",
            action_key="auth.password.reset.confirm",
            metadata={"user_id": user.id},
        )
        return response.Response(
            {"detail": "Mot de passe reinitialise. Connectez-vous avec votre nouveau mot de passe."},
            status=status.HTTP_200_OK,
        )


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
            security_logger.warning("google_id_token_rejected", exc_info=True)
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
        # Audit ref: [M-6] a suspended account must not be silently reactivated
        # by signing in with Google.
        if not created and getattr(user, "is_suspended", False):
            return response.Response(
                {"detail": "Compte suspendu. Contactez le support."},
                status=status.HTTP_403_FORBIDDEN,
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
            return response.Response(
                {"detail": "registration_id requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if device_type not in ("android", "ios", "web"):
            device_type = "android"

        # Audit ref: [NOTIF-002] previously `update_or_create(registration_id=)`
        # silently REASSIGNED a token to whoever called the endpoint — letting
        # an attacker with a victim's FCM registration id hijack their push
        # notifications (incl. 2FA codes, password resets). We now reject any
        # attempt to claim a token already bound to a different user. The
        # legitimate device holder can DELETE first then re-register.
        existing = FCMToken.objects.filter(registration_id=registration_id).first()
        if existing and existing.user_id != request.user.id:
            security_logger.warning(
                "fcm.token_reassign_blocked",
                extra={
                    "actor_user_id": request.user.id,
                    "owner_user_id": existing.user_id,
                },
            )
            return response.Response(
                {"detail": "Ce token est deja associe a un autre compte."},
                status=status.HTTP_409_CONFLICT,
            )

        FCMToken.objects.update_or_create(
            registration_id=registration_id,
            user=request.user,
            defaults={"type": device_type},
        )
        return response.Response({"ok": True})

    def delete(self, request):
        registration_id = (request.data.get("registration_id") or "").strip()
        if registration_id:
            FCMToken.objects.filter(
                user=request.user, registration_id=registration_id
            ).delete()
        return response.Response(status=status.HTTP_204_NO_CONTENT)
