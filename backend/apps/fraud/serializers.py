from rest_framework import serializers
from .models import FraudAssessment, UserRiskProfile, BlacklistEntry


class FraudAssessmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = FraudAssessment
        fields = [
            "id", "user", "action_type", "risk_score", "risk_level", "decision",
            "signals", "entity_type", "entity_id", "reviewed", "reviewed_at",
            "review_outcome", "metadata", "created_at",
        ]
        read_only_fields = [
            "id", "user", "action_type", "risk_score", "risk_level", "decision",
            "signals", "entity_type", "entity_id", "reviewed", "reviewed_at",
            "review_outcome", "metadata", "created_at",
        ]


class UserRiskProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserRiskProfile
        fields = [
            "user", "overall_score", "assessment_count", "last_assessed_at",
            "is_watchlisted", "is_blocked", "blocked_reason", "blocked_at",
            "last_30d_withdrawal_total", "updated_at",
        ]
        read_only_fields = [
            "user", "overall_score", "assessment_count", "last_assessed_at",
            "is_watchlisted", "is_blocked", "blocked_reason", "blocked_at",
            "last_30d_withdrawal_total", "updated_at",
        ]


class BlacklistEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = BlacklistEntry
        fields = ["id", "entry_type", "value", "reason", "added_by", "expires_at", "created_at"]
        read_only_fields = ["id", "created_at"]
