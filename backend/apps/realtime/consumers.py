"""
WebSocket consumers for Marché CM.

Consumers:
  - NotificationConsumer: per-user notification stream
  - TrackingConsumer: live delivery tracking stream
  - DashboardConsumer: admin dashboard live updates

Le chat temps réel ne passe PAS par ici : envoi via REST (apps/chat/views.py),
réception/typing via /ws/events/ (apps/notifications/consumers.EventsConsumer,
événements ciblés user_<id>).

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



class BaseAuthConsumer(AsyncJsonWebsocketConsumer):
    """JWT-authenticated WebSocket base — refuses connection if no valid token."""

    async def websocket_connect(self, message):
        user = await authenticate_scope_user(self.scope)
        if user is None:
            security_logger.warning(
                "ws.auth_failed",
                extra={"path": self.scope.get("path", "")},
            )
            await self.close(code=4401)
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
        from django.utils import timezone
        from apps.logistics.models import Shipment, ShipmentEvent
        try:
            shipment = Shipment.objects.get(pk=self.shipment_id)
            shipment.current_latitude = lat
            shipment.current_longitude = lng
            shipment.location_updated_at = timezone.now()
            shipment.save(
                update_fields=["current_latitude", "current_longitude", "location_updated_at"]
            )
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



async def push_notification_to_user(channel_layer, user_id: int, data: dict) -> None:
    """
    Push a notification to a connected user via WebSocket.
    Call from Celery tasks after sending the DB notification.
    """
    await channel_layer.group_send(
        f"notification_{user_id}",
        {"type": "notification_message", "data": data},
    )


class FallbackWebSocketConsumer(AsyncJsonWebsocketConsumer):
    """Reject any unrouted WebSocket path with close code 4404 (not found)."""

    async def websocket_connect(self, message):
        await self.close(code=4404)
