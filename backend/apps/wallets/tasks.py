"""
Celery tasks financières — file `financial` (concurrence 1, sérialisée).

Audit ref: [INFRA-P0-004] le beat_schedule (celery_app.py) référençait
apps.wallets.tasks.{retry_failed_payouts, run_daily_reconciliation,
cleanup_expired_idempotency} mais ce module n'existait pas : le worker
rejetait chaque tick en "Received unregistered task". Les implémentations
vivaient déjà dans payout_retry / reconciliation / idempotency_service
(utilisées par les management commands) — ces tâches ne font que les exposer.
"""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.wallets.tasks.retry_failed_payouts",
    bind=True,
    max_retries=2,
    default_retry_delay=60,
    queue="financial",
)
def retry_failed_payouts(self, limit: int = 200) -> dict:
    from .payout_retry import process_due_payout_retries

    try:
        result = process_due_payout_retries(limit=limit)
        logger.info("payout_retries_processed", extra={"result": str(result)})
        return result
    except Exception as exc:
        logger.error("payout_retries_error", extra={"error": str(exc)}, exc_info=True)
        raise self.retry(exc=exc)


@shared_task(
    name="apps.wallets.tasks.run_daily_reconciliation",
    bind=True,
    max_retries=1,
    default_retry_delay=300,
    queue="financial",
)
def run_daily_reconciliation(self) -> dict:
    from .reconciliation import run_daily_reconciliation as _run

    try:
        report = _run()
        summary = getattr(report, "summary", None) or str(report)
        logger.info("daily_reconciliation_done", extra={"summary": str(summary)[:500]})
        return {"status": "ok"}
    except Exception as exc:
        logger.error("daily_reconciliation_error", extra={"error": str(exc)}, exc_info=True)
        raise self.retry(exc=exc)


@shared_task(
    name="apps.wallets.tasks.cleanup_expired_idempotency",
    queue="default",
)
def cleanup_expired_idempotency() -> dict:
    from .idempotency_service import IdempotencyService

    deleted = IdempotencyService.cleanup_expired()
    logger.info("idempotency_cleanup", extra={"deleted": deleted})
    return {"deleted": deleted}
