from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import mixins, viewsets
from rest_framework.filters import OrderingFilter
from rest_framework.permissions import IsAuthenticated

from core.permissions.rbac import IsGeneralAdmin
from .models import AuditEvent
from .serializers import AuditEventSerializer


class AuditEventViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = AuditEventSerializer
    permission_classes = [IsAuthenticated, IsGeneralAdmin]
    filter_backends = [DjangoFilterBackend, OrderingFilter]
    filterset_fields = ["category", "event_type", "actor_id", "entity_type", "entity_id", "outcome"]
    ordering_fields = ["created_at"]
    ordering = ["-created_at"]

    def get_queryset(self):
        return AuditEvent.objects.all()
