from .models import Notification
from .realtime import broadcast_user_event


def create_realtime_notification(*, user, title: str, body: str, payload: dict | None = None) -> Notification:
    notification = Notification.objects.create(user=user, title=title, body=body)
    event_payload = {
        "notification_id": notification.id,
        "title": title,
        "body": body,
        "created_at": notification.created_at.isoformat(),
        **(payload or {}),
    }
    broadcast_user_event(
        user_id=user.id,
        topic="notifications",
        event_type="notification_created",
        payload=event_payload,
    )
    return notification
