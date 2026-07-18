import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from django.core.asgi import get_asgi_application

django_asgi_app = get_asgi_application()

from django.urls import re_path

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator

from apps.chat.routing import websocket_urlpatterns as chat_ws_patterns
from apps.notifications.routing import websocket_urlpatterns as events_ws_patterns
from apps.realtime.consumers import FallbackWebSocketConsumer
from apps.realtime.routing import websocket_urlpatterns as realtime_ws_patterns

all_ws_patterns = (
    realtime_ws_patterns
    + chat_ws_patterns
    + events_ws_patterns
    + [re_path(r"^ws/.*$", FallbackWebSocketConsumer.as_asgi())]
)

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
