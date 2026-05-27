"""
Notification Celery tasks — async delivery via FCM, email, SMS, WebSocket.
"""
import logging
from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.notifications.tasks.send_notification",
    bind=True,
    max_retries=3,
    default_retry_delay=30,
    queue="default",
)
def send_notification(
    self,
    user_id: int,
    title: str,
    body: str,
    notification_type: str = "INFO",
    data: dict | None = None,
    channels: list[str] | None = None,
) -> dict:
    """
    Send a notification to a user via configured channels.
    channels: list of ["push", "email", "websocket", "in_app"]
    """
    try:
        from apps.notifications.models import Notification
        notification = Notification.objects.create(
            user_id=user_id,
            title=title,
            body=body,
        )

        channels = channels or ["in_app", "push", "websocket"]
        results = {}

        if "push" in channels:
            results["push"] = _send_fcm_push(user_id, title, body, data or {})

        if "websocket" in channels:
            results["websocket"] = _send_websocket(user_id, notification)

        return {"notification_id": notification.pk, "results": results}

    except Exception as exc:
        logger.error("notification_error", extra={"user_id": user_id, "error": str(exc)}, exc_info=True)
        raise self.retry(exc=exc)


def _send_fcm_push(user_id: int, title: str, body: str, data: dict) -> str:
    try:
        from firebase_admin import messaging
        from apps.accounts.models import FCMToken

        tokens = list(FCMToken.objects.filter(user_id=user_id).values_list("registration_id", flat=True))
        if not tokens:
            return "no_tokens"

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            tokens=tokens,
        )
        response = messaging.send_each_for_multicast(message)
        return f"sent:{response.success_count},failed:{response.failure_count}"
    except Exception as exc:
        logger.warning("fcm_push_error", extra={"user_id": user_id, "error": str(exc)})
        return f"error:{exc}"


def _send_websocket(user_id: int, notification) -> str:
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer
        layer = get_channel_layer()
        if not layer:
            return "no_channel_layer"
        async_to_sync(layer.group_send)(
            f"notification_{user_id}",
            {
                "type": "notification_message",
                "data": {
                    "id": notification.pk,
                    "title": notification.title,
                    "body": notification.body,
                    "created_at": notification.created_at.isoformat(),
                },
            },
        )
        return "sent"
    except Exception as exc:
        logger.warning("ws_notification_error", extra={"user_id": user_id, "error": str(exc)})
        return f"error:{exc}"


@shared_task(name="apps.notifications.tasks.send_bulk_notification", queue="default")
def send_bulk_notification(user_ids: list[int], title: str, body: str, **kwargs) -> dict:
    for uid in user_ids:
        send_notification.delay(uid, title, body, **kwargs)
    return {"queued": len(user_ids)}
