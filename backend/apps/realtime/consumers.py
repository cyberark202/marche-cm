"""
WebSocket consumers for Marché CM.

Consumers:
  - NotificationConsumer: per-user notification stream
  - ChatConsumer: real-time chat with typing indicators
  - TrackingConsumer: live delivery tracking stream
  - DashboardConsumer: admin dashboard live updates

All consumers use Redis channel layers for pub/sub.
"""
import logging
import time

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.core.cache import cache
from django.db import models

from config.websocket_auth import authenticate_scope_user

logger = logging.getLogger(__name__)
security_logger = logging.getLogger("security")


def _coerce_finite_float(value) -> float | None:
    """Return a finite float or None — rejects NaN/inf and unparseable values."""
    if value is None or isinstance(value, bool):
        return None
    try:
        f = float(value)
    except (TypeError, ValueError):
        return None
    if f != f or f in (float("inf"), float("-inf")):  # noqa: PLR0124 — NaN check
        return None
    return f


# Audit ref: [WS-001] BaseAuthConsumer ne valide jamais le JWT.
# Previous version trusted only scope["user"] populated by AuthMiddlewareStack
# (Django session cookie). Mobile clients (3 Flutter apps) have no session
# cookie — they need JWT validation. The new implementation calls
# authenticate_scope_user() which:
#   * accepts Sec-WebSocket-Protocol: bearer, <token> (recommended, no log leak)
#   * accepts Authorization: Bearer <token> header
#   * accepts ?token=<jwt> ONLY in DEBUG / explicit override (audit [WS-002])
#   * validates the JWT signature, expiry, blacklist via SimpleJWT
#   * verifies user.is_active

class BaseAuthConsumer(AsyncJsonWebsocketConsumer):
    """JWT-authenticated WebSocket base — refuses connection if no valid token."""

    async def websocket_connect(self, message):
        user = await authenticate_scope_user(self.scope)
        if user is None:
            security_logger.warning(
                "ws.auth_failed",
                extra={"path": self.scope.get("path", "")},
            )
            await self.close(code=4401)  # 4401 = unauthorized (custom WS close code)
            return
        self.scope["user"] = user
        self.user = user
        await super().websocket_connect(message)

    async def connect(self):
        raise NotImplementedError

    async def disconnect(self, code):
        pass

    async def receive_json(self, content, **kwargs):
        pass


class NotificationConsumer(BaseAuthConsumer):
    """
    Per-user notification stream.
    Group: notification_{user_id}
    Messages pushed here via send_notification() from Celery tasks.
    """

    async def connect(self):
        user = self.scope["user"]
        self.group_name = f"notification_{user.pk}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await self._set_online(True)
        logger.info("ws_notification_connect", extra={"user_id": user.pk})

    async def disconnect(self, code):
        # Audit ref: [M-5] guard against rejected handshakes (auth failure closes
        # before connect() sets group_name) — mirrors the other consumers and
        # avoids an AttributeError on every unauthenticated connection attempt.
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
            await self._set_online(False)

    async def receive_json(self, content, **kwargs):
        msg_type = content.get("type", "")
        if msg_type == "mark_read":
            notification_id = content.get("notification_id")
            if notification_id:
                await self._mark_notification_read(notification_id)

    async def notification_message(self, event):
        """Handler for channel layer messages — pushed from Celery."""
        await self.send_json(event["data"])

    @database_sync_to_async
    def _set_online(self, is_online: bool):
        from django.utils import timezone
        user = self.scope["user"]
        user.is_online = is_online
        user.last_seen_at = timezone.now()
        user.save(update_fields=["is_online", "last_seen_at"])

    @database_sync_to_async
    def _mark_notification_read(self, notification_id: int):
        from apps.notifications.models import Notification
        Notification.objects.filter(pk=notification_id, user=self.scope["user"]).update(is_read=True)


class ChatConsumer(BaseAuthConsumer):
    """
    Real-time chat consumer.
    Group: chat_{room_id}
    Supports: message send, typing indicators, read receipts.
    """

    async def connect(self):
        self.room_id = self.scope["url_route"]["kwargs"]["room_id"]
        self.user = self.scope["user"]

        # Verify user is a participant
        is_participant = await self._check_participant()
        if not is_participant:
            await self.close(code=4003)
            return

        self.group_name = f"chat_{self.room_id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        logger.info("ws_chat_connect", extra={"user_id": self.user.pk, "room_id": self.room_id})

    async def disconnect(self, code):
        if hasattr(self, "group_name"):
            # Send stop-typing to peers
            await self.channel_layer.group_send(
                self.group_name,
                {"type": "typing_indicator", "data": {"user_id": self.user.pk, "is_typing": False}},
            )
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    # Audit ref: [WS-005/WS-006] strict validation on every inbound frame.
    _CHAT_ALLOWED_TYPES = {"chat_message", "typing", "mark_read"}
    _CHAT_ALLOWED_MESSAGE_TYPES = {"TEXT", "IMAGE", "VIDEO", "DOCUMENT"}
    _CHAT_MAX_CONTENT_LEN = 4000
    _CHAT_RATE_KEY_FMT = "ws:chat:rate:{user_id}:{room_id}"
    _CHAT_RATE_WINDOW_SECONDS = 1

    async def receive_json(self, content, **kwargs):
        if not isinstance(content, dict):
            return
        msg_type = content.get("type", "")
        if msg_type not in self._CHAT_ALLOWED_TYPES:
            return

        if msg_type == "chat_message":
            if not await self._chat_rate_limit_ok():
                return
            raw_text = content.get("content", "")
            if not isinstance(raw_text, str):
                return
            text = raw_text[: self._CHAT_MAX_CONTENT_LEN]
            mtype = content.get("message_type", "TEXT")
            if mtype not in self._CHAT_ALLOWED_MESSAGE_TYPES:
                mtype = "TEXT"
            message = await self._save_message(text, mtype)
            await self.channel_layer.group_send(
                self.group_name,
                {
                    "type": "chat_message",
                    "data": {
                        "id": message.pk,
                        "sender_id": self.user.pk,
                        "content": message.content,
                        "type": message.type,
                        "created_at": message.created_at.isoformat(),
                    },
                },
            )
        elif msg_type == "typing":
            is_typing = bool(content.get("is_typing", False))
            await self.channel_layer.group_send(
                self.group_name,
                {"type": "typing_indicator", "data": {"user_id": self.user.pk, "is_typing": is_typing}},
            )
        elif msg_type == "mark_read":
            message_id = content.get("message_id")
            if isinstance(message_id, int) and message_id > 0:
                await self._mark_read(message_id)

    async def _chat_rate_limit_ok(self) -> bool:
        key = self._CHAT_RATE_KEY_FMT.format(
            user_id=getattr(self.user, "pk", "anon"),
            room_id=self.room_id,
        )
        added = await database_sync_to_async(cache.add)(
            key, int(time.time()), self._CHAT_RATE_WINDOW_SECONDS,
        )
        return bool(added)

    async def chat_message(self, event):
        await self.send_json(event["data"])

    async def typing_indicator(self, event):
        if event["data"]["user_id"] != self.user.pk:
            await self.send_json({"type": "typing", **event["data"]})

    @database_sync_to_async
    def _check_participant(self) -> bool:
        from apps.chat.models import ChatRoom
        return ChatRoom.objects.filter(pk=self.room_id, participants=self.scope["user"]).exists()

    @database_sync_to_async
    def _save_message(self, content: str, message_type: str = "TEXT"):
        from apps.chat.models import ChatRoom, Message
        room = ChatRoom.objects.get(pk=self.room_id)
        return Message.objects.create(
            room=room,
            sender=self.scope["user"],
            content=content,
            type=message_type,
        )

    @database_sync_to_async
    def _mark_read(self, message_id: int):
        from apps.chat.models import DeliveryState, MessageReceipt
        from django.utils import timezone
        MessageReceipt.objects.filter(message_id=message_id, user=self.scope["user"]).update(
            state=DeliveryState.READ,
            read_at=timezone.now(),
        )


class TrackingConsumer(BaseAuthConsumer):
    """
    Live delivery tracking stream.
    Group: tracking_{shipment_id}
    Transit agent pushes GPS events; buyer/seller receive them.
    """

    async def connect(self):
        self.shipment_id = self.scope["url_route"]["kwargs"]["shipment_id"]
        self.user = self.scope["user"]

        can_view = await self._can_view_shipment()
        if not can_view:
            await self.close(code=4003)
            return

        self.group_name = f"tracking_{self.shipment_id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    # Audit ref: [WS-003] GPS spoofing TrackingConsumer.
    # Three hardening layers added below:
    #   1. Sender authorization: user must be the *assigned* transit_agent of
    #      the shipment — not just any TRANSIT_AGENT-role user.
    #   2. Coordinate validation: lat ∈ [-90, 90], lng ∈ [-180, 180], finite.
    #   3. Rate limit: max 1 location update per 2s per (agent, shipment).
    _GPS_RATE_KEY_FMT = "ws:gps:rate:{user_id}:{shipment_id}"
    _GPS_RATE_WINDOW_SECONDS = 2

    async def receive_json(self, content, **kwargs):
        msg_type = content.get("type", "")
        if msg_type != "location_update":
            return

        if not await self._is_assigned_transit_agent():
            security_logger.warning(
                "ws.tracking.gps_spoof_attempt",
                extra={
                    "user_id": getattr(self.user, "pk", None),
                    "shipment_id": self.shipment_id,
                },
            )
            return

        lat = _coerce_finite_float(content.get("latitude"))
        lng = _coerce_finite_float(content.get("longitude"))
        if lat is None or lng is None or not (-90.0 <= lat <= 90.0) or not (-180.0 <= lng <= 180.0):
            return

        if not await self._gps_rate_limit_ok():
            return

        await self._save_tracking_event(lat, lng)
        await self.channel_layer.group_send(
            self.group_name,
            {
                "type": "location_update",
                "data": {
                    "shipment_id": self.shipment_id,
                    "latitude": lat,
                    "longitude": lng,
                    "timestamp": content.get("timestamp", ""),
                },
            },
        )

    async def location_update(self, event):
        await self.send_json({"type": "location_update", **event["data"]})

    async def delivery_status(self, event):
        await self.send_json({"type": "delivery_status", **event["data"]})

    async def _gps_rate_limit_ok(self) -> bool:
        key = self._GPS_RATE_KEY_FMT.format(
            user_id=getattr(self.user, "pk", "anon"),
            shipment_id=self.shipment_id,
        )
        # cache.add returns False if the key already exists (within the window).
        # add() is atomic on django-redis and on LocMemCache.
        added = await database_sync_to_async(cache.add)(
            key, int(time.time()), self._GPS_RATE_WINDOW_SECONDS,
        )
        return bool(added)

    @database_sync_to_async
    def _can_view_shipment(self) -> bool:
        from apps.logistics.models import Shipment
        user = self.scope["user"]
        qs = Shipment.objects.filter(pk=self.shipment_id)
        if hasattr(Shipment, "buyer"):
            qs = qs.filter(
                models.Q(buyer=user) | models.Q(seller=user) | models.Q(transit_agent=user)
            )
        return qs.exists()

    @database_sync_to_async
    def _is_assigned_transit_agent(self) -> bool:
        from apps.logistics.models import Shipment
        return Shipment.objects.filter(
            pk=self.shipment_id, transit_agent=self.scope["user"],
        ).exists()

    @database_sync_to_async
    def _save_tracking_event(self, lat: float, lng: float):
        from apps.logistics.models import Shipment, ShipmentEvent
        try:
            shipment = Shipment.objects.get(pk=self.shipment_id)
            ShipmentEvent.objects.create(
                shipment=shipment,
                actor=self.scope["user"],
                status=shipment.status,
                note=f"GPS: {lat},{lng}",
            )
        except Exception:
            logger.exception("tracking_event_save_failed shipment=%s", self.shipment_id)


class DashboardConsumer(BaseAuthConsumer):
    """
    Admin dashboard live updates.
    Only accessible to GENERAL_ADMIN.
    """

    async def connect(self):
        # Audit ref: [FIN-020] use enum, not string comparison.
        from apps.accounts.models import UserRole
        self.user = self.scope["user"]
        if getattr(self.user, "role", None) != UserRole.GENERAL_ADMIN:
            await self.close(code=4003)
            return
        self.group_name = "admin_dashboard"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def dashboard_update(self, event):
        await self.send_json(event["data"])


# ---------------------------------------------------------------------------
# Helper: push notification to a user's WebSocket
# ---------------------------------------------------------------------------

async def push_notification_to_user(channel_layer, user_id: int, data: dict) -> None:
    """
    Push a notification to a connected user via WebSocket.
    Call from Celery tasks after sending the DB notification.
    """
    await channel_layer.group_send(
        f"notification_{user_id}",
        {"type": "notification_message", "data": data},
    )


# Audit ref: [M-5] Clean handler for unknown /ws/* paths.
# Without a catch-all, URLRouter raises when no route matches the path, which
# surfaces to clients as an abrupt 500-style failure (observed for the Driver
# App's stale /ws/driver/ URL). This consumer rejects the handshake cleanly with
# a custom close code so the client gets a deterministic, non-error rejection.
class FallbackWebSocketConsumer(AsyncJsonWebsocketConsumer):
    """Reject any unrouted WebSocket path with close code 4404 (not found)."""

    async def websocket_connect(self, message):
        await self.close(code=4404)
