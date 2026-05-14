import json
from urllib.parse import parse_qs

from channels.generic.websocket import AsyncWebsocketConsumer

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
}


class EventsConsumer(AsyncWebsocketConsumer):
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

    async def disconnect(self, close_code):
        for topic in getattr(self, "topics", []):
            await self.channel_layer.group_discard(f"events_{topic}", self.channel_name)
        if hasattr(self, "user_group"):
            await self.channel_layer.group_discard(self.user_group, self.channel_name)

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
