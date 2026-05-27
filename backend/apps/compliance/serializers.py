from rest_framework import serializers
from .models import KYCApplication, KYCDocument, AMLScreening


class KYCDocumentSerializer(serializers.ModelSerializer):
    """
    Audit ref: [KYC-001/002] anti-mass-assignment + anti-IDOR.

    The viewset MUST inject `application` server-side (filtered to the
    requesting user) AFTER validating ownership. Client-supplied `application`
    would let an attacker attach forged documents to another user's KYC.
    `storage_key`, `file_hash`, `file_size_bytes`, `mime_type` are computed
    server-side during the signed-upload finalization step — never trusted
    from the client.
    """

    class Meta:
        model = KYCDocument
        fields = ["id", "application", "document_type", "storage_key", "file_hash",
                  "file_size_bytes", "mime_type", "is_verified", "uploaded_at"]
        read_only_fields = [
            "id", "application", "storage_key", "file_hash",
            "file_size_bytes", "mime_type", "is_verified", "uploaded_at",
        ]


class KYCApplicationSerializer(serializers.ModelSerializer):
    """
    Audit ref: [KYC-001] mass-assignment user.

    `user` is REJECTED from the request payload. The viewset MUST inject
    `user=request.user` in `perform_create`. `metadata` is also locked
    because it can carry approval signals consumed downstream by AML/fraud.
    """

    documents = KYCDocumentSerializer(many=True, read_only=True)

    class Meta:
        model = KYCApplication
        fields = [
            "id", "user", "target_level", "status", "submitted_at",
            "reviewed_at", "reviewed_by", "rejection_reason",
            "risk_score", "documents", "metadata", "created_at", "updated_at",
        ]
        read_only_fields = [
            "id", "user", "status", "submitted_at", "reviewed_at",
            "reviewed_by", "rejection_reason", "risk_score",
            "documents", "metadata", "created_at", "updated_at",
        ]

    def validate_target_level(self, value):
        try:
            level = int(value)
        except (TypeError, ValueError):
            raise serializers.ValidationError("Niveau KYC invalide.")
        if level not in (1, 2, 3):
            raise serializers.ValidationError("Niveau KYC doit etre 1, 2 ou 3.")
        return level


class AMLScreeningSerializer(serializers.ModelSerializer):
    class Meta:
        model = AMLScreening
        fields = ["id", "user", "screening_type", "entity_type", "entity_id",
                  "result", "hits", "provider", "screened_at"]
        read_only_fields = ["id", "user", "screening_type", "entity_type", "entity_id",
                            "result", "hits", "provider", "screened_at"]
