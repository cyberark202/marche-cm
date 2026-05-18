import json

from asgiref.sync import sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

from config.websocket_auth import authenticate_scope_user
from .models import ChatRoom


@sync_to_async
def _is_room_participant(room_id, user_id):
    return ChatRoom.objects.filter(id=room_id, participants__id=user_id).exists()


class ChatConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        user = await authenticate_scope_user(self.scope)
        if user is None:
            await self.close(code=4401)
            return

        self.room_id = int(self.scope["url_route"]["kwargs"]["room_id"])
        if not await _is_room_participant(self.room_id, user.id):
            await self.close(code=4403)
            return

        self.user = user
        self.group_name = f"chat_{self.room_id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        if not text_data:
            return
        try:
            payload = json.loads(text_data)
        except json.JSONDecodeError:
            return
        if not isinstance(payload, dict):
            return
        payload["sender_id"] = self.user.id
        payload["room_id"] = self.room_id
        await self.channel_layer.group_send(
            self.group_name,
            {
                "type": "chat.message",
                "payload": payload,
            },
        )

    async def chat_message(self, event):
        await self.send(text_data=json.dumps(event["payload"]))
