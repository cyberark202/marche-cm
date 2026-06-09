import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

logger = logging.getLogger(__name__)


def broadcast_event(topic: str, event_type: str, payload: dict) -> None:
    """Diffuse un évènement temps réel — best-effort.

    Une panne du channel layer (Redis down, timeout) ne doit JAMAIS casser le
    flux appelant : ces diffusions sont émises après des transactions
    financières déjà committées. On avale et on journalise l'échec.
    """
    try:
        layer = get_channel_layer()
        if not layer:
            return
        async_to_sync(layer.group_send)(
            f"events_{topic}",
            {
                "type": "event.message",
                "topic": topic,
                "event_type": event_type,
                "payload": payload,
            },
        )
    except Exception:
        logger.warning("broadcast_event_failed topic=%s event=%s", topic, event_type, exc_info=True)


def broadcast_user_event(*, user_id: int, topic: str, event_type: str, payload: dict) -> None:
    """Diffuse un évènement ciblé utilisateur — best-effort (cf. broadcast_event)."""
    try:
        layer = get_channel_layer()
        if not layer:
            return
        async_to_sync(layer.group_send)(
            f"user_{user_id}",
            {
                "type": "event.message",
                "topic": topic,
                "event_type": event_type,
                "payload": payload,
            },
        )
    except Exception:
        logger.warning("broadcast_user_event_failed user=%s event=%s", user_id, event_type, exc_info=True)
