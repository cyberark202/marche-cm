import json
import time
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.core.cache import cache

from config.websocket_auth import authenticate_scope_user


ALLOWED_TOPICS = {
    "products",
    "orders",
    "chat",
    "logistics",
    "analytics",
    "profiles",
    "wallets",
    "compliance",
    "notifications",
    "support",
    "system",
}


class EventsConsumer(AsyncWebsocketConsumer):
    _TYPING_RATE_KEY_FMT = "ws:typing:{user_id}:{room_id}"
    _TYPING_RATE_WINDOW_SECONDS = 2

    async def connect(self):
        user = await authenticate_scope_user(self.scope)
        if user is None:
            await self.close(code=4401)
            return
        self.user = user

        raw_query = self.scope.get("query_string", b"").decode()
        query = parse_qs(raw_query)
        topics = query.get("topics", [",".join(sorted(ALLOWED_TOPICS))])[0]
        self.topics = sorted({topic for topic in [t.strip() for t in topics.split(",")] if topic in ALLOWED_TOPICS})
        if not self.topics:
            await self.close(code=4400)
            return

        for topic in self.topics:
            await self.channel_layer.group_add(f"events_{topic}", self.channel_name)
        self.user_group = f"user_{self.user.id}"
        await self.channel_layer.group_add(self.user_group, self.channel_name)
        await self.accept()
        await self._set_online(True)

    async def disconnect(self, close_code):
        for topic in getattr(self, "topics", []):
            await self.channel_layer.group_discard(f"events_{topic}", self.channel_name)
        if hasattr(self, "user_group"):
            await self.channel_layer.group_discard(self.user_group, self.channel_name)
            await self._set_online(False)

    async def receive(self, text_data=None, bytes_data=None):
        """Seul message entrant accepté : le signal typing du chat, relayé
        éphémère (jamais persisté) aux autres participants du salon."""
        if not text_data:
            return
        try:
            content = json.loads(text_data)
        except (TypeError, ValueError):
            return
        if not isinstance(content, dict) or content.get("type") != "typing":
            return
        room_id = content.get("room")
        if not isinstance(room_id, int) or room_id <= 0:
            return
        if not await self._typing_rate_ok(room_id):
            return
        participant_ids = await self._room_participant_ids(room_id)
        if self.user.id not in participant_ids:
            return
        payload = {
            "room": room_id,
            "user_id": self.user.id,
            "is_typing": bool(content.get("is_typing", False)),
        }
        for user_id in participant_ids:
            if user_id == self.user.id:
                continue
            await self.channel_layer.group_send(
                f"user_{user_id}",
                {"type": "event.message", "topic": "chat", "event_type": "typing", "payload": payload},
            )

    async def event_message(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "topic": event["topic"],
                    "type": event["event_type"],
                    "payload": event["payload"],
                }
            )
        )

    async def _typing_rate_ok(self, room_id: int) -> bool:
        key = self._TYPING_RATE_KEY_FMT.format(user_id=self.user.id, room_id=room_id)
        added = await database_sync_to_async(cache.add)(key, int(time.time()), self._TYPING_RATE_WINDOW_SECONDS)
        return bool(added)

    @database_sync_to_async
    def _room_participant_ids(self, room_id: int) -> set:
        from apps.chat.models import ChatRoom

        room = ChatRoom.objects.filter(pk=room_id).first()
        if room is None:
            return set()
        return set(room.participants.values_list("id", flat=True))

    @database_sync_to_async
    def _set_online(self, is_online: bool):
        from django.utils import timezone

        type(self.user).objects.filter(pk=self.user.pk).update(
            is_online=is_online, last_seen_at=timezone.now()
        )
