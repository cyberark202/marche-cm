from django.db import transaction
from django.utils import timezone
from rest_framework import mixins, viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.accounts.models import UserRole
from apps.audit.services import audit_service
from core.permissions.rbac import IsGeneralAdmin
from .models import FraudAssessment, UserRiskProfile, BlacklistEntry
from .serializers import FraudAssessmentSerializer, UserRiskProfileSerializer, BlacklistEntrySerializer


# Audit ref: [FIN-012] only these review outcomes are accepted — previously
# the endpoint accepted any string, including outcomes that would later
# blow up downstream serialization or analytics.
_REVIEW_OUTCOMES = {"DISMISSED", "CONFIRMED", "ESCALATED", "FALSE_POSITIVE"}


class FraudAssessmentViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = FraudAssessmentSerializer
    permission_classes = [IsAuthenticated]

    def get_permissions(self):
        if self.action == "review":
            return [IsAuthenticated(), IsGeneralAdmin()]
        return super().get_permissions()

    def get_queryset(self):
        # Audit ref: [FIN-020] role compared via enum, not literal string.
        user = self.request.user
        if getattr(user, "role", None) == UserRole.GENERAL_ADMIN:
            return FraudAssessment.objects.all().order_by("-created_at")
        return FraudAssessment.objects.filter(user=user).order_by("-created_at")

    @action(detail=True, methods=["post"], url_path="review")
    def review(self, request, pk=None):
        # Permission enforced by get_permissions() above.
        outcome = (request.data.get("outcome") or "DISMISSED").upper()
        if outcome not in _REVIEW_OUTCOMES:
            return Response(
                {"detail": f"outcome doit etre dans {sorted(_REVIEW_OUTCOMES)}."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            assessment = FraudAssessment.objects.select_for_update().get(pk=self.get_object().pk)
            previous_outcome = assessment.review_outcome
            assessment.reviewed = True
            assessment.reviewed_at = timezone.now()
            assessment.reviewed_by = request.user
            assessment.review_outcome = outcome
            assessment.save(
                update_fields=["reviewed", "reviewed_at", "reviewed_by_id", "review_outcome"]
            )
            # Audit ref: [FIN-012] admin overrides on fraud decisions must be
            # captured in the immutable audit trail. Without this, a
            # compromised admin account could whitelist fraudulent activity
            # invisibly. Now every override is signed into the chain hash.
            audit_service.log_fraud(
                event_type="fraud.assessment.review",
                user_id=str(getattr(assessment.user, "pk", "")),
                payload={
                    "assessment_id": str(assessment.pk),
                    "outcome": outcome,
                    "previous_outcome": previous_outcome or "",
                    "decision": getattr(assessment, "decision", ""),
                    "score": str(getattr(assessment, "score", "")),
                },
                actor=request.user,
            )
        return Response(FraudAssessmentSerializer(assessment).data)


class UserRiskProfileViewSet(mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = UserRiskProfileSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        if getattr(self.request.user, "role", None) == UserRole.GENERAL_ADMIN:
            return UserRiskProfile.objects.all()
        return UserRiskProfile.objects.filter(user=self.request.user)

    def get_object(self):
        if self.kwargs.get("pk") == "me":
            profile, _ = UserRiskProfile.objects.get_or_create(user=self.request.user)
            return profile
        return super().get_object()
