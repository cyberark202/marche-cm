from rest_framework import serializers
from django.conf import settings

from apps.accounts.upload_security import validate_uploaded_file
from core.text_sanitize import redact_links
from .models import ChatRoom, DeliveryState, Message, MessageReceipt


def message_preview(message_type: str, content: str) -> str:
    """Aperçu court type-aware d'un message (liste de conversations, push, citation)."""
    if message_type == "TEXT":
        text = (content or "").strip()
        return text[:120] if text else "Nouveau message"
    return {
        "IMAGE": "📷 Photo",
        "VIDEO": "🎥 Vidéo",
        "AUDIO": "🎤 Note vocale",
        "DOCUMENT": "📎 Document",
    }.get(message_type, "Nouveau message")


class ChatRoomSerializer(serializers.ModelSerializer):
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()
    peer = serializers.SerializerMethodField()

    class Meta:
        model = ChatRoom
        fields = "__all__"
        read_only_fields = ("created_at",)

    def get_last_message(self, obj):
        message_type = getattr(obj, "last_message_type", None)
        created_at = getattr(obj, "last_message_at", None)
        if not created_at:
            return None
        return {
            "type": message_type,
            "snippet": message_preview(message_type, getattr(obj, "last_message_content", "")),
            "sender": getattr(obj, "last_message_sender_id", None),
            "created_at": created_at.isoformat(),
        }

    def get_unread_count(self, obj):
        return int(getattr(obj, "unread_count", 0) or 0)

    def get_peer(self, obj):
        request = self.context.get("request")
        user = request.user if request else None
        if user is None or not user.is_authenticated:
            return None
        peer = next((p for p in obj.participants.all() if p.id != user.id), None)
        if peer is None:
            return None
        avatar_url = ""
        if peer.avatar:
            avatar_url = request.build_absolute_uri(peer.avatar.url)
        return {
            "id": peer.id,
            "username": peer.username,
            "role": peer.role,
            "avatar_url": avatar_url,
            "is_online": bool(peer.is_online),
            "last_seen_at": peer.last_seen_at.isoformat() if peer.last_seen_at else None,
        }


class MessageSerializer(serializers.ModelSerializer):
    my_state = serializers.SerializerMethodField()
    reply_preview = serializers.SerializerMethodField()
    reactions = serializers.SerializerMethodField()

    MAX_CONTENT_LEN = 4000
    ALLOWED_TYPES = {"TEXT", "IMAGE", "VIDEO", "DOCUMENT", "AUDIO"}

    class Meta:
        model = Message
        fields = "__all__"
        read_only_fields = ("sender", "created_at")

    def get_my_state(self, obj):
        user = self.context.get("request").user if self.context.get("request") else None
        if not user or not user.is_authenticated:
            return ""
        if obj.sender_id == user.id:
            states = [r.state for r in obj.receipts.all()]
            if not states:
                return DeliveryState.SENT
            if all(s == DeliveryState.READ for s in states):
                return DeliveryState.READ
            if all(s in (DeliveryState.READ, DeliveryState.DELIVERED) for s in states):
                return DeliveryState.DELIVERED
            return DeliveryState.SENT
        receipt = next((r for r in obj.receipts.all() if r.user_id == user.id), None)
        return receipt.state if receipt else ""

    def get_reactions(self, obj):
        user = self.context.get("request").user if self.context.get("request") else None
        my_id = user.id if user and user.is_authenticated else None
        aggregated = {}
        for reaction in obj.reactions.all():
            entry = aggregated.setdefault(reaction.emoji, {"emoji": reaction.emoji, "count": 0, "mine": False})
            entry["count"] += 1
            if reaction.user_id == my_id:
                entry["mine"] = True
        return list(aggregated.values())

    def get_reply_preview(self, obj):
        parent = obj.reply_to
        if parent is None:
            return None
        return {
            "id": parent.id,
            "sender": parent.sender_id,
            "type": parent.type,
            "snippet": message_preview(parent.type, parent.content),
        }

    def validate_reply_to(self, value):
        if value is None:
            return value
        room = self.initial_data.get("room")
        try:
            room_id = int(room)
        except (TypeError, ValueError):
            room_id = None
        if room_id is not None and value.room_id != room_id:
            raise serializers.ValidationError(
                "Le message cité doit appartenir au même salon."
            )
        return value

    def validate_content(self, value):
        if value and len(value) > self.MAX_CONTENT_LEN:
            raise serializers.ValidationError(
                f"Message trop long ({self.MAX_CONTENT_LEN} caracteres max)."
            )
        return redact_links(
            value,
            redact_phones=getattr(settings, "CHAT_REDACT_PHONE_NUMBERS", False),
        )

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
        if content_type.startswith("audio/"):
            validate_uploaded_file(
                value,
                field_label="Note vocale",
                allowed_extensions={".m4a", ".aac", ".mp3", ".ogg", ".opus", ".wav"},
                max_mb=settings.MAX_UPLOAD_AUDIO_MB,
                allowed_content_types={
                    "audio/mp4", "audio/aac", "audio/x-m4a", "audio/mpeg",
                    "audio/ogg", "audio/opus", "audio/wav", "audio/x-wav",
                },
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
