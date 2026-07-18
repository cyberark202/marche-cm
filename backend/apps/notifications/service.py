import logging

from .models import (
    Notification,
    NotificationCategory,
    NotificationPreference,
    NotificationPriority,
)
from .realtime import broadcast_user_event

logger = logging.getLogger(__name__)


def create_realtime_notification(
    *,
    user,
    title: str,
    body: str,
    payload: dict | None = None,
    category: str = NotificationCategory.SYSTEM,
    priority: str = NotificationPriority.NORMAL,
) -> Notification | None:
    """Crée la notification in-app + broadcast WS + push FCM (doc 10).

    Préférences : PROMOTIONS est totalement supprimable par l'utilisateur ;
    le push est désactivable sauf pour SECURITY et priorité CRITICAL, jamais
    supprimées (obligation de sécurité).
    """
    prefs = NotificationPreference.objects.filter(user=user).first()
    is_forced = category == NotificationCategory.SECURITY or priority == NotificationPriority.CRITICAL
    if prefs and not prefs.promotions_enabled and category == NotificationCategory.PROMOTIONS and not is_forced:
        return None

    notification = Notification.objects.create(
        user=user, title=title, body=body, category=category, priority=priority
    )
    event_payload = {
        "notification_id": notification.id,
        "title": title,
        "body": body,
        "category": category,
        "priority": priority,
        "created_at": notification.created_at.isoformat(),
        **(payload or {}),
    }
    broadcast_user_event(
        user_id=user.id,
        topic="notifications",
        event_type="notification_created",
        payload=event_payload,
    )
    push_allowed = is_forced or not prefs or prefs.push_enabled
    if push_allowed:
        # Best-effort FCM push for users whose app is closed or backgrounded.
        try:
            from .push_service import send_push_notification
            send_push_notification(user=user, title=title, body=body, data=event_payload)
        except Exception:
            # Never let push failure break the in-app notification path.
            logger.warning("fcm_push_failed user=%d", user.id, exc_info=True)

    return notification
