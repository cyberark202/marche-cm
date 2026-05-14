from __future__ import annotations

import logging
from datetime import timedelta
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from .models import PaymentProvider, PayoutRetryJob, PayoutRetryStatus, TransactionStatus, WalletTransaction
from .notchpay_service import NotchPayDisbursementService


RETRYABLE_TX_KINDS = {"PAYOUT_SUPPLIER", "PAYOUT_LOCAL_SUPPLIER", "PAYOUT_LOGISTICS"}
logger = logging.getLogger(__name__)


def enqueue_payout_retry(
    *,
    tx: WalletTransaction,
    error: str,
    delay_seconds: int = 120,
    max_attempts: int = 5,
) -> PayoutRetryJob | None:
    if tx.kind not in RETRYABLE_TX_KINDS:
        return None
    next_retry_at = timezone.now() + timedelta(seconds=max(10, int(delay_seconds)))
    job, _ = PayoutRetryJob.objects.update_or_create(
        transaction=tx,
        defaults={
            "status": PayoutRetryStatus.PENDING,
            "next_retry_at": next_retry_at,
            "last_error": str(error or "")[:240],
            "max_attempts": max(1, int(max_attempts)),
            "metadata": tx.metadata or {},
        },
    )
    return job


def mark_payout_retry_success(*, tx: WalletTransaction):
    retry = PayoutRetryJob.objects.filter(transaction=tx).first()
    if not retry:
        return
    retry.status = PayoutRetryStatus.SUCCESS
    retry.locked_at = None
    retry.last_error = ""
    retry.next_retry_at = timezone.now()
    retry.save(update_fields=["status", "locked_at", "last_error", "next_retry_at", "updated_at"])


def _retry_delay_seconds(attempt: int) -> int:
    # Exponential backoff with ceiling.
    return min(3600, 60 * (2 ** max(0, attempt - 1)))


def process_due_payout_retries(*, limit: int = 100) -> dict:
    now = timezone.now()
    processed = 0
    succeeded = 0
    failed = 0
    retried = 0

    due_ids = list(
        PayoutRetryJob.objects.filter(
            status__in=[PayoutRetryStatus.PENDING, PayoutRetryStatus.RETRYING],
            next_retry_at__lte=now,
        )
        .order_by("next_retry_at")
        .values_list("id", flat=True)[: max(1, int(limit))]
    )

    for job_id in due_ids:
        with transaction.atomic():
            job = PayoutRetryJob.objects.select_for_update().select_related("transaction").filter(id=job_id).first()
            if not job:
                continue
            tx = job.transaction
            if tx.status == TransactionStatus.SUCCESS:
                job.status = PayoutRetryStatus.SUCCESS
                job.last_error = ""
                job.locked_at = None
                job.save(update_fields=["status", "last_error", "locked_at", "updated_at"])
                continue
            job.status = PayoutRetryStatus.RETRYING
            job.locked_at = now
            job.attempt_count += 1
            job.save(update_fields=["status", "locked_at", "attempt_count", "updated_at"])

        processed += 1
        metadata = tx.metadata or {}
        account_alias = str(metadata.get("account_alias") or "").strip()
        payout_amount = Decimal(str(metadata.get("payout_amount") or abs(tx.amount)))
        if not account_alias:
            with transaction.atomic():
                job = PayoutRetryJob.objects.select_for_update().get(id=job_id)
                tx = WalletTransaction.objects.select_for_update().get(id=tx.id)
                job.status = PayoutRetryStatus.FAILED
                job.last_error = "account_alias_manquant"
                job.locked_at = None
                job.next_retry_at = timezone.now()
                job.save(update_fields=["status", "last_error", "locked_at", "next_retry_at", "updated_at"])
                tx.status = TransactionStatus.FAILED
                tx.failure_reason = "account_alias_manquant"
                tx.save(update_fields=["status", "failure_reason", "updated_at"])
            failed += 1
            continue

        try:
            transfer = NotchPayDisbursementService.send_money(
                amount=abs(payout_amount),
                account_alias=account_alias,
                provider=PaymentProvider.MOBILE_MONEY,
                transaction_id=f"ORDER-PAYOUT-{tx.id}-R{job.attempt_count}",
                account_name=tx.wallet.owner.get_full_name() or tx.wallet.owner.username,
            )
        except Exception as exc:
            transfer = {"error": f"exception:{type(exc).__name__}"}

        if transfer.get("error"):
            should_rollback = False
            with transaction.atomic():
                job = PayoutRetryJob.objects.select_for_update().get(id=job_id)
                tx = WalletTransaction.objects.select_for_update().get(id=tx.id)
                if job.attempt_count >= job.max_attempts:
                    job.status = PayoutRetryStatus.FAILED
                    tx.status = TransactionStatus.FAILED
                    tx.failure_reason = str(transfer.get("error", ""))[:240]
                    tx.save(update_fields=["status", "failure_reason", "updated_at"])
                    should_rollback = True
                    failed += 1
                else:
                    job.status = PayoutRetryStatus.PENDING
                    job.next_retry_at = timezone.now() + timedelta(seconds=_retry_delay_seconds(job.attempt_count))
                    retried += 1
                job.last_error = str(transfer.get("error", ""))[:240]
                job.locked_at = None
                job.save(update_fields=["status", "next_retry_at", "last_error", "locked_at", "updated_at"])
            if should_rollback:
                try:
                    from apps.orders.services import OrderFinanceService

                    OrderFinanceService.rollback_failed_payout(
                        tx=tx,
                        reason=str(transfer.get("error", ""))[:240],
                        actor=None,
                    )
                except Exception:
                    logger.exception("Rollback payout echoue tx=%s", tx.id)
            continue

        finalize_error = ""
        job_success = True
        with transaction.atomic():
            job = PayoutRetryJob.objects.select_for_update().get(id=job_id)
            tx = WalletTransaction.objects.select_for_update().get(id=tx.id)
            tx.external_transaction_id = str(transfer.get("transaction_id") or f"ORDER-PAYOUT-{tx.id}")
            tx.metadata = {**(tx.metadata or {}), "retry_transfer": transfer}
            if transfer.get("mode") == "SIMULATED":
                tx.status = TransactionStatus.SUCCESS
                tx.cinetpay_transfered = True
                tx.reconciled_at = timezone.now()
                tx.save(
                    update_fields=[
                        "external_transaction_id",
                        "metadata",
                        "status",
                        "cinetpay_transfered",
                        "reconciled_at",
                        "updated_at",
                    ]
                )
                # Savepoint imbrique: si finalize_payout_success leve une
                # exception, on ne corrompt pas la transaction outer (job/tx
                # status restent committables). On declenche ensuite un
                # rollback compensatoire des fonds.
                try:
                    from apps.orders.services import OrderFinanceService

                    with transaction.atomic():
                        OrderFinanceService.finalize_payout_success(tx=tx, actor=None)
                except Exception as exc:
                    logger.exception("Finalisation payout retry echouee tx=%s", tx.id)
                    finalize_error = f"finalize_exception:{type(exc).__name__}"[:240]
                    tx.status = TransactionStatus.FAILED
                    tx.failure_reason = finalize_error
                    tx.save(update_fields=["status", "failure_reason", "updated_at"])
                    job_success = False
                    try:
                        from apps.orders.services import OrderFinanceService as _OFS

                        _OFS.rollback_failed_payout(tx=tx, reason=finalize_error, actor=None)
                    except Exception:
                        logger.exception("Rollback compensatoire payout retry echoue tx=%s", tx.id)
            else:
                tx.status = TransactionStatus.PENDING
                tx.save(update_fields=["external_transaction_id", "metadata", "status", "updated_at"])
            job.status = PayoutRetryStatus.SUCCESS if job_success else PayoutRetryStatus.FAILED
            job.last_error = "" if job_success else finalize_error
            job.locked_at = None
            job.next_retry_at = timezone.now()
            job.save(update_fields=["status", "last_error", "locked_at", "next_retry_at", "updated_at"])
        if job_success:
            succeeded += 1
        else:
            failed += 1

    return {
        "processed": processed,
        "succeeded": succeeded,
        "failed": failed,
        "rescheduled": retried,
    }
