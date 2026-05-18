import os

# MUST be set before any Django or app imports — the app registry loads here.
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from django.core.asgi import get_asgi_application

# get_asgi_application() triggers django.setup() which populates the app registry.
# All app-level imports (consumers, routing) must come AFTER this call.
django_asgi_app = get_asgi_application()

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter

from apps.chat.routing import websocket_urlpatterns as chat_ws_patterns
from apps.notifications.routing import websocket_urlpatterns as events_ws_patterns

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": AuthMiddlewareStack(
            URLRouter(chat_ws_patterns + events_ws_patterns)
        ),
    }
)
