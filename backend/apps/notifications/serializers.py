from rest_framework import serializers

from .models import Notification, NotificationPreference


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ("id", "title", "body", "category", "priority", "is_read", "created_at")
        read_only_fields = ("id", "title", "body", "category", "priority", "created_at")


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationPreference
        fields = ("promotions_enabled", "push_enabled", "updated_at")
        read_only_fields = ("updated_at",)
