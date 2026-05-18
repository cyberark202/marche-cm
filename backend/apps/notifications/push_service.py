"""FCM push notification delivery.

Requires one of:
  FIREBASE_SERVICE_ACCOUNT_KEY      — JSON string of the service account key
  FIREBASE_SERVICE_ACCOUNT_KEY_PATH — path to the service account JSON file

Both are set in the Render/environment dashboard, never committed.
"""

import json
import logging
import os

logger = logging.getLogger(__name__)


def send_push_notification(*, user, title: str, body: str, data: dict | None = None) -> int:
    """Send FCM push to all registered devices for *user*.

    Returns the number of tokens successfully delivered.
    Silently drops delivery failures so callers are never blocked.
    """
    from apps.accounts.models import FCMToken

    tokens = list(FCMToken.objects.filter(user=user).values_list("registration_id", flat=True))
    if not tokens:
        return 0

    try:
        import firebase_admin
        from firebase_admin import messaging

        if not firebase_admin._apps:
            _init_firebase()

        str_data = {k: str(v) for k, v in (data or {}).items()}

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data=str_data,
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", badge=1)
                )
            ),
        )
        result = messaging.send_each_for_multicast(message)

        # Prune tokens the FCM service says are no longer valid.
        if result.failure_count > 0:
            invalid = [
                tokens[i]
                for i, r in enumerate(result.responses)
                if not r.success
                and r.exception
                and "registration-token-not-registered" in str(r.exception).lower()
            ]
            if invalid:
                FCMToken.objects.filter(registration_id__in=invalid).delete()
                logger.info("Pruned %d stale FCM tokens for user %s", len(invalid), user.id)

        return result.success_count
    except Exception:
        logger.exception("FCM push failed for user %s", user.id)
        return 0


def _init_firebase() -> None:
    import firebase_admin
    from firebase_admin import credentials

    key_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_KEY", "").strip()
    if key_json:
        cred = credentials.Certificate(json.loads(key_json))
    else:
        key_path = os.environ.get("FIREBASE_SERVICE_ACCOUNT_KEY_PATH", "").strip()
        if not key_path:
            raise RuntimeError(
                "Set FIREBASE_SERVICE_ACCOUNT_KEY or FIREBASE_SERVICE_ACCOUNT_KEY_PATH"
            )
        cred = credentials.Certificate(key_path)

    firebase_admin.initialize_app(cred)
