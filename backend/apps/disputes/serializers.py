from rest_framework import serializers
from .models import DisputeCase, DisputeEvent, DisputeEvidence, DisputeDecision


class DisputeEvidenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = DisputeEvidence
        fields = ["id", "dispute", "uploaded_by", "evidence_type",
                  "file_key", "file_hash", "file_size_bytes", "description", "uploaded_at"]
        read_only_fields = ["id", "uploaded_at", "uploaded_by"]


class DisputeEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = DisputeEvent
        fields = ["id", "dispute", "event_type", "actor", "from_state",
                  "to_state", "description", "payload", "created_at"]
        read_only_fields = ["id", "dispute", "event_type", "actor", "from_state",
                            "to_state", "description", "payload", "created_at"]


class DisputeDecisionSerializer(serializers.ModelSerializer):
    class Meta:
        model = DisputeDecision
        fields = ["id", "dispute", "decided_by", "outcome",
                  "buyer_refund_amount", "seller_release_amount", "reasoning", "created_at"]
        read_only_fields = ["id", "created_at"]


class DisputeCaseSerializer(serializers.ModelSerializer):
    events = DisputeEventSerializer(many=True, read_only=True)
    evidences = DisputeEvidenceSerializer(many=True, read_only=True)

    class Meta:
        model = DisputeCase
        fields = [
            "id", "reference", "category", "dispute_type", "state",
            "opened_by", "accused_party", "assigned_mediator",
            "entity_type", "entity_id", "title", "description",
            "escrow_hold_id", "escrow_frozen_amount",
            "sla_due_at", "sla_breached", "is_critical",
            "resolution_outcome", "resolution_note", "resolved_at",
            "events", "evidences", "metadata", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "reference", "state", "sla_breached",
                            "resolved_at", "created_at", "updated_at"]


class OpenDisputeSerializer(serializers.Serializer):
    entity_type = serializers.CharField(max_length=60)
    entity_id = serializers.CharField(max_length=80)
    dispute_type = serializers.CharField(max_length=40)
    category = serializers.CharField(max_length=20)
    title = serializers.CharField(max_length=200)
    description = serializers.CharField()
    accused_party_id = serializers.IntegerField(required=False, allow_null=True)
    escrow_hold_id = serializers.UUIDField(required=False, allow_null=True)


class MakeDecisionSerializer(serializers.Serializer):
    outcome = serializers.ChoiceField(choices=["REFUND_BUYER", "RELEASE_SELLER", "SPLIT", "NO_ACTION"])
    buyer_refund_amount = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    seller_release_amount = serializers.DecimalField(max_digits=14, decimal_places=2, default=0)
    reasoning = serializers.CharField()
