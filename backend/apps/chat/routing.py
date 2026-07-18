# Le chat n'a plus de WebSocket dédié : l'envoi passe par REST
# (apps/chat/views.py) et la réception/typing par /ws/events/
# (EventsConsumer, événements ciblés user_<id>). L'ancien /ws/chat/<room_id>/
# n'était connecté par aucune app — supprimé. Conservé (vide) car
# config/asgi.py et les tests l'importent.
websocket_urlpatterns: list = []
