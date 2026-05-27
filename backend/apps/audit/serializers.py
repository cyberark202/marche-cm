from rest_framework import serializers
from .models import AuditEvent


class AuditEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = AuditEvent
        fields = [
            "id", "category", "event_type", "actor_id", "actor_role",
            "entity_type", "entity_id", "payload", "ip_address",
            "correlation_id", "outcome", "created_at",
        ]
        read_only_fields = [
            "id", "category", "event_type", "actor_id", "actor_role",
            "entity_type", "entity_id", "payload", "ip_address",
            "correlation_id", "outcome", "created_at",
        ]
