from rest_framework import serializers

from .models import SupportTicket, SupportTicketMessage, TicketPriority, TicketStatus


class SupportTicketMessageSerializer(serializers.ModelSerializer):
    author_username = serializers.CharField(source="author.username", read_only=True)
    author_role = serializers.CharField(source="author.role", read_only=True)

    class Meta:
        model = SupportTicketMessage
        fields = ("id", "author", "author_username", "author_role", "body", "is_internal", "created_at")
        read_only_fields = ("id", "author", "author_username", "author_role", "created_at")

    def validate_body(self, value):
        body = (value or "").strip()
        if len(body) < 2:
            raise serializers.ValidationError("Le message est trop court.")
        return body


class SupportTicketSerializer(serializers.ModelSerializer):
    created_by_username = serializers.CharField(source="created_by.username", read_only=True)
    assigned_to_username = serializers.CharField(source="assigned_to.username", read_only=True)
    messages = SupportTicketMessageSerializer(many=True, read_only=True)
    messages_count = serializers.IntegerField(source="messages.count", read_only=True)

    class Meta:
        model = SupportTicket
        fields = (
            "id",
            "subject",
            "description",
            "category",
            "status",
            "priority",
            "created_by",
            "created_by_username",
            "assigned_to",
            "assigned_to_username",
            "last_activity_at",
            "created_at",
            "updated_at",
            "messages_count",
            "messages",
        )
        read_only_fields = (
            "id",
            "created_by",
            "created_by_username",
            "assigned_to_username",
            "last_activity_at",
            "created_at",
            "updated_at",
            "messages_count",
            "messages",
        )

    def validate_subject(self, value):
        subject = (value or "").strip()
        if len(subject) < 5:
            raise serializers.ValidationError("Le sujet doit contenir au moins 5 caracteres.")
        return subject

    def validate_description(self, value):
        description = (value or "").strip()
        if len(description) < 10:
            raise serializers.ValidationError("La description doit contenir au moins 10 caracteres.")
        return description

    def validate_priority(self, value):
        if value not in TicketPriority.values:
            raise serializers.ValidationError("Priorite invalide.")
        return value

    def validate_status(self, value):
        if value not in TicketStatus.values:
            raise serializers.ValidationError("Statut invalide.")
        return value
