from rest_framework import serializers
from django.conf import settings

from apps.accounts.upload_security import validate_uploaded_file
from .models import ChatRoom, Message, MessageReceipt


class ChatRoomSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChatRoom
        fields = "__all__"
        read_only_fields = ("created_at",)


class MessageSerializer(serializers.ModelSerializer):
    my_state = serializers.SerializerMethodField()

    # Audit ref: [N-002] defense in depth — the same length/type validation
    # the WS consumer enforces (apps/realtime/consumers.py) MUST also live in
    # the REST serializer. Otherwise a client can bypass the WS hardening by
    # POSTing directly to /api/chat/messages/.
    MAX_CONTENT_LEN = 4000
    ALLOWED_TYPES = {"TEXT", "IMAGE", "VIDEO", "DOCUMENT"}

    class Meta:
        model = Message
        fields = "__all__"
        read_only_fields = ("sender", "created_at")

    def get_my_state(self, obj):
        user = self.context.get("request").user if self.context.get("request") else None
        if not user or not user.is_authenticated:
            return ""
        receipt = next((r for r in obj.receipts.all() if r.user_id == user.id), None)
        return receipt.state if receipt else ""

    def validate_content(self, value):
        if value and len(value) > self.MAX_CONTENT_LEN:
            raise serializers.ValidationError(
                f"Message trop long ({self.MAX_CONTENT_LEN} caracteres max)."
            )
        return value

    def validate_type(self, value):
        if value not in self.ALLOWED_TYPES:
            raise serializers.ValidationError(
                f"Type de message invalide. Valeurs autorisees: {sorted(self.ALLOWED_TYPES)}."
            )
        return value

    def validate_file(self, value):
        content_type = str(getattr(value, "content_type", "") or "").lower()
        if content_type.startswith("image/"):
            validate_uploaded_file(
                value,
                field_label="Fichier chat (image)",
                allowed_extensions={".png", ".jpg", ".jpeg", ".webp"},
                max_mb=settings.MAX_UPLOAD_IMAGE_MB,
                allowed_content_types={"image/png", "image/jpeg", "image/webp"},
            )
            return value
        if content_type.startswith("video/"):
            validate_uploaded_file(
                value,
                field_label="Fichier chat (video)",
                allowed_extensions={".mp4", ".mov", ".webm", ".m4v"},
                max_mb=settings.MAX_UPLOAD_VIDEO_MB,
                allowed_content_types={"video/mp4", "video/quicktime", "video/webm", "video/x-m4v"},
            )
            return value
        validate_uploaded_file(
            value,
            field_label="Fichier chat",
            allowed_extensions={".pdf", ".doc", ".docx", ".xls", ".xlsx", ".txt"},
            max_mb=settings.MAX_UPLOAD_DOCUMENT_MB,
            allowed_content_types={
                "application/pdf",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "text/plain",
            },
        )
        return value


class MessageReceiptSerializer(serializers.ModelSerializer):
    class Meta:
        model = MessageReceipt
        fields = "__all__"
