from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied

from apps.accounts.security import write_audit_log
from apps.notifications.realtime import broadcast_event
from .models import ChatRoom, DeliveryState, Message, MessageReceipt
from .serializers import ChatRoomSerializer, MessageSerializer


class ChatRoomViewSet(viewsets.ModelViewSet):
    serializer_class = ChatRoomSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return ChatRoom.objects.filter(participants=self.request.user).distinct()

    def perform_create(self, serializer):
        room = serializer.save()
        room.participants.add(self.request.user)
        broadcast_event("chat", "room_created", {"id": room.id, "name": room.name})


class MessageViewSet(viewsets.ModelViewSet):
    serializer_class = MessageSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        queryset = Message.objects.filter(room__participants=self.request.user).select_related("sender", "room")
        room_id = self.request.query_params.get("room")
        if room_id:
            queryset = queryset.filter(room_id=room_id)
        term = (self.request.query_params.get("q") or "").strip()
        if term:
            queryset = queryset.filter(content__icontains=term)
        return queryset.prefetch_related("receipts")

    def perform_create(self, serializer):
        room = serializer.validated_data["room"]
        if not room.participants.filter(id=self.request.user.id).exists():
            raise PermissionDenied("Vous devez faire partie du salon pour envoyer un message.")
        message = serializer.save(sender=self.request.user)
        recipient_ids = list(message.room.participants.exclude(id=self.request.user.id).values_list("id", flat=True))
        MessageReceipt.objects.bulk_create(
            [
                MessageReceipt(
                    message=message,
                    user_id=user_id,
                    state=DeliveryState.SENT,
                )
                for user_id in recipient_ids
            ]
        )
        write_audit_log(
            actor=self.request.user,
            action="Message chat envoye",
            action_key="chat.send",
            metadata={"room_id": message.room_id, "message_id": message.id},
        )
        broadcast_event(
            "chat",
            "message_created",
            {
                "id": message.id,
                "room": message.room_id,
                "sender": message.sender_id,
                "type": message.type,
            },
        )

    @decorators.action(detail=True, methods=["post"])
    def mark_delivered(self, request, pk=None):
        message = self.get_object()
        receipt = MessageReceipt.objects.filter(message=message, user=request.user).first()
        if not receipt:
            return response.Response({"detail": "Aucun etat a mettre a jour."}, status=status.HTTP_404_NOT_FOUND)
        if receipt.state == DeliveryState.SENT:
            receipt.state = DeliveryState.DELIVERED
            receipt.delivered_at = timezone.now()
            receipt.save(update_fields=["state", "delivered_at"])
        broadcast_event("chat", "message_delivered", {"message_id": message.id, "user_id": request.user.id})
        return response.Response({"detail": "Message marque comme delivre."})

    @decorators.action(detail=True, methods=["post"])
    def mark_read(self, request, pk=None):
        message = self.get_object()
        receipt = MessageReceipt.objects.filter(message=message, user=request.user).first()
        if not receipt:
            return response.Response({"detail": "Aucun etat a mettre a jour."}, status=status.HTTP_404_NOT_FOUND)
        if receipt.state != DeliveryState.READ:
            if receipt.delivered_at is None:
                receipt.delivered_at = timezone.now()
            receipt.state = DeliveryState.READ
            receipt.read_at = timezone.now()
            receipt.save(update_fields=["state", "delivered_at", "read_at"])
        broadcast_event("chat", "message_read", {"message_id": message.id, "user_id": request.user.id})
        return response.Response({"detail": "Message marque comme lu."})
