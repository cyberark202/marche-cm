"""Tâches planifiées conformité — expiration des documents KYC (doc 06).

Un document d'identité (CNI, passeport, permis) a une validité limitée :
  - à 30 jours de l'échéance, l'utilisateur est averti (une seule fois) ;
  - à l'échéance, l'application KYC passe EXPIRED et le compte est rétrogradé
    (is_verified=False, kyc_level=0) : les fonctionnalités sensibles se ferment
    jusqu'à mise à jour du dossier.
"""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)

_IDENTITY_DOC_TYPES = ("NATIONAL_ID", "PASSPORT", "DRIVERS_LICENSE")
_WARNING_WINDOW_DAYS = 30


@shared_task(name="apps.compliance.tasks.check_kyc_document_expiry", queue="default")
def check_kyc_document_expiry(limit: int = 1000) -> dict:
    from datetime import timedelta

    from django.utils import timezone

    from apps.notifications.models import NotificationCategory, NotificationPriority
    from apps.notifications.service import create_realtime_notification
    from apps.accounts.security import write_audit_log
    from .models import KYCDocument, KYCStatus

    today = timezone.now().date()
    warn_before = today + timedelta(days=_WARNING_WINDOW_DAYS)
    warned = expired = 0

    upcoming = (
        KYCDocument.objects.filter(
            document_type__in=_IDENTITY_DOC_TYPES,
            expiry_date__isnull=False,
            expiry_date__gt=today,
            expiry_date__lte=warn_before,
            expiry_warning_sent_at__isnull=True,
            application__status=KYCStatus.APPROVED,
        )
        .select_related("application__user")[: max(1, limit)]
    )
    for doc in upcoming:
        user = doc.application.user
        try:
            create_realtime_notification(
                user=user,
                title="Document d'identite bientot expire",
                body=(
                    f"Votre {doc.get_document_type_display()} expire le {doc.expiry_date.isoformat()}. "
                    "Mettez a jour votre dossier KYC pour conserver l'acces complet."
                ),
                payload={"topic": "kyc", "kind": "expiry_warning"},
                category=NotificationCategory.KYC,
            )
        except Exception:
            logger.exception("kyc_expiry_warn_notify_failed doc=%s", doc.id)
        doc.expiry_warning_sent_at = timezone.now()
        doc.save(update_fields=["expiry_warning_sent_at"])
        warned += 1

    due = (
        KYCDocument.objects.filter(
            document_type__in=_IDENTITY_DOC_TYPES,
            expiry_date__isnull=False,
            expiry_date__lt=today,
            application__status=KYCStatus.APPROVED,
        )
        .select_related("application__user")[: max(1, limit)]
    )
    for doc in due:
        application = doc.application
        user = application.user
        application.status = KYCStatus.EXPIRED
        application.save(update_fields=["status", "updated_at"])
        if getattr(user, "is_verified", False) or int(getattr(user, "kyc_level", 0) or 0) > 0:
            user.is_verified = False
            user.kyc_level = 0
            user.save(update_fields=["is_verified", "kyc_level"])
        try:
            create_realtime_notification(
                user=user,
                title="Document d'identite expire",
                body=(
                    "Votre document d'identite a expire. Certaines fonctionnalites sont suspendues "
                    "jusqu'a la soumission d'un nouveau document."
                ),
                payload={"topic": "kyc", "kind": "expired"},
                category=NotificationCategory.KYC,
                priority=NotificationPriority.HIGH,
            )
        except Exception:
            logger.exception("kyc_expired_notify_failed doc=%s", doc.id)
        write_audit_log(
            actor=None,
            action="KYC expire - compte retrograde",
            action_key="compliance.kyc.expired",
            metadata={"user_id": user.id, "application_id": str(application.id)},
        )
        expired += 1

    result = {"warned": warned, "expired": expired}
    logger.info("kyc_expiry_check_done", extra=result)
    return result
