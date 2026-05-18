from __future__ import annotations

import json
import logging
import urllib.request

from django.conf import settings
from django.core.mail import send_mail
from django.db.models import Q

from apps.accounts.models import User, UserRole
from apps.accounts.security import write_audit_log
from apps.notifications.service import create_realtime_notification


logger = logging.getLogger(__name__)


def send_finops_alert(*, title: str, body: str, metadata: dict | None = None) -> dict:
    metadata = metadata or {}
    delivered = {"email": False, "webhook": False, "in_app_admin_count": 0}

    recipients = list(getattr(settings, "FINOPS_ALERT_EMAILS", []) or [])
    if recipients:
        try:
            send_mail(
                subject=title,
                message=body,
                from_email=getattr(settings, "DEFAULT_FROM_EMAIL", "no-reply@marche-cm.local"),
                recipient_list=recipients,
                fail_silently=False,
            )
            delivered["email"] = True
        except Exception:
            logger.exception("Echec envoi email alerte finops.")

    webhook_url = str(getattr(settings, "FINOPS_ALERT_WEBHOOK_URL", "") or "").strip()
    if webhook_url:
        payload = {"text": f"{title}\n{body}", "metadata": metadata}
        encoded = json.dumps(payload).encode("utf-8")
        timeout = max(3, int(getattr(settings, "FINOPS_ALERT_WEBHOOK_TIMEOUT_SECONDS", 10)))
        try:
            req = urllib.request.Request(
                webhook_url,
                data=encoded,
                headers={"Content-Type": "application/json", "Accept": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=timeout):
                pass
            delivered["webhook"] = True
        except Exception:
            logger.exception("Echec webhook alerte finops.")

    admins = (
        User.objects.filter(is_active=True)
        .filter(Q(role=UserRole.GENERAL_ADMIN) | Q(is_superuser=True))
        .distinct()[:50]
    )
    admin_notified = 0
    for admin in admins:
        try:
            create_realtime_notification(
                user=admin,
                title=title,
                body=body[:400],
                payload={"domain": "finops", **metadata},
            )
            admin_notified += 1
        except Exception:
            continue
    delivered["in_app_admin_count"] = admin_notified

    logger.warning("FINOPS ALERT | %s | %s | metadata=%s", title, body, metadata)
    write_audit_log(
        actor=None,
        action="FinOps alert dispatched",
        action_key="wallet.finops.alert",
        metadata={"title": title, "body": body, "delivery": delivered, **metadata},
    )
    return delivered
