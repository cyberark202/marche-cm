from rest_framework import serializers
from .models import EscrowHold, EscrowRelease, EscrowTransition


class EscrowHoldSerializer(serializers.ModelSerializer):
    remaining_amount = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    all_conditions_met = serializers.BooleanField(read_only=True)

    class Meta:
        model = EscrowHold
        fields = [
            "id", "purpose", "state", "beneficiary", "payer", "currency",
            "amount", "released_amount", "remaining_amount", "commission_amount",
            "entity_type", "entity_id", "required_conditions", "met_conditions",
            "auto_release_at", "frozen_reason", "frozen_at",
            "released_at", "refunded_at", "all_conditions_met",
            "idempotency_key", "metadata", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "state", "released_amount", "frozen_at",
                            "released_at", "refunded_at", "created_at", "updated_at"]


class EscrowReleaseSerializer(serializers.ModelSerializer):
    class Meta:
        model = EscrowRelease
        fields = ["id", "escrow_hold", "released_to", "amount", "commission",
                  "release_reason", "released_by", "idempotency_key", "created_at"]
        read_only_fields = ["id", "created_at"]


class EscrowTransitionSerializer(serializers.ModelSerializer):
    class Meta:
        model = EscrowTransition
        fields = ["id", "escrow_hold", "from_state", "to_state",
                  "triggered_by", "reason", "metadata", "created_at"]
        read_only_fields = ["id", "escrow_hold", "from_state", "to_state",
                            "triggered_by", "reason", "metadata", "created_at"]
