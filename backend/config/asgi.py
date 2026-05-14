import os

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

from apps.chat.routing import websocket_urlpatterns as chat_ws_patterns
from apps.notifications.routing import websocket_urlpatterns as events_ws_patterns

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

application = ProtocolTypeRouter(
    {
        "http": get_asgi_application(),
        "websocket": AuthMiddlewareStack(URLRouter(chat_ws_patterns + events_ws_patterns)),
    }
)
