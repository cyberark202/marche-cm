"""Tâches planifiées logistique — expiration des offres de mission (doc 07).

Une offre non répondue dans le délai imparti expire et la mission cascade
automatiquement au livreur suivant le plus proche.
"""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.logistics.tasks.expire_dispatch_offers",
    queue="default",
)
def expire_dispatch_offers(limit: int = 500) -> dict:
    from django.db import transaction
    from django.utils import timezone

    from apps.notifications.service import create_realtime_notification
    from .dispatch import offer_to_next_driver
    from .models import DispatchOffer, DispatchOfferStatus

    now = timezone.now()
    expired = advanced = 0
    due = (
        DispatchOffer.objects.filter(status=DispatchOfferStatus.PENDING, expires_at__lt=now)
        .select_related("shipment", "driver")[: max(1, limit)]
    )
    for offer in due:
        with transaction.atomic():
            locked = DispatchOffer.objects.select_for_update().get(id=offer.id)
            if locked.status != DispatchOfferStatus.PENDING:
                continue
            locked.status = DispatchOfferStatus.EXPIRED
            locked.responded_at = now
            locked.save(update_fields=["status", "responded_at"])
        expired += 1
        try:
            create_realtime_notification(
                user=offer.driver,
                title="Mission expiree",
                body=f"L'offre pour la mission #{offer.shipment_id} a expire.",
                payload={"shipment_id": offer.shipment_id, "topic": "logistics"},
            )
        except Exception:
            logger.exception("dispatch_expiry_notify_failed offer=%s", offer.id)
        if offer.shipment.transit_agent_id is None:
            try:
                if offer_to_next_driver(offer.shipment) is not None:
                    advanced += 1
            except Exception:
                logger.exception("dispatch_advance_failed shipment=%s", offer.shipment_id)

    result = {"expired": expired, "advanced": advanced}
    logger.info("dispatch_expiry_done", extra=result)
    return result
