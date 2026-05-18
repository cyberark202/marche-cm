from rest_framework import permissions, viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.models import UserRole
from apps.notifications.realtime import broadcast_event
from .models import GroupCampaign, RFQOffer, RequestForQuotation
from .serializers import GroupCampaignSerializer, RFQOfferSerializer, RequestForQuotationSerializer


class GroupCampaignViewSet(viewsets.ModelViewSet):
    serializer_class = GroupCampaignSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = GroupCampaign.objects.select_related("wholesaler", "product").order_by("id")

    def get_queryset(self):
        user = self.request.user
        if user.role != UserRole.WHOLESALER:
            raise PermissionDenied("Acces reserve aux grossistes.")
        return self.queryset.filter(wholesaler=user)

    def perform_create(self, serializer):
        if self.request.user.role != UserRole.WHOLESALER:
            raise PermissionDenied("Seul un grossiste peut creer une campagne.")
        campaign = serializer.save(wholesaler=self.request.user)
        broadcast_event("analytics", "campaign_created", {"id": campaign.id, "product_id": campaign.product_id})

    def perform_update(self, serializer):
        if self.request.user.role != UserRole.WHOLESALER:
            raise PermissionDenied("Modification reservee aux grossistes.")
        if serializer.instance.wholesaler_id != self.request.user.id:
            raise PermissionDenied("Vous ne pouvez modifier que vos campagnes.")
        serializer.save()

    def perform_destroy(self, instance):
        if self.request.user.role != UserRole.WHOLESALER:
            raise PermissionDenied("Suppression reservee aux grossistes.")
        if instance.wholesaler_id != self.request.user.id:
            raise PermissionDenied("Vous ne pouvez supprimer que vos campagnes.")
        instance.delete()


class RequestForQuotationViewSet(viewsets.ModelViewSet):
    serializer_class = RequestForQuotationSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = RequestForQuotation.objects.select_related("buyer").all()

    def get_queryset(self):
        user = self.request.user
        if user.role == UserRole.GENERAL_ADMIN or user.is_superuser:
            return self.queryset
        if user.role == UserRole.BUYER:
            return self.queryset.filter(buyer=user)
        return self.queryset

    def perform_create(self, serializer):
        if self.request.user.role != UserRole.BUYER:
            raise PermissionDenied("Seul un acheteur peut creer un RFQ.")
        rfq = serializer.save(buyer=self.request.user)
        broadcast_event("analytics", "rfq_created", {"id": rfq.id, "product_name": rfq.product_name})


class RFQOfferViewSet(viewsets.ModelViewSet):
    serializer_class = RFQOfferSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = RFQOffer.objects.select_related("rfq", "seller").all()

    def get_queryset(self):
        user = self.request.user
        if user.role == UserRole.GENERAL_ADMIN or user.is_superuser:
            return self.queryset
        if user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            return self.queryset.filter(seller=user)
        if user.role == UserRole.BUYER:
            return self.queryset.filter(rfq__buyer=user)
        return self.queryset.none()

    def perform_create(self, serializer):
        if self.request.user.role not in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            raise PermissionDenied("Seuls fournisseur/grossiste peuvent soumettre une offre RFQ.")
        offer = serializer.save(seller=self.request.user)
        broadcast_event("analytics", "rfq_offer_created", {"id": offer.id, "rfq_id": offer.rfq_id})
