import logging
from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.escrow.tasks.process_auto_releases",
    queue="financial",
    max_retries=2,
)
def process_auto_releases() -> dict:
    """Auto-release loop for matured EscrowHold rows.

    Audit ref: [NEW-003] wrapped in a distributed lock so two Celery beat
    replicas (HA / rolling deploy) cannot run the loop concurrently. The
    inner select_for_update on each hold already prevents corruption, but
    duplicate execution doubles DB load and pollutes audit logs.
    """
    from core.locks import acquire_lock, LockAcquisitionError
    from .services import escrow_service

    try:
        # retry_count=0 — we want INSTANT skip if another beat is running,
        # not queuing. Next tick (every 300s) will catch what we miss.
        with acquire_lock("escrow:auto_release_beat", ttl_seconds=290, retry_count=0):
            count = escrow_service.process_auto_releases()
            logger.info("escrow_auto_releases", extra={"count": count})
            return {"released": count}
    except LockAcquisitionError:
        logger.info("escrow_auto_releases.skipped reason=another_beat_running")
        return {"released": 0, "skipped": "another_beat_running"}
