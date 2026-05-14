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

    class Meta:
        model = Message
        fields = "__all__"
        read_only_fields = ("sender", "created_at")

    def get_my_state(self, obj):
        user = self.context.get("request").user if self.context.get("request") else None
        if not user or not user.is_authenticated:
            return ""
        receipt = obj.receipts.filter(user=user).first()
        return receipt.state if receipt else ""

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
