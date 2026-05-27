from django.contrib.auth import get_user_model
from django.db.models import Q
from rest_framework import mixins, viewsets, status
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError as DRFValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.accounts.models import UserRole
from core.permissions.rbac import IsGeneralAdmin
from .models import DisputeCase, DisputeEvent
from .serializers import (
    DisputeCaseSerializer, DisputeEventSerializer,
    OpenDisputeSerializer, MakeDecisionSerializer,
)
from .services import dispute_service
from .state_machine import DisputeStateMachineError

User = get_user_model()


class DisputeCaseViewSet(
    mixins.RetrieveModelMixin,
    mixins.ListModelMixin,
    viewsets.GenericViewSet,
):
    permission_classes = [IsAuthenticated]

    def get_serializer_class(self):
        if self.action == "open":
            return OpenDisputeSerializer
        if self.action == "decide":
            return MakeDecisionSerializer
        return DisputeCaseSerializer

    def get_permissions(self):
        # Audit ref: [FIN-020] use enum + permission class instead of string role.
        if self.action == "decide":
            return [IsAuthenticated(), IsGeneralAdmin()]
        return super().get_permissions()

    def get_queryset(self):
        user = self.request.user
        if getattr(user, "role", None) == UserRole.GENERAL_ADMIN:
            return DisputeCase.objects.all().order_by("-created_at")
        return DisputeCase.objects.filter(
            Q(opened_by=user) | Q(accused_party=user) | Q(assigned_mediator=user)
        ).order_by("-created_at")

    @action(detail=False, methods=["post"], url_path="open")
    def open(self, request):
        serializer = OpenDisputeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        accused_party = None
        if d.get("accused_party_id"):
            try:
                accused_party = User.objects.get(pk=d["accused_party_id"])
            except User.DoesNotExist:
                pass
        case = dispute_service.open_dispute(
            opened_by=request.user,
            entity_type=d["entity_type"],
            entity_id=d["entity_id"],
            dispute_type=d["dispute_type"],
            category=d["category"],
            title=d["title"],
            description=d["description"],
            accused_party=accused_party,
            escrow_hold_id=d.get("escrow_hold_id"),
        )
        return Response(DisputeCaseSerializer(case).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="decide")
    def decide(self, request, pk=None):
        # Permission enforced by get_permissions() above.
        case = self.get_object()
        serializer = MakeDecisionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        try:
            # Audit ref: [FIN-005] pass Decimals straight through — no float().
            decision = dispute_service.make_decision(
                case=case,
                decided_by=request.user,
                outcome=d["outcome"],
                buyer_refund=d["buyer_refund_amount"],
                seller_release=d["seller_release_amount"],
                reasoning=d["reasoning"],
            )
            return Response({"id": str(decision.id), "outcome": decision.outcome})
        except DisputeStateMachineError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)
        except DRFValidationError:
            raise
        except Exception as exc:
            # The service raises ValidationError(...) for business-rule failures
            # (negative amounts, sum mismatch, unsupported entity_type, missing
            # order). Surface them as 422 — the financial action did NOT execute.
            return Response({"detail": str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)

    @action(detail=True, methods=["post"], url_path="escalate")
    def escalate(self, request, pk=None):
        case = self.get_object()
        reason = request.data.get("reason", "")
        try:
            updated = dispute_service.escalate(case, actor=request.user, reason=reason)
            return Response(DisputeCaseSerializer(updated).data)
        except DisputeStateMachineError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_422_UNPROCESSABLE_ENTITY)

    @action(detail=True, methods=["get"], url_path="timeline")
    def timeline(self, request, pk=None):
        case = self.get_object()
        events = DisputeEvent.objects.filter(dispute=case).order_by("created_at")
        return Response(DisputeEventSerializer(events, many=True).data)
