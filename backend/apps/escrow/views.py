from django.db.models import Q
from rest_framework import mixins, viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.accounts.models import UserRole
from core.permissions.rbac import IsGeneralAdmin
from .models import EscrowHold, EscrowTransition
from .serializers import EscrowHoldSerializer, EscrowReleaseSerializer, EscrowTransitionSerializer
from .services import escrow_service
from .state_machine import EscrowStateMachineError


class EscrowHoldViewSet(mixins.RetrieveModelMixin, mixins.ListModelMixin, viewsets.GenericViewSet):
    serializer_class = EscrowHoldSerializer
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action == "freeze":
            return [IsAuthenticated(), IsGeneralAdmin()]
        return super().get_permissions()

    def get_queryset(self):
        # Audit ref: [FIN-020] role compared via enum, not literal string.
        user = self.request.user
        if getattr(user, "role", None) == UserRole.GENERAL_ADMIN:
            return EscrowHold.objects.all().order_by("-created_at")
        return EscrowHold.objects.filter(
            Q(beneficiary=user) | Q(payer=user)
        ).order_by("-created_at")

    @action(detail=True, methods=["post"], url_path="freeze")
    def freeze(self, request, pk=None):
        hold = self.get_object()
        reason = (request.data.get("reason") or "").strip()[:240]
        try:
            updated = escrow_service.freeze_for_dispute(hold, actor=request.user, reason=reason)
            return Response(EscrowHoldSerializer(updated).data)
        except EscrowStateMachineError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)

    @action(detail=True, methods=["get"], url_path="transitions")
    def transitions(self, request, pk=None):
        hold = self.get_object()
        qs = EscrowTransition.objects.filter(escrow_hold=hold).order_by("created_at")
        return Response(EscrowTransitionSerializer(qs, many=True).data)

    @action(detail=True, methods=["post"], url_path="mark-condition")
    def mark_condition(self, request, pk=None):
        hold = self.get_object()
        condition = request.data.get("condition", "")
        if not condition:
            return Response({"detail": "condition requis."}, status=status.HTTP_400_BAD_REQUEST)
        updated = escrow_service.mark_condition_met(hold, condition=condition, actor=request.user)
        return Response(EscrowHoldSerializer(updated).data)
