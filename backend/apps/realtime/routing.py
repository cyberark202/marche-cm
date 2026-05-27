from django.urls import re_path

from . import consumers

websocket_urlpatterns = [
    re_path(r"^ws/notifications/$", consumers.NotificationConsumer.as_asgi()),
    re_path(r"^ws/chat/(?P<room_id>\d+)/$", consumers.ChatConsumer.as_asgi()),
    re_path(r"^ws/tracking/(?P<shipment_id>\d+)/$", consumers.TrackingConsumer.as_asgi()),
    re_path(r"^ws/dashboard/$", consumers.DashboardConsumer.as_asgi()),
]
