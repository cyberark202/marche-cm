from datetime import timedelta

from django.utils import timezone
from django.db import IntegrityError, transaction
from django.db.models import Avg
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import UserRole
from apps.accounts.security import has_action_permission, write_audit_log
from apps.accounts.upload_security import validate_uploaded_file
from apps.notifications.realtime import broadcast_event
from apps.orders.models import OrderStatus, OrderType
from apps.orders.services import FraudRiskError, OrderFinanceService

from .models import (
    DeliveryProof,
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
    DeliveryProofSerializer,
    ShipmentDisputeSerializer,
    ShipmentSerializer,
    TransitAgentRatingSerializer,
    TransportProfileSerializer,
    TransportQuoteSerializer,
)


def _is_general_admin(user):
    return user.is_superuser or user.role == UserRole.GENERAL_ADMIN


STATUS_TRANSITIONS = {
    ShipmentStatus.PICKUP_PENDING: {ShipmentStatus.IN_TRANSIT, ShipmentStatus.CANCELLED},
    ShipmentStatus.IN_TRANSIT: {ShipmentStatus.AT_CUSTOMS, ShipmentStatus.OUT_FOR_DELIVERY, ShipmentStatus.CANCELLED},
    ShipmentStatus.AT_CUSTOMS: {ShipmentStatus.IN_TRANSIT, ShipmentStatus.OUT_FOR_DELIVERY, ShipmentStatus.CANCELLED},
    ShipmentStatus.OUT_FOR_DELIVERY: {ShipmentStatus.CANCELLED},
    ShipmentStatus.DELIVERED: set(),
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
        if shipment.status in {ShipmentStatus.DELIVERED, ShipmentStatus.CANCELLED}:
            return response.Response({"detail": "Expedition deja terminee."}, status=status.HTTP_400_BAD_REQUEST)
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
        shipment.status = ShipmentStatus.DELIVERED
        shipment.delivered_at = timezone.now()
        shipment.save(update_fields=["status", "delivered_at", "updated_at"])

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
        if request.user.id not in {shipment.buyer_id, shipment.seller_id, shipment.transit_agent_id}:
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        payload = request.data.copy()
        payload["shipment"] = shipment.id
        serializer = ShipmentDisputeSerializer(data=payload)
        serializer.is_valid(raise_exception=True)
        dispute = serializer.save(shipment=shipment, opened_by=request.user)
        OrderFinanceService.freeze_order_escrows(order=shipment.order, actor=request.user, reason="Litige expedition ouvert")
        if dispute.sla_due_at is None:
            dispute.sla_due_at = timezone.now() + timedelta(hours=48)
            dispute.save(update_fields=["sla_due_at"])
        write_audit_log(
            actor=request.user,
            action="Ouverture litige expedition",
            action_key="logistics.dispute.open",
            metadata={"shipment_id": shipment.id, "dispute_id": dispute.id},
        )
        broadcast_event("logistics", "dispute_opened", {"shipment_id": shipment.id, "dispute_id": dispute.id})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_201_CREATED)

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
            "logistics",
            "agent_rated",
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
    queryset = ShipmentDispute.objects.select_related("shipment", "opened_by").all()

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

    @decorators.action(detail=True, methods=["post"])
    def decide(self, request, pk=None):
        if not has_action_permission(request.user, "admin.disputes.decide"):
            return response.Response({"detail": "Action reservee a l'administration."}, status=status.HTTP_403_FORBIDDEN)
        dispute = self.get_object()
        new_status = str(request.data.get("status") or "").strip().upper()
        decision = str(request.data.get("admin_decision") or "").strip().upper()
        note = str(request.data.get("resolution_note") or "").strip()
        if new_status not in {"UNDER_REVIEW", "RESOLVED"}:
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
                        order=order,
                        actor=request.user,
                        reason=note or "Decision admin litige",
                    )
                elif decision == "RELEASE_SELLER":
                    escrow_types = {"LOCAL", "SUPPLIER"}
                    OrderFinanceService.admin_force_release_locked_escrows(
                        order=order,
                        actor=request.user,
                        escrow_types=escrow_types,
                    )
                elif decision == "SPLIT":
                    OrderFinanceService.admin_force_release_locked_escrows(
                        order=order,
                        actor=request.user,
                        escrow_types={"SUPPLIER"},
                    )
                    OrderFinanceService.refund_order_locked_funds(
                        order=order,
                        actor=request.user,
                        reason="Decision SPLIT litige",
                    )
            except (ValidationError, FraudRiskError) as exc:
                return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        dispute.status = new_status
        dispute.admin_decision = decision
        dispute.resolution_note = note
        dispute.decided_by = request.user
        dispute.decided_at = timezone.now()
        dispute.save(
            update_fields=["status", "admin_decision", "resolution_note", "decided_by", "decided_at", "updated_at"]
        )
        write_audit_log(
            actor=request.user,
            action="Decision litige expedition",
            action_key="admin.disputes.decide",
            metadata={
                "dispute_id": dispute.id,
                "status": dispute.status,
                "decision": dispute.admin_decision,
                "reason": note[:240],
            },
        )
        broadcast_event("logistics", "dispute_decided", {"dispute_id": dispute.id, "status": dispute.status})
        return response.Response(ShipmentDisputeSerializer(dispute).data, status=status.HTTP_200_OK)
