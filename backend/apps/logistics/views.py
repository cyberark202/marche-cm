import hashlib
from datetime import timedelta

from django.db import IntegrityError, transaction
from django.db.models import Avg
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import UserRole
from apps.accounts.security import has_action_permission, write_audit_log
from apps.accounts.upload_security import validate_uploaded_file
from apps.notifications.realtime import broadcast_event
from apps.orders.models import OrderStatus, OrderType
from apps.orders.services import FraudRiskError, OrderFinanceService

from .models import (
    DISPUTE_TYPES_AGAINST_BUYER,
    DISPUTE_TYPES_AGAINST_SELLER,
    DISPUTE_TYPES_AGAINST_TRANSIT,
    DISPUTE_TYPES_BUYER_VS_TRANSIT,
    DISPUTE_TYPES_CONTEST_WINDOW,
    DISPUTE_TYPES_CRITICAL,
    DISPUTE_TYPES_PLATFORM,
    CustodyEvent,
    CustodyEventType,
    DeliveryProof,
    DisputeEvidence,
    DisputeEvidenceType,
    DisputeStatus,
    DisputeType,
    QuoteStatus,
    Shipment,
    ShipmentDispute,
    ShipmentEvent,
    ShipmentStatus,
    TransitAgentRating,
    TransportProfile,
    TransportQuote,
)
from .serializers import (
    CustodyEventSerializer,
    DeliveryProofSerializer,
    DisputeEvidenceSerializer,
    ShipmentDisputeSerializer,
    ShipmentSerializer,
    TransitAgentRatingSerializer,
    TransportProfileSerializer,
    TransportQuoteSerializer,
)

_EVIDENCE_ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".pdf", ".mp4", ".mov"}
_EVIDENCE_ALLOWED_TYPES = {
    "image/jpeg", "image/png", "image/webp",
    "application/pdf",
    "video/mp4", "video/quicktime",
}
_EVIDENCE_MAX_MB = 50


def _is_general_admin(user):
    return user.is_superuser or user.role == UserRole.GENERAL_ADMIN


def _compute_file_sha256(file_obj) -> str:
    h = hashlib.sha256()
    file_obj.seek(0)
    for chunk in iter(lambda: file_obj.read(8192), b""):
        h.update(chunk)
    file_obj.seek(0)
    return h.hexdigest()


def _compute_chat_integrity_hash(shipment_id: int) -> str:
    # ChatRoom has no order FK — hash over stable Shipment fields instead.
    try:
        s = Shipment.objects.filter(id=shipment_id).values(
            "id", "order_id", "buyer_id", "seller_id", "created_at"
        ).first()
        raw = (
            f"{s['id']}:{s['order_id']}:{s['buyer_id']}:{s['seller_id']}:{s['created_at'].isoformat()}"
            if s else f"shipment:{shipment_id}"
        )
    except Exception:
        raw = f"shipment:{shipment_id}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


STATUS_TRANSITIONS = {
    ShipmentStatus.PICKUP_PENDING: {ShipmentStatus.IN_TRANSIT, ShipmentStatus.CANCELLED},
    ShipmentStatus.IN_TRANSIT: {ShipmentStatus.AT_CUSTOMS, ShipmentStatus.OUT_FOR_DELIVERY, ShipmentStatus.CANCELLED},
    ShipmentStatus.AT_CUSTOMS: {ShipmentStatus.IN_TRANSIT, ShipmentStatus.OUT_FOR_DELIVERY, ShipmentStatus.CANCELLED},
    ShipmentStatus.OUT_FOR_DELIVERY: {ShipmentStatus.CANCELLED},
    ShipmentStatus.DELIVERED: set(),
    ShipmentStatus.DISPUTED: set(),
    ShipmentStatus.CANCELLED: set(),
}

TRANSIT_AGENT_STATUSES = {
    ShipmentStatus.IN_TRANSIT,
    ShipmentStatus.AT_CUSTOMS,
    ShipmentStatus.OUT_FOR_DELIVERY,
}


def _allowed_shipment_ids_for_user(user):
    if user.role == UserRole.BUYER:
        return Shipment.objects.filter(buyer=user).values_list("id", flat=True)
    if user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
        return Shipment.objects.filter(seller=user).values_list("id", flat=True)
    if user.role == UserRole.TRANSIT_AGENT:
        return Shipment.objects.filter(transit_agent=user).values_list("id", flat=True)
    return Shipment.objects.none().values_list("id", flat=True)


def _can_update_status(user, shipment, new_status):
    if _is_general_admin(user):
        return True
    if new_status == ShipmentStatus.CANCELLED:
        return user.id in {shipment.buyer_id, shipment.seller_id}
    if user.id == shipment.transit_agent_id and new_status in TRANSIT_AGENT_STATUSES:
        return True
    return False


def _refresh_transport_profile_stats(transit_agent_id):
    if not transit_agent_id:
        return
    ratings = TransitAgentRating.objects.filter(transit_agent_id=transit_agent_id)
    avg_rating = ratings.aggregate(value=Avg("score"))["value"] or 0
    completed_shipments = Shipment.objects.filter(
        transit_agent_id=transit_agent_id,
        status=ShipmentStatus.DELIVERED,
    ).count()
    TransportProfile.objects.filter(user_id=transit_agent_id).update(
        rating=round(float(avg_rating), 2),
        completed_shipments=completed_shipments,
    )


def _is_dispute_participant(user, dispute):
    shipment = dispute.shipment
    return user.id in {shipment.buyer_id, shipment.seller_id, shipment.transit_agent_id}


# ---------------------------------------------------------------------------
# Dispute type–specific security side-effects
# ---------------------------------------------------------------------------

def _invalidate_user_sessions_bulk(user_ids):
    """Delete all active Django sessions for the given user IDs."""
    try:
        from django.contrib.sessions.models import Session
        valid_ids = {uid for uid in user_ids if uid}
        if not valid_ids:
            return
        to_delete = []
        for session in Session.objects.filter(expire_date__gt=timezone.now()):
            try:
                if int(session.get_decoded().get("_auth_user_id", -1)) in valid_ids:
                    to_delete.append(session.session_key)
            except Exception:
                pass
        if to_delete:
            Session.objects.filter(session_key__in=to_delete).delete()
    except Exception:
        pass


def _verify_custody_chain_integrity(shipment):
    """Return list of CustodyEvent IDs whose integrity hash no longer matches."""
    broken = []
    for event in CustodyEvent.objects.filter(shipment=shipment).select_related("actor"):
        if event.integrity_hash and event.actor_id:
            expected = CustodyEvent.compute_hash(
                shipment.id, event.event_type, event.actor_id, event.scanned_at.isoformat()
            )
            if expected != event.integrity_hash:
                broken.append(event.id)
    return broken


def _check_premature_release(shipment, dispute, actor):
    """Log an audit entry if escrow was already released before this dispute was opened."""
    try:
        order = shipment.order
        escrow_status = str(getattr(order, "escrow_status", "UNKNOWN"))
        if escrow_status not in {"LOCKED", "FROZEN", "UNKNOWN"}:
            write_audit_log(
                actor=actor,
                action="Liberation prematuree confirmee — fonds liberes avant ouverture litige",
                action_key="wallet.premature_release_confirmed",
                metadata={
                    "dispute_id": dispute.id,
                    "order_id": order.id,
                    "escrow_status": escrow_status,
                },
            )
    except Exception:
        pass


def _run_dispute_type_security_actions(dispute_type, shipment, dispute, actor):
    """Execute security-critical side-effects keyed on dispute type."""
    if dispute_type == DisputeType.DATA_BREACH:
        participant_ids = [shipment.buyer_id, shipment.seller_id, shipment.transit_agent_id]
        _invalidate_user_sessions_bulk(participant_ids)
        write_audit_log(
            actor=actor,
            action="ALERTE SECURITE — Fuite de donnees KYC detectee — sessions invalides",
            action_key="security.data_breach",
            metadata={
                "dispute_id": dispute.id,
                "shipment_id": shipment.id,
                "affected_user_ids": [uid for uid in participant_ids if uid],
            },
        )

    elif dispute_type == DisputeType.UNAUTHORIZED_ACCESS:
        _invalidate_user_sessions_bulk([actor.id])
        write_audit_log(
            actor=actor,
            action="ALERTE SECURITE — Acces non autorise signale — session utilisateur invalidee",
            action_key="security.unauthorized_access",
            metadata={"dispute_id": dispute.id, "user_id": actor.id},
        )

    elif dispute_type == DisputeType.WITHDRAWAL_ERROR:
        write_audit_log(
            actor=actor,
            action="Investigation retrait wallet ouverte",
            action_key="wallet.withdrawal_error_investigation",
            metadata={"dispute_id": dispute.id, "shipment_id": shipment.id, "user_id": actor.id},
        )

    elif dispute_type == DisputeType.HISTORY_TAMPER:
        broken = _verify_custody_chain_integrity(shipment)
        write_audit_log(
            actor=actor,
            action="Verification integrite chaine de garde" + (" — ALTERATION DETECTEE" if broken else " — OK"),
            action_key="security.history_tamper",
            metadata={
                "dispute_id": dispute.id,
                "shipment_id": shipment.id,
                "broken_event_ids": broken,
            },
        )
        broadcast_event("logistics", "history_tamper_detected", {
            "shipment_id": shipment.id, "dispute_id": dispute.id, "broken_count": len(broken)
        })

    elif dispute_type == DisputeType.FINANCIAL_REGULATION:
        write_audit_log(
            actor=actor,
            action="Signalement reglementaire financier (COBAC / BEAC) — admin notifie",
            action_key="compliance.financial_regulation",
            metadata={"dispute_id": dispute.id, "shipment_id": shipment.id, "reporter_id": actor.id},
        )

    elif dispute_type == DisputeType.TAX_COMPLIANCE:
        write_audit_log(
            actor=actor,
            action="Signalement conformite fiscale (DGI) — admin notifie",
            action_key="compliance.tax_compliance",
            metadata={"dispute_id": dispute.id, "shipment_id": shipment.id, "reporter_id": actor.id},
        )

    elif dispute_type == DisputeType.PREMATURE_RELEASE:
        _check_premature_release(shipment, dispute, actor)

    elif dispute_type == DisputeType.MULTI_ACTOR:
        write_audit_log(
            actor=actor,
            action="Analyse chaine de garde multi-acteurs initiee",
            action_key="logistics.multi_actor_analysis",
            metadata={
                "dispute_id": dispute.id,
                "shipment_id": shipment.id,
                "last_holder_id": dispute.last_custody_holder_id,
            },
        )


class TransportProfileViewSet(viewsets.ModelViewSet):
    serializer_class = TransportProfileSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = TransportProfile.objects.select_related("user").all()

    def get_queryset(self):
        if _is_general_admin(self.request.user):
            return self.queryset
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        if self.request.user.role != UserRole.TRANSIT_AGENT:
            raise PermissionDenied("Profil reserve au transitaire.")
        profile = serializer.save(user=self.request.user)
        broadcast_event("logistics", "transport_profile_created", {"id": profile.id, "user_id": profile.user_id})


class ShipmentViewSet(viewsets.ModelViewSet):
    serializer_class = ShipmentSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = Shipment.objects.select_related("order", "buyer", "seller", "transit_agent").all()

    def get_queryset(self):
        user = self.request.user
        if _is_general_admin(user):
            return self.queryset
        if user.role == UserRole.BUYER:
            return self.queryset.filter(buyer=user)
        if user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            return self.queryset.filter(seller=user)
        if user.role == UserRole.TRANSIT_AGENT:
            return self.queryset.filter(transit_agent=user)
        return self.queryset.none()

    def perform_create(self, serializer):
        if self.request.user.role not in {UserRole.BUYER, UserRole.SUPPLIER, UserRole.WHOLESALER}:
            raise PermissionDenied("Role non autorise a creer une expedition.")
        order = serializer.validated_data["order"]
        shipment = serializer.save(buyer=order.buyer, seller=order.seller)
        broadcast_event("logistics", "shipment_created", {"id": shipment.id, "order_id": shipment.order_id})

    @decorators.action(detail=True, methods=["post"])
    def post_quote(self, request, pk=None):
        shipment = self.get_object()
        if request.user.role != UserRole.TRANSIT_AGENT:
            return response.Response(
                {"detail": "Action reservee aux transitaires."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if shipment.status in {ShipmentStatus.DELIVERED, ShipmentStatus.CANCELLED}:
            return response.Response(
                {"detail": "Impossible de deviser une expedition terminee."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if shipment.transit_agent_id and shipment.transit_agent_id != request.user.id:
            return response.Response(
                {"detail": "Un autre transitaire est deja assigne."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = TransportQuoteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            with transaction.atomic():
                quote = serializer.save(transit_agent=request.user, shipment=shipment)
        except IntegrityError:
            return response.Response(
                {"detail": "Vous avez deja emis un devis pour cette expedition."},
                status=status.HTTP_409_CONFLICT,
            )
        broadcast_event("logistics", "quote_posted", {"shipment_id": shipment.id, "quote_id": quote.id})
        return response.Response(serializer.data, status=status.HTTP_201_CREATED)

    @decorators.action(detail=True, methods=["post"])
    def accept_quote(self, request, pk=None):
        shipment = self.get_object()
        quote_id = request.data.get("quote_id")
        quote = TransportQuote.objects.filter(id=quote_id, shipment=shipment).first()
        if not quote:
            return response.Response({"detail": "Devis introuvable."}, status=status.HTTP_404_NOT_FOUND)
        if shipment.status in {ShipmentStatus.DELIVERED, ShipmentStatus.CANCELLED}:
            return response.Response({"detail": "Expedition deja terminee."}, status=status.HTTP_400_BAD_REQUEST)
        if request.user.id not in {shipment.buyer_id, shipment.seller_id}:
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        if quote.status != QuoteStatus.PENDING:
            return response.Response({"detail": "Ce devis n'est plus en attente."}, status=status.HTTP_400_BAD_REQUEST)
        if shipment.transit_agent_id and shipment.transit_agent_id != quote.transit_agent_id:
            return response.Response(
                {"detail": "Impossible de reassigner un autre transitaire."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        TransportQuote.objects.filter(shipment=shipment).exclude(id=quote.id).update(status=QuoteStatus.REJECTED)
        quote.status = QuoteStatus.ACCEPTED
        quote.save(update_fields=["status"])
        shipment.transit_agent = quote.transit_agent
        shipment.shipping_fee = quote.fee
        shipment.save(update_fields=["transit_agent", "shipping_fee", "updated_at"])
        broadcast_event("logistics", "quote_accepted", {"shipment_id": shipment.id, "quote_id": quote.id})
        return response.Response({"detail": "Devis accepte et transitaire assigne."})

    @decorators.action(detail=True, methods=["post"])
    def update_status(self, request, pk=None):
        shipment = self.get_object()
        new_status = request.data.get("status")
        note = request.data.get("note", "")
        allowed_statuses = {value for value, _ in ShipmentStatus.choices}
        if new_status not in allowed_statuses:
            return response.Response({"detail": "Statut invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if shipment.status in {ShipmentStatus.DELIVERED, ShipmentStatus.CANCELLED, ShipmentStatus.DISPUTED}:
            return response.Response({"detail": "Expedition deja terminee ou en litige."}, status=status.HTTP_400_BAD_REQUEST)
        if new_status == ShipmentStatus.DELIVERED:
            return response.Response(
                {"detail": "Utilisez validate_delivery pour confirmer la livraison."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if new_status not in STATUS_TRANSITIONS.get(shipment.status, set()):
            return response.Response(
                {"detail": f"Transition invalide: {shipment.status} -> {new_status}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not _can_update_status(request.user, shipment, new_status):
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        shipment.status = new_status
        fields_to_update = ["status", "updated_at"]
        if new_status == ShipmentStatus.CANCELLED:
            shipment.order.status = OrderStatus.CANCELLED
            shipment.order.save(update_fields=["status", "updated_at"])
            OrderFinanceService.refund_order_locked_funds(
                order=shipment.order,
                actor=request.user,
                reason="Annulation expedition",
            )
        shipment.save(update_fields=fields_to_update)
        ShipmentEvent.objects.create(shipment=shipment, actor=request.user, status=new_status, note=note)
        broadcast_event("logistics", "shipment_status_changed", {"shipment_id": shipment.id, "status": new_status})
        broadcast_event("orders", "shipment_status_changed", {"order_id": shipment.order_id, "status": new_status})
        return response.Response({"detail": "Statut logistique mis a jour."})

    @decorators.action(detail=True, methods=["post"])
    def submit_proof(self, request, pk=None):
        shipment = self.get_object()
        if request.user.id != shipment.transit_agent_id:
            return response.Response({"detail": "Reserve au transitaire assigne."}, status=status.HTTP_403_FORBIDDEN)
        if shipment.status not in {ShipmentStatus.IN_TRANSIT, ShipmentStatus.AT_CUSTOMS, ShipmentStatus.OUT_FOR_DELIVERY}:
            return response.Response(
                {"detail": "Statut expedition incompatible avec la preuve de livraison."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = DeliveryProofSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        OrderFinanceService._ensure_secure_proof_storage()
        photo = serializer.validated_data.get("photo")
        if photo:
            validate_uploaded_file(
                photo,
                field_label="Preuve livraison",
                allowed_extensions={".jpg", ".jpeg", ".png", ".webp"},
                allowed_content_types={"image/jpeg", "image/png", "image/webp"},
                max_mb=10,
            )
        DeliveryProof.objects.update_or_create(
            shipment=shipment,
            defaults=serializer.validated_data,
        )
        broadcast_event("logistics", "delivery_proof_submitted", {"shipment_id": shipment.id})
        return response.Response({"detail": "Preuve de livraison enregistree."})

    @decorators.action(detail=True, methods=["post"])
    def validate_delivery(self, request, pk=None):
        shipment = self.get_object()
        if request.user.id != shipment.buyer_id:
            return response.Response({"detail": "Action reservee a l'acheteur."}, status=status.HTTP_403_FORBIDDEN)
        if shipment.status not in {ShipmentStatus.OUT_FOR_DELIVERY, ShipmentStatus.IN_TRANSIT, ShipmentStatus.AT_CUSTOMS}:
            return response.Response({"detail": "Cette expedition n'est pas livrable pour le moment."}, status=status.HTTP_400_BAD_REQUEST)
        proof = getattr(shipment, "delivery_proof", None)
        if not proof:
            return response.Response({"detail": "Aucune preuve de livraison."}, status=status.HTTP_400_BAD_REQUEST)
        proof.validated = True
        proof.save(update_fields=["validated"])
        now = timezone.now()
        shipment.status = ShipmentStatus.DELIVERED
        shipment.delivered_at = now
        shipment.contest_deadline = now + timedelta(hours=48)
        shipment.save(update_fields=["status", "delivered_at", "contest_deadline", "updated_at"])
        order = shipment.order
        if order.status not in {OrderStatus.SHIPPING, OrderStatus.DELIVERED, OrderStatus.ADMIN_APPROVED, OrderStatus.CONFIRMED}:
            return response.Response(
                {"detail": f"Transition commande invalide: {order.status} -> DELIVERED."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        order.status = OrderStatus.DELIVERED
        order.save(update_fields=["status", "updated_at"])
        try:
            if order.order_type == OrderType.INTERNATIONAL:
                OrderFinanceService.release_logistics_escrow_after_buyer_confirmation(order=order, actor=request.user)
            else:
                OrderFinanceService.release_local_escrow_after_buyer_confirmation(order=order, actor=request.user)
        except (ValidationError, FraudRiskError) as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        order.refresh_from_db(fields=["status", "escrow_status"])
        if order.status == OrderStatus.DISPUTED:
            return response.Response(
                {"detail": "Livraison validee mais payout en echec: fonds replaces en litige admin."},
                status=status.HTTP_409_CONFLICT,
            )
        _refresh_transport_profile_stats(shipment.transit_agent_id)
        broadcast_event("logistics", "delivery_validated", {"shipment_id": shipment.id, "order_id": order.id})
        broadcast_event("orders", "completed", {"id": order.id})
        broadcast_event("wallets", "escrow_released", {"order_id": order.id})
        return response.Response({"detail": "Livraison validee, funds debloques vendeur + transitaire."})

    @decorators.action(detail=True, methods=["post"])
    def open_dispute(self, request, pk=None):
        shipment = self.get_object()
        user = request.user
        if user.id not in {shipment.buyer_id, shipment.seller_id, shipment.transit_agent_id}:
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)

        dispute_type = str(request.data.get("dispute_type") or DisputeType.QUALITY_DEFECT).strip().upper()
        valid_types = {v for v, _ in DisputeType.choices}
        if dispute_type not in valid_types:
            return response.Response({"detail": "Type de litige invalide."}, status=status.HTTP_400_BAD_REQUEST)

        # Enforce 48-hour contest window for product-quality disputes
        if dispute_type in DISPUTE_TYPES_CONTEST_WINDOW:
            if shipment.contest_deadline and timezone.now() > shipment.contest_deadline:
                if not _is_general_admin(user):
                    return response.Response(
                        {"detail": "La fenetre de contestation de 48h apres livraison est depassee."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )

        payload = request.data.copy()
        payload["shipment"] = shipment.id
        serializer = ShipmentDisputeSerializer(data=payload)
        serializer.is_valid(raise_exception=True)

        now = timezone.now()
        is_critical = dispute_type in DISPUTE_TYPES_CRITICAL
        is_multi = dispute_type == DisputeType.MULTI_ACTOR

        # Resolve last custody holder from chain
        last_event = CustodyEvent.objects.filter(shipment=shipment).order_by("-scanned_at").first()
        last_holder = last_event.actor if last_event else None

        chat_hash = _compute_chat_integrity_hash(shipment.id)

        # Automatically resolve the accused party from opener role + dispute type.
        # Platform-level types never have an individual accused — platform is responsible.
        accused_party = None
        opener_role = getattr(user, "role", None)
        from apps.accounts.models import UserRole as _Role
        if dispute_type not in DISPUTE_TYPES_PLATFORM:
            if opener_role == _Role.BUYER:
                if dispute_type in DISPUTE_TYPES_AGAINST_SELLER:
                    accused_party = shipment.seller
                elif dispute_type in DISPUTE_TYPES_BUYER_VS_TRANSIT:
                    accused_party = shipment.transit_agent
            elif opener_role in (_Role.SUPPLIER, _Role.WHOLESALER):
                if dispute_type in DISPUTE_TYPES_AGAINST_TRANSIT:
                    accused_party = shipment.transit_agent
                elif dispute_type in DISPUTE_TYPES_AGAINST_BUYER:
                    accused_party = shipment.buyer
            elif opener_role == _Role.TRANSIT_AGENT:
                accused_party = shipment.seller

        with transaction.atomic():
            dispute = serializer.save(
                shipment=shipment,
                opened_by=user,
                accused_party=accused_party,
                dispute_type=dispute_type,
                status=DisputeStatus.UNDER_REVIEW if is_critical else DisputeStatus.OPEN,
                sla_due_at=now + timedelta(hours=48),
                chat_integrity_hash=chat_hash,
                is_multi_actor=is_multi,
                last_custody_holder=last_holder,
            )
            # Freeze escrow immediately
            OrderFinanceService.freeze_order_escrows(
                order=shipment.order, actor=user, reason=f"Litige {dispute_type} ouvert"
            )
            # Mark shipment as disputed
            shipment.status = ShipmentStatus.DISPUTED
            shipment.save(update_fields=["status", "updated_at"])
            ShipmentEvent.objects.create(
                shipment=shipment, actor=user, status=ShipmentStatus.DISPUTED,
                note=f"Litige {dispute_type} ouvert"
            )

        # Critical disputes: immediately suspend seller for COUNTERFEIT/FAKE_DOCUMENTS
        if dispute_type in {DisputeType.COUNTERFEIT, DisputeType.FAKE_DOCUMENTS}:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            User.objects.filter(id=shipment.seller_id).update(is_active=False)
            write_audit_log(
                actor=user,
                action="Vendeur suspendu - litige critique",
                action_key="admin.users.manage",
                metadata={"seller_id": shipment.seller_id, "dispute_type": dispute_type, "dispute_id": dispute.id},
            )

        # Type-specific security / compliance side-effects
        _run_dispute_type_security_actions(dispute_type, shipment, dispute, user)

        write_audit_log(
            actor=user,
            action="Ouverture litige expedition",
            action_key="logistics.dispute.open",
            metadata={"shipment_id": shipment.id, "dispute_id": dispute.id, "dispute_type": dispute_type},
        )
        broadcast_event("logistics", "dispute_opened", {
            "shipment_id": shipment.id, "dispute_id": dispute.id,
            "dispute_type": dispute_type, "is_critical": is_critical,
        })
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_201_CREATED)

    @decorators.action(detail=True, methods=["post"], url_path="log-custody")
    def log_custody(self, request, pk=None):
        """Log a physical custody transfer event. Required for chain-of-custody integrity."""
        shipment = self.get_object()
        if not has_action_permission(request.user, "custody.log") and not _is_general_admin(request.user):
            return response.Response({"detail": "Action reservee au transitaire."}, status=status.HTTP_403_FORBIDDEN)
        if request.user.id not in {shipment.transit_agent_id, shipment.seller_id} and not _is_general_admin(request.user):
            return response.Response({"detail": "Vous n'etes pas associe a cette expedition."}, status=status.HTTP_403_FORBIDDEN)

        event_type = str(request.data.get("event_type") or "").strip().upper()
        valid_types = {v for v, _ in CustodyEventType.choices}
        if event_type not in valid_types:
            return response.Response({"detail": "Type d'evenement invalide."}, status=status.HTTP_400_BAD_REQUEST)

        location = str(request.data.get("location") or "").strip()[:250]
        notes = str(request.data.get("notes") or "").strip()[:500]

        photo = request.FILES.get("photo")
        if photo:
            validate_uploaded_file(
                photo,
                field_label="Photo prise en charge",
                allowed_extensions={".jpg", ".jpeg", ".png", ".webp"},
                allowed_content_types={"image/jpeg", "image/png", "image/webp"},
                max_mb=10,
            )

        with transaction.atomic():
            event = CustodyEvent.objects.create(
                shipment=shipment,
                actor=request.user,
                event_type=event_type,
                photo=photo,
                location=location,
                notes=notes,
            )
            # Compute and store integrity hash post-save (now that scanned_at is set)
            event.integrity_hash = CustodyEvent.compute_hash(
                shipment.id, event_type, request.user.id, event.scanned_at.isoformat()
            )
            event.save(update_fields=["integrity_hash"])

        write_audit_log(
            actor=request.user,
            action="Evenement chaine de garde enregistre",
            action_key="custody.log",
            metadata={"shipment_id": shipment.id, "event_type": event_type, "event_id": event.id},
        )
        broadcast_event("logistics", "custody_event_logged", {
            "shipment_id": shipment.id, "event_type": event_type, "actor_id": request.user.id
        })
        return response.Response(CustodyEventSerializer(event).data, status=status.HTTP_201_CREATED)

    @decorators.action(detail=True, methods=["post"], url_path="supplier/confirm")
    def confirm_supplier(self, request, pk=None):
        shipment = self.get_object()
        try:
            OrderFinanceService.register_supplier_confirmation(order=shipment.order, actor=request.user)
        except (ValidationError, FraudRiskError) as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response({"detail": "Fournisseur confirme par le transitaire."}, status=status.HTTP_200_OK)

    @decorators.action(detail=True, methods=["post"], url_path="supplier/proof")
    def upload_supplier_proof(self, request, pk=None):
        shipment = self.get_object()
        proof = request.FILES.get("proof")
        if not proof:
            return response.Response({"detail": "Fichier preuve requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            OrderFinanceService.register_supplier_purchase_proof(order=shipment.order, actor=request.user, proof_file=proof)
        except (ValidationError, FraudRiskError) as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response({"detail": "Preuve d'achat fournisseur enregistree."}, status=status.HTTP_200_OK)

    @decorators.action(detail=True, methods=["post"], url_path="supplier/admin-validate")
    def admin_validate_supplier(self, request, pk=None):
        shipment = self.get_object()
        approve = str(request.data.get("approve", "true")).strip().lower() in {"1", "true", "yes"}
        note = str(request.data.get("note") or "").strip()
        if not note:
            return response.Response({"detail": "Motif admin requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            OrderFinanceService.admin_validate_supplier(order=shipment.order, actor=request.user, approve=approve, note=note)
        except (ValidationError, FraudRiskError) as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response({"detail": "Validation admin fournisseur enregistree."}, status=status.HTTP_200_OK)

    @decorators.action(detail=True, methods=["post"])
    def rate_transit_agent(self, request, pk=None):
        shipment = self.get_object()
        if request.user.id != shipment.buyer_id:
            return response.Response({"detail": "Reserve a l'acheteur."}, status=status.HTTP_403_FORBIDDEN)
        if not shipment.transit_agent_id:
            return response.Response({"detail": "Aucun transitaire assigne."}, status=status.HTTP_400_BAD_REQUEST)
        serializer = TransitAgentRatingSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        rating, _ = TransitAgentRating.objects.update_or_create(
            shipment=shipment,
            defaults={
                "transit_agent_id": shipment.transit_agent_id,
                "buyer": request.user,
                "score": serializer.validated_data["score"],
                "review": serializer.validated_data.get("review", ""),
            },
        )
        broadcast_event(
            "logistics", "agent_rated",
            {"shipment_id": shipment.id, "transit_agent_id": shipment.transit_agent_id, "score": rating.score},
        )
        _refresh_transport_profile_stats(shipment.transit_agent_id)
        return response.Response(TransitAgentRatingSerializer(rating).data)


class TransportQuoteViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = TransportQuoteSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = TransportQuote.objects.select_related("shipment", "transit_agent").all()

    def get_queryset(self):
        user = self.request.user
        if _is_general_admin(user):
            return self.queryset
        if user.role == UserRole.TRANSIT_AGENT:
            return self.queryset.filter(transit_agent=user)
        if user.role == UserRole.BUYER:
            return self.queryset.filter(shipment__buyer=user)
        if user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            return self.queryset.filter(shipment__seller=user)
        return self.queryset.none()


class ShipmentDisputeViewSet(viewsets.ModelViewSet):
    serializer_class = ShipmentDisputeSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = (
        ShipmentDispute.objects
        .select_related("shipment", "opened_by", "accused_party", "decided_by", "last_custody_holder",
                        "appeal_requested_by", "appeal_reviewed_by")
        .prefetch_related("evidences")
        .all()
    )

    def get_queryset(self):
        user = self.request.user
        if _is_general_admin(user):
            return self.queryset
        return self.queryset.filter(shipment__id__in=_allowed_shipment_ids_for_user(user))

    def perform_create(self, serializer):
        shipment = serializer.validated_data.get("shipment")
        user = self.request.user
        if shipment is None:
            raise PermissionDenied("Expedition invalide.")
        if _is_general_admin(user):
            serializer.save(opened_by=user)
            return
        if shipment.id not in set(_allowed_shipment_ids_for_user(user)):
            raise PermissionDenied("Vous ne pouvez pas ouvrir un litige sur cette expedition.")
        serializer.save(opened_by=user)

    def perform_update(self, serializer):
        if not has_action_permission(self.request.user, "admin.disputes.decide"):
            raise PermissionDenied("Seul l'administrateur peut modifier le statut d'un litige.")
        serializer.save()

    def perform_destroy(self, instance):
        if not has_action_permission(self.request.user, "admin.disputes.decide"):
            raise PermissionDenied("Seul l'administrateur peut supprimer un litige.")
        instance.delete()

    # ------------------------------------------------------------------
    # Admin: decide
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"])
    def decide(self, request, pk=None):
        if not has_action_permission(request.user, "admin.disputes.decide"):
            return response.Response({"detail": "Action reservee a l'administration."}, status=status.HTTP_403_FORBIDDEN)
        dispute = self.get_object()
        new_status = str(request.data.get("status") or "").strip().upper()
        decision = str(request.data.get("admin_decision") or "").strip().upper()
        note = str(request.data.get("resolution_note") or "").strip()

        valid_statuses = {"UNDER_REVIEW", "RESOLVED", "CLOSED_NO_ACTION", "INSPECTION_PENDING"}
        if new_status not in valid_statuses:
            return response.Response({"detail": "Statut de litige invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if new_status == "RESOLVED" and decision not in {"REFUND_BUYER", "RELEASE_SELLER", "SPLIT"}:
            return response.Response({"detail": "Decision admin invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if new_status == "RESOLVED" and not note:
            return response.Response({"detail": "resolution_note est obligatoire."}, status=status.HTTP_400_BAD_REQUEST)

        if new_status == "RESOLVED":
            order = dispute.shipment.order
            try:
                if decision == "REFUND_BUYER":
                    OrderFinanceService.refund_order_locked_funds(
                        order=order, actor=request.user, reason=note or "Decision admin litige"
                    )
                elif decision == "RELEASE_SELLER":
                    OrderFinanceService.admin_force_release_locked_escrows(
                        order=order, actor=request.user, escrow_types={"LOCAL", "SUPPLIER"}
                    )
                elif decision == "SPLIT":
                    OrderFinanceService.admin_force_release_locked_escrows(
                        order=order, actor=request.user, escrow_types={"SUPPLIER"}
                    )
                    OrderFinanceService.refund_order_locked_funds(
                        order=order, actor=request.user, reason="Decision SPLIT litige"
                    )
            except (ValidationError, FraudRiskError) as exc:
                return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        dispute.status = new_status
        dispute.admin_decision = decision
        dispute.resolution_note = note
        dispute.decided_by = request.user
        dispute.decided_at = timezone.now()
        dispute.save(update_fields=[
            "status", "admin_decision", "resolution_note", "decided_by", "decided_at", "updated_at"
        ])
        write_audit_log(
            actor=request.user,
            action="Decision litige expedition",
            action_key="admin.disputes.decide",
            metadata={"dispute_id": dispute.id, "status": dispute.status,
                      "decision": dispute.admin_decision, "reason": note[:240]},
        )
        broadcast_event("logistics", "dispute_decided", {"dispute_id": dispute.id, "status": dispute.status})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # All participants: add evidence
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"], url_path="add-evidence")
    def add_evidence(self, request, pk=None):
        dispute = self.get_object()
        if dispute.status == DisputeStatus.RESOLVED:
            return response.Response(
                {"detail": "Impossible d'ajouter des preuves a un litige resolu."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not _is_general_admin(request.user) and not _is_dispute_participant(request.user, dispute):
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        if not has_action_permission(request.user, "dispute.evidence.add") and not _is_general_admin(request.user):
            return response.Response({"detail": "Permission manquante."}, status=status.HTTP_403_FORBIDDEN)

        file = request.FILES.get("file")
        if not file:
            return response.Response({"detail": "Fichier requis."}, status=status.HTTP_400_BAD_REQUEST)

        validate_uploaded_file(
            file,
            field_label="Preuve litige",
            allowed_extensions=_EVIDENCE_ALLOWED_EXTENSIONS,
            allowed_content_types=_EVIDENCE_ALLOWED_TYPES,
            max_mb=_EVIDENCE_MAX_MB,
        )

        evidence_type = str(request.data.get("evidence_type") or DisputeEvidenceType.DOCUMENT).strip().upper()
        valid_evidence_types = {v for v, _ in DisputeEvidenceType.choices}
        if evidence_type not in valid_evidence_types:
            evidence_type = DisputeEvidenceType.DOCUMENT

        description = str(request.data.get("description") or "").strip()[:300]
        file_hash = _compute_file_sha256(file)

        evidence = DisputeEvidence.objects.create(
            dispute=dispute,
            uploaded_by=request.user,
            file=file,
            evidence_type=evidence_type,
            description=description,
            file_integrity_hash=file_hash,
            file_size_bytes=file.size,
        )
        write_audit_log(
            actor=request.user,
            action="Preuve ajoutee au litige",
            action_key="dispute.evidence.add",
            metadata={"dispute_id": dispute.id, "evidence_id": evidence.id, "evidence_type": evidence_type},
        )
        broadcast_event("logistics", "dispute_evidence_added", {"dispute_id": dispute.id, "evidence_id": evidence.id})
        return response.Response(DisputeEvidenceSerializer(evidence).data, status=status.HTTP_201_CREATED)

    # ------------------------------------------------------------------
    # Participants: request appeal (within 48h of resolution)
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"])
    def appeal(self, request, pk=None):
        dispute = self.get_object()
        user = request.user

        if not has_action_permission(user, "dispute.appeal") and not _is_general_admin(user):
            return response.Response({"detail": "Permission manquante."}, status=status.HTTP_403_FORBIDDEN)
        if not _is_dispute_participant(user, dispute) and not _is_general_admin(user):
            return response.Response({"detail": "Vous n'etes pas partie prenante de ce litige."}, status=status.HTTP_403_FORBIDDEN)
        if dispute.status != DisputeStatus.RESOLVED:
            return response.Response(
                {"detail": "L'appel n'est possible qu'apres une decision rendue."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if dispute.appeal_requested:
            return response.Response({"detail": "Un appel est deja en cours."}, status=status.HTTP_400_BAD_REQUEST)
        # 48-hour appeal window after resolution
        if dispute.decided_at and timezone.now() > dispute.decided_at + timedelta(hours=48):
            if not _is_general_admin(user):
                return response.Response(
                    {"detail": "La fenetre d'appel de 48h apres la decision est depassee."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        reason = str(request.data.get("reason") or "").strip()
        if len(reason) < 10:
            return response.Response(
                {"detail": "Motif d'appel trop court (min 10 caracteres)."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        dispute.appeal_requested = True
        dispute.appeal_requested_by = user
        dispute.appeal_requested_at = timezone.now()
        dispute.status = DisputeStatus.APPEAL_REQUESTED
        dispute.resolution_note = (dispute.resolution_note or "") + f"\n[APPEL #{timezone.now().date()}]: {reason}"
        dispute.save(update_fields=[
            "appeal_requested", "appeal_requested_by", "appeal_requested_at",
            "status", "resolution_note", "updated_at"
        ])
        write_audit_log(
            actor=user,
            action="Appel litige soumis",
            action_key="dispute.appeal",
            metadata={"dispute_id": dispute.id},
        )
        broadcast_event("logistics", "dispute_appeal_requested", {"dispute_id": dispute.id, "user_id": user.id})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # Admin: resolve appeal — must be a DIFFERENT admin than the decider
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"], url_path="resolve-appeal")
    def resolve_appeal(self, request, pk=None):
        if not has_action_permission(request.user, "admin.dispute.appeal.resolve"):
            return response.Response({"detail": "Permission manquante."}, status=status.HTTP_403_FORBIDDEN)
        dispute = self.get_object()
        if dispute.status != DisputeStatus.APPEAL_REQUESTED:
            return response.Response({"detail": "Aucun appel en cours sur ce litige."}, status=status.HTTP_400_BAD_REQUEST)
        # Separation of duties: the original decider cannot also resolve the appeal
        if dispute.decided_by_id and dispute.decided_by_id == request.user.id:
            return response.Response(
                {"detail": "L'admin ayant rendu la decision initiale ne peut pas traiter l'appel."},
                status=status.HTTP_403_FORBIDDEN,
            )

        decision = str(request.data.get("appeal_decision") or "").strip()
        new_admin_decision = str(request.data.get("admin_decision") or "").strip().upper()
        if len(decision) < 10:
            return response.Response({"detail": "Decision d'appel trop courte."}, status=status.HTTP_400_BAD_REQUEST)

        now = timezone.now()
        dispute.appeal_reviewed_by = request.user
        dispute.appeal_decision = decision
        dispute.appeal_resolved_at = now
        dispute.status = DisputeStatus.RESOLVED

        if new_admin_decision in {"REFUND_BUYER", "RELEASE_SELLER", "SPLIT"}:
            order = dispute.shipment.order
            try:
                if new_admin_decision == "REFUND_BUYER":
                    OrderFinanceService.refund_order_locked_funds(order=order, actor=request.user, reason=decision)
                elif new_admin_decision == "RELEASE_SELLER":
                    OrderFinanceService.admin_force_release_locked_escrows(
                        order=order, actor=request.user, escrow_types={"LOCAL", "SUPPLIER"}
                    )
                elif new_admin_decision == "SPLIT":
                    OrderFinanceService.admin_force_release_locked_escrows(
                        order=order, actor=request.user, escrow_types={"SUPPLIER"}
                    )
                    OrderFinanceService.refund_order_locked_funds(order=order, actor=request.user, reason="Appel SPLIT")
            except (ValidationError, FraudRiskError) as exc:
                return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
            dispute.admin_decision = new_admin_decision
            dispute.decided_by = request.user
            dispute.decided_at = now

        dispute.save(update_fields=[
            "appeal_reviewed_by", "appeal_decision", "appeal_resolved_at",
            "status", "admin_decision", "decided_by", "decided_at", "updated_at"
        ])
        write_audit_log(
            actor=request.user,
            action="Appel litige resolu",
            action_key="admin.dispute.appeal.resolve",
            metadata={"dispute_id": dispute.id, "decision": decision[:240]},
        )
        broadcast_event("logistics", "dispute_appeal_resolved", {"dispute_id": dispute.id})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # Admin: request physical inspection
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"], url_path="request-inspection")
    def request_inspection(self, request, pk=None):
        if not has_action_permission(request.user, "admin.dispute.inspect.request"):
            return response.Response({"detail": "Permission manquante."}, status=status.HTTP_403_FORBIDDEN)
        dispute = self.get_object()
        if dispute.inspection_required:
            return response.Response({"detail": "Inspection deja demandee."}, status=status.HTTP_400_BAD_REQUEST)

        note = str(request.data.get("note") or "").strip()
        dispute.inspection_required = True
        dispute.inspection_requested_at = timezone.now()
        dispute.status = DisputeStatus.INSPECTION_PENDING
        dispute.resolution_note = (dispute.resolution_note or "") + (f"\n[INSPECTION]: {note}" if note else "")
        dispute.save(update_fields=[
            "inspection_required", "inspection_requested_at", "status", "resolution_note", "updated_at"
        ])
        # Extend SLA by 5 days for inspection
        if dispute.sla_due_at:
            dispute.sla_due_at = dispute.sla_due_at + timedelta(days=5)
            dispute.save(update_fields=["sla_due_at"])

        write_audit_log(
            actor=request.user,
            action="Inspection physique demandee",
            action_key="admin.dispute.inspect.request",
            metadata={"dispute_id": dispute.id},
        )
        broadcast_event("logistics", "dispute_inspection_requested", {"dispute_id": dispute.id})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # Admin: upload inspection report
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"], url_path="inspection-report")
    def upload_inspection_report(self, request, pk=None):
        if not has_action_permission(request.user, "admin.dispute.inspection.upload"):
            return response.Response({"detail": "Permission manquante."}, status=status.HTTP_403_FORBIDDEN)
        dispute = self.get_object()
        if not dispute.inspection_required:
            return response.Response({"detail": "Aucune inspection demandee."}, status=status.HTTP_400_BAD_REQUEST)

        report_file = request.FILES.get("report")
        if not report_file:
            return response.Response({"detail": "Fichier rapport requis."}, status=status.HTTP_400_BAD_REQUEST)
        validate_uploaded_file(
            report_file,
            field_label="Rapport inspection",
            allowed_extensions={".pdf", ".jpg", ".jpeg", ".png"},
            allowed_content_types={"application/pdf", "image/jpeg", "image/png"},
            max_mb=20,
        )

        dispute.inspector_report = report_file
        dispute.inspector_report_uploaded_at = timezone.now()
        dispute.status = DisputeStatus.UNDER_REVIEW
        dispute.save(update_fields=["inspector_report", "inspector_report_uploaded_at", "status", "updated_at"])

        # Also save as DisputeEvidence for the unified evidence gallery
        file_hash = _compute_file_sha256(report_file)
        DisputeEvidence.objects.create(
            dispute=dispute,
            uploaded_by=request.user,
            file=dispute.inspector_report,
            evidence_type=DisputeEvidenceType.INSPECTION_REPORT,
            description="Rapport d'inspection physique",
            file_integrity_hash=file_hash,
            file_size_bytes=report_file.size,
        )
        write_audit_log(
            actor=request.user,
            action="Rapport inspection telecharse",
            action_key="admin.dispute.inspection.upload",
            metadata={"dispute_id": dispute.id},
        )
        broadcast_event("logistics", "dispute_inspection_report_uploaded", {"dispute_id": dispute.id})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # Admin: activate guarantee fund (multi-actor / custody chain broken)
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["post"], url_path="guarantee-fund")
    def activate_guarantee_fund(self, request, pk=None):
        if not has_action_permission(request.user, "admin.guarantee_fund.activate"):
            return response.Response({"detail": "Permission manquante."}, status=status.HTTP_403_FORBIDDEN)
        dispute = self.get_object()
        if dispute.guarantee_fund_activated:
            return response.Response({"detail": "Fonds de garantie deja active."}, status=status.HTTP_400_BAD_REQUEST)

        note = str(request.data.get("note") or "").strip()
        if len(note) < 5:
            return response.Response({"detail": "Motif requis (min 5 caracteres)."}, status=status.HTTP_400_BAD_REQUEST)

        order = dispute.shipment.order
        amount = order.total_amount if hasattr(order, "total_amount") else None

        try:
            OrderFinanceService.refund_order_locked_funds(
                order=order, actor=request.user,
                reason=f"Fonds de garantie plateforme: {note}"
            )
        except (ValidationError, FraudRiskError) as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        now = timezone.now()
        dispute.guarantee_fund_activated = True
        dispute.guarantee_fund_amount = amount
        dispute.guarantee_fund_activated_at = now
        dispute.status = DisputeStatus.RESOLVED
        dispute.admin_decision = "REFUND_BUYER"
        dispute.decided_by = request.user
        dispute.decided_at = now
        dispute.resolution_note = (dispute.resolution_note or "") + f"\n[FONDS GARANTIE]: {note}"
        dispute.save(update_fields=[
            "guarantee_fund_activated", "guarantee_fund_amount", "guarantee_fund_activated_at",
            "status", "admin_decision", "decided_by", "decided_at", "resolution_note", "updated_at"
        ])
        write_audit_log(
            actor=request.user,
            action="Fonds de garantie active",
            action_key="admin.guarantee_fund.activate",
            metadata={"dispute_id": dispute.id, "reason": note[:240]},
        )
        broadcast_event("logistics", "guarantee_fund_activated", {"dispute_id": dispute.id})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)

    # ------------------------------------------------------------------
    # All participants: view custody chain for the dispute's shipment
    # ------------------------------------------------------------------
    @decorators.action(detail=True, methods=["get"], url_path="custody-chain")
    def custody_chain(self, request, pk=None):
        dispute = self.get_object()
        if not _is_general_admin(request.user) and not _is_dispute_participant(request.user, dispute):
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        events = CustodyEvent.objects.filter(
            shipment=dispute.shipment
        ).select_related("actor").order_by("scanned_at")
        return response.Response(CustodyEventSerializer(events, many=True).data)
