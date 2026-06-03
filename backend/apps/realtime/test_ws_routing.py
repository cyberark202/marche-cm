"""M-5 — WebSocket routing: known routes connect, unknown paths are rejected
cleanly (no 500), and the driver uses the real shared events stream.

Real Channels WebsocketCommunicator tests against the actual URLRouter +
consumers. We bypass only the AllowedHostsOriginValidator wrapper (origin
checking is orthogonal and environment-dependent); auth is exercised for real
through the JWT `bearer` sub-protocol path.
"""
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from django.test.utils import override_settings
from django.urls import re_path
from rest_framework_simplejwt.tokens import AccessToken

from apps.accounts import field_crypto
from apps.chat.routing import websocket_urlpatterns as chat_ws
from apps.notifications.routing import websocket_urlpatterns as events_ws
from apps.realtime.consumers import FallbackWebSocketConsumer
from apps.realtime.routing import websocket_urlpatterns as realtime_ws
from django.contrib.auth import get_user_model

WS_APP = URLRouter(
    realtime_ws + chat_ws + events_ws
    + [re_path(r"^ws/.*$", FallbackWebSocketConsumer.as_asgi())]
)


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class WebSocketRoutingTests(TransactionTestCase):
    def setUp(self):
        field_crypto.clear_crypto_cache()
        self.user = get_user_model().objects.create_user(
            username="ws_user", email="ws_user@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=1, country_code="CM",
            phone_number="+237690001101")
        self.token = str(AccessToken.for_user(self.user))

    async def _connect(self, path, with_token=True):
        subprotocols = ["bearer", self.token] if with_token else None
        comm = WebsocketCommunicator(WS_APP, path, subprotocols=subprotocols)
        connected, _ = await comm.connect()
        await comm.disconnect()
        return connected

    async def test_known_events_route_accepts_with_jwt(self):
        self.assertTrue(await self._connect("/ws/events/?topics=orders"))

    async def test_known_route_rejects_without_token(self):
        self.assertFalse(await self._connect("/ws/notifications/", with_token=False))

    async def test_unknown_driver_path_is_rejected_cleanly(self):
        # The stale Driver App path: must NOT raise (no 500) and must NOT connect.
        self.assertFalse(await self._connect("/ws/driver/"))

    async def test_other_unknown_path_is_rejected_cleanly(self):
        self.assertFalse(await self._connect("/ws/totally-unknown/"))

    def test_driver_config_points_to_real_endpoint(self):
        """Guard the frontend fix: driverWsUrl must target /ws/events/, never the
        non-existent /ws/driver/."""
        import os
        cfg = os.path.join(
            os.path.dirname(__file__), "..", "..", "..",
            "frontend", "Driver App", "app", "lib", "core", "config", "app_config.dart",
        )
        cfg = os.path.abspath(cfg)
        if not os.path.exists(cfg):
            self.skipTest("Driver App config not present in this checkout")
        content = open(cfg, encoding="utf-8").read()
        self.assertIn("/ws/events/", content)
        self.assertNotIn("/ws/driver/", content)
