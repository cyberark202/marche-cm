import logging
from celery import shared_task
from django.utils import timezone

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.disputes.tasks.check_sla_breaches",
    queue="default",
)
def check_sla_breaches() -> dict:
    from .models import DisputeCase, DisputeState
    now = timezone.now()
    breached = DisputeCase.objects.filter(
        state__in=[DisputeState.OPEN, DisputeState.UNDER_REVIEW, DisputeState.AWAITING_EVIDENCE],
        sla_due_at__lt=now,
        sla_breached=False,
    )
    count = 0
    for case in breached:
        case.sla_breached = True
        case.save(update_fields=["sla_breached", "updated_at"])
        count += 1
    logger.info("dispute_sla_breaches", extra={"count": count})
    return {"breached": count}
