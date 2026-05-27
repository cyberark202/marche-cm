import os

# MUST be set before any Django or app imports — the app registry loads here.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from django.core.asgi import get_asgi_application

# get_asgi_application() triggers django.setup() which populates the app registry.
# All app-level imports (consumers, routing) must come AFTER this call.
django_asgi_app = get_asgi_application()

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator

from apps.chat.routing import websocket_urlpatterns as chat_ws_patterns
from apps.notifications.routing import websocket_urlpatterns as events_ws_patterns
from apps.realtime.routing import websocket_urlpatterns as realtime_ws_patterns

# Merge all WebSocket URL patterns — order matters (first match wins).
# realtime_ws_patterns: /ws/notifications/, /ws/chat/<id>/, /ws/tracking/<id>/, /ws/dashboard/
# chat_ws_patterns: legacy /ws/chat/ (kept for backward compat)
# events_ws_patterns: legacy /ws/events/
all_ws_patterns = realtime_ws_patterns + chat_ws_patterns + events_ws_patterns

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": AllowedHostsOriginValidator(
            AuthMiddlewareStack(
                URLRouter(all_ws_patterns)
            )
        ),
    }
)
