from rest_framework import decorators, permissions, response, status, viewsets

from .models import Notification, NotificationCategory, NotificationPreference
from .serializers import NotificationPreferenceSerializer, NotificationSerializer


class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = Notification.objects.all()

    def get_queryset(self):
        qs = self.queryset.filter(user=self.request.user).order_by("-created_at")
        category = self.request.query_params.get("category", "").upper()
        if category in NotificationCategory.values:
            qs = qs.filter(category=category)
        if self.request.query_params.get("unread") == "1":
            qs = qs.filter(is_read=False)
        return qs

    @decorators.action(detail=False, methods=["get", "put", "patch"], url_path="preferences")
    def preferences(self, request):
        prefs, _ = NotificationPreference.objects.get_or_create(user=request.user)
        if request.method in {"PUT", "PATCH"}:
            serializer = NotificationPreferenceSerializer(prefs, data=request.data, partial=True)
            serializer.is_valid(raise_exception=True)
            serializer.save()
        return response.Response(NotificationPreferenceSerializer(prefs).data)

    @decorators.action(detail=True, methods=["post"])
    def mark_read(self, request, pk=None):
        notification = self.get_object()
        if notification.is_read:
            return response.Response(
                NotificationSerializer(notification).data,
                status=status.HTTP_200_OK,
            )
        notification.is_read = True
        notification.save(update_fields=["is_read"])
        return response.Response(
            NotificationSerializer(notification).data,
            status=status.HTTP_200_OK,
        )

    @decorators.action(detail=False, methods=["post"])
    def mark_all_read(self, request):
        updated = self.get_queryset().filter(is_read=False).update(is_read=True)
        return response.Response(
            {"detail": "Notifications marquees comme lues.", "updated": updated},
            status=status.HTTP_200_OK,
        )
