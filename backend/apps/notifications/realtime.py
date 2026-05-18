from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_event(topic: str, event_type: str, payload: dict) -> None:
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


def broadcast_user_event(*, user_id: int, topic: str, event_type: str, payload: dict) -> None:
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
