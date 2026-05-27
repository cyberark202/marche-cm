"""
Celery tasks for the event outbox processor.
"""
import logging
from celery import shared_task
from .dispatcher import dispatch_pending

logger = logging.getLogger(__name__)


@shared_task(
    name="core.events.tasks.process_outbox_events",
    bind=True,
    max_retries=3,
    default_retry_delay=10,
    queue="outbox",
)
def process_outbox_events(self, batch_size: int = 100) -> dict:
    try:
        processed = dispatch_pending(batch_size=batch_size)
        return {"processed": processed}
    except Exception as exc:
        logger.error("outbox_processor_error", extra={"error": str(exc)}, exc_info=True)
        raise self.retry(exc=exc)
