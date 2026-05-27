from rest_framework import mixins, viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.accounts.models import UserRole
from core.permissions.rbac import IsGeneralAdmin
from .models import KYCApplication, KYCStatus
from .serializers import KYCApplicationSerializer, AMLScreeningSerializer
from .services import compliance_service


def _is_admin(user) -> bool:
    """Audit ref: [FIN-020] use enum, not string comparison."""
    return getattr(user, "role", None) == UserRole.GENERAL_ADMIN


class KYCApplicationViewSet(
    mixins.CreateModelMixin,
    mixins.RetrieveModelMixin,
    mixins.ListModelMixin,
    viewsets.GenericViewSet,
):
    serializer_class = KYCApplicationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if _is_admin(user):
            return KYCApplication.objects.all().order_by("-created_at")
        return KYCApplication.objects.filter(user=user).order_by("-created_at")

    def perform_create(self, serializer):
        # Audit ref: [KYC-001] user MUST be injected server-side.
        # The serializer also lists `user` in read_only_fields, so even a
        # malicious payload with {"user": <victim_id>} is silently dropped
        # before reaching here.
        serializer.save(user=self.request.user)

    def get_permissions(self):
        if self.action in ("approve", "reject"):
            return [IsAuthenticated(), IsGeneralAdmin()]
        return super().get_permissions()

    @action(detail=True, methods=["post"], url_path="approve")
    def approve(self, request, pk=None):
        application = self.get_object()
        if application.status not in (KYCStatus.PENDING, KYCStatus.UNDER_REVIEW):
            return Response(
                {"detail": "Application not reviewable."},
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        compliance_service.approve_kyc(application, reviewer=request.user)
        return Response(KYCApplicationSerializer(application).data)

    @action(detail=True, methods=["post"], url_path="reject")
    def reject(self, request, pk=None):
        application = self.get_object()
        reason = (request.data.get("reason") or "").strip()
        if not reason:
            return Response({"detail": "reason requis."}, status=status.HTTP_400_BAD_REQUEST)
        if len(reason) > 500:
            return Response({"detail": "reason trop long (500 max)."}, status=status.HTTP_400_BAD_REQUEST)
        compliance_service.reject_kyc(application, reviewer=request.user, reason=reason)
        return Response(KYCApplicationSerializer(application).data)
