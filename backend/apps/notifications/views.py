from rest_framework import decorators, permissions, response, status, viewsets

from .models import Notification
from .serializers import NotificationSerializer


class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = Notification.objects.all()

    def get_queryset(self):
        return self.queryset.filter(user=self.request.user).order_by("-created_at")

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
