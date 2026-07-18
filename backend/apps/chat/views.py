from django.db.models import Count, IntegerField, OuterRef, Subquery, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.security import write_audit_log
from apps.notifications.realtime import broadcast_user_event
from .models import ChatRoom, DeliveryState, Message, MessageReaction, MessageReceipt
from .serializers import ChatRoomSerializer, MessageSerializer, message_preview


def notify_participants(room, event_type: str, payload: dict, exclude_user_id: int | None = None) -> None:
    """Événement temps réel CIBLÉ aux participants du salon (groupe user_<id>).

    Remplace l'ancien broadcast_event global sur le topic `chat` : celui-ci
    diffusait les métadonnées de TOUS les salons à tout utilisateur authentifié
    abonné au topic (fuite d'ids message/room/sender).
    """
    for user_id in room.participants.values_list("id", flat=True):
        if user_id == exclude_user_id:
            continue
        broadcast_user_event(user_id=user_id, topic="chat", event_type=event_type, payload=payload)


class ChatRoomViewSet(viewsets.ModelViewSet):
    serializer_class = ChatRoomSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        # Annotations « liste de conversations » (dernier message + non-lus),
        # en sous-requêtes pour éviter la multiplication de lignes des joins.
        last_message = Message.objects.filter(room=OuterRef("pk")).order_by("-created_at")
        unread = (
            MessageReceipt.objects.filter(message__room=OuterRef("pk"), user=self.request.user)
            .exclude(state=DeliveryState.READ)
            .order_by()
            .values("message__room")
            .annotate(total=Count("pk"))
            .values("total")[:1]
        )
        return (
            ChatRoom.objects.filter(participants=self.request.user)
            .distinct()
            .prefetch_related("participants")
            .annotate(
                last_message_at=Subquery(last_message.values("created_at")[:1]),
                last_message_type=Subquery(last_message.values("type")[:1]),
                last_message_content=Subquery(last_message.values("content")[:1]),
                last_message_sender_id=Subquery(last_message.values("sender_id")[:1]),
                unread_count=Coalesce(Subquery(unread, output_field=IntegerField()), 0),
            )
            .order_by(Coalesce("last_message_at", "created_at").desc())
        )

    def perform_create(self, serializer):
        room = serializer.save()
        room.participants.add(self.request.user)
        notify_participants(room, "room_created", {"id": room.id, "name": room.name})

    @decorators.action(detail=True, methods=["post"])
    def mark_read(self, request, pk=None):
        """Marque TOUS les messages non lus du salon comme lus (un seul POST,
        remplace la boucle client « 2 requêtes par message »)."""
        room = self.get_object()
        pending = MessageReceipt.objects.filter(message__room=room, user=request.user).exclude(
            state=DeliveryState.READ
        )
        sender_ids = set(pending.values_list("message__sender_id", flat=True))
        now = timezone.now()
        updated = pending.update(
            state=DeliveryState.READ, read_at=now, delivered_at=Coalesce("delivered_at", Value(now))
        )
        for sender_id in sender_ids:
            broadcast_user_event(
                user_id=sender_id,
                topic="chat",
                event_type="room_read",
                payload={"room": room.id, "reader_id": request.user.id},
            )
        return response.Response({"updated": updated})


class MessageViewSet(viewsets.ModelViewSet):
    serializer_class = MessageSerializer
    permission_classes = [permissions.IsAuthenticated]

    # Audit ref: [CHAT-001] disallow PATCH/PUT/DELETE — rewriting another
    # participant's message would destroy dispute evidence. Append-only chat.
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        queryset = (
            Message.objects.filter(room__participants=self.request.user)
            .select_related("sender", "room", "reply_to")
        )
        room_id = self.request.query_params.get("room")
        if room_id:
            queryset = queryset.filter(room_id=room_id)
        # Audit ref: [CHAT-002] q-filter hardening — bound length, escape SQL
        # LIKE wildcards (% and _), require room_id when searching.
        raw_term = (self.request.query_params.get("q") or "").strip()
        if raw_term:
            if not room_id:
                # Cross-room full-text search is forbidden: a single attacker
                # in one room could otherwise harvest every message containing
                # tokens like "password" across all their rooms.
                raise PermissionDenied("Le parametre `room` est obligatoire pour rechercher.")
            if len(raw_term) < 3 or len(raw_term) > 80:
                # Reject too-short (matches "all") and too-long (DoS) terms.
                queryset = queryset.none()
            else:
                term = raw_term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
                queryset = queryset.filter(content__icontains=term)
        return queryset.prefetch_related("receipts", "reactions")

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
        # Message COMPLET sérialisé vers chaque destinataire (groupe user_<id>) :
        # le client l'insère dans le fil ouvert sans re-fetch REST.
        payload = MessageSerializer(message, context=self.get_serializer_context()).data
        for user_id in recipient_ids:
            broadcast_user_event(user_id=user_id, topic="chat", event_type="message_created", payload=payload)
        # Real-time delivery when the recipient's app is backgrounded/closed:
        # WebSocket (above) only reaches connected clients, so we also fire an
        # async FCM push (push-only — no in-app Notification row, chat has its
        # own unread tracking). Enqueued so a slow/absent broker never blocks
        # the send request.
        self._push_new_message(message, recipient_ids)

    def _push_new_message(self, message, recipient_ids):
        if not recipient_ids:
            return
        try:
            from apps.notifications.tasks import send_push

            preview = message_preview(message.type, message.content)
            data = {
                "kind": "chat",
                "room_id": message.room_id,
                "message_id": message.id,
                "type": message.type,
            }
            for user_id in recipient_ids:
                send_push.delay(
                    user_id=user_id,
                    title="Nouveau message",
                    body=preview,
                    data=data,
                )
        except Exception:  # noqa: BLE001 — push is best-effort, never break send.
            pass

    def _notify_sender_state(self, message, state: str):
        broadcast_user_event(
            user_id=message.sender_id,
            topic="chat",
            event_type="message_state",
            payload={
                "message_id": message.id,
                "room": message.room_id,
                "user_id": self.request.user.id,
                "state": state,
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
        self._notify_sender_state(message, DeliveryState.DELIVERED)
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
        self._notify_sender_state(message, DeliveryState.READ)
        return response.Response({"detail": "Message marque comme lu."})

    @decorators.action(detail=True, methods=["post"])
    def react(self, request, pk=None):
        """Réaction emoji façon WhatsApp : POST {emoji} pose/remplace la réaction
        de l'utilisateur ; le même emoji (ou vide) la retire."""
        message = self.get_object()
        emoji = str(request.data.get("emoji") or "").strip()
        if len(emoji) > 8:
            raise ValidationError({"emoji": "Emoji invalide."})
        existing = MessageReaction.objects.filter(message=message, user=request.user).first()
        if not emoji or (existing and existing.emoji == emoji):
            if existing:
                existing.delete()
        elif existing:
            existing.emoji = emoji
            existing.save(update_fields=["emoji"])
        else:
            MessageReaction.objects.create(message=message, user=request.user, emoji=emoji)

        aggregated = {}
        for row in message.reactions.values("emoji", "user_id"):
            entry = aggregated.setdefault(row["emoji"], {"emoji": row["emoji"], "count": 0, "user_ids": []})
            entry["count"] += 1
            entry["user_ids"].append(row["user_id"])
        reactions = list(aggregated.values())
        notify_participants(
            message.room,
            "message_reaction",
            {"message_id": message.id, "room": message.room_id, "reactions": reactions},
            exclude_user_id=request.user.id,
        )
        return response.Response({"reactions": reactions})
