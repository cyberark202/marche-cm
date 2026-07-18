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


@shared_task(
    name="apps.wallets.tasks.check_dormant_balances",
    queue="financial",
)
def check_dormant_balances(limit: int = 500) -> dict:
    """Solde dormant > seuil (doc 05) : avertit, puis pénalise si activé.

    Cycle par wallet dormant (solde disponible > seuil, aucun retrait ni achat
    engagé depuis N jours) :
      1er passage  → notification d'avertissement (dormancy_notified_at posé) ;
      passages suivants, si l'avertissement date de plus de N jours ET que la
      pénalité est activée (désactivée par défaut tant que la base légale
      n'est pas validée) → prélèvement historisé + notification.
    Toute activité qualifiante remet le compteur à zéro.
    """
    from datetime import timedelta
    from decimal import Decimal

    from django.utils import timezone

    from apps.appconfig.models import get_platform_setting
    from apps.notifications.service import create_realtime_notification
    from apps.accounts.security import write_audit_log
    from .models import LedgerDirection, LedgerEntryType, Wallet
    from .services import WalletAccountingService, quantize_money

    threshold = Decimal(str(get_platform_setting("wallet.dormancy_threshold")))
    delay_days = int(get_platform_setting("wallet.dormancy_delay_days"))
    penalty_enabled = bool(get_platform_setting("wallet.dormancy_enabled"))
    penalty_percent = Decimal(str(get_platform_setting("wallet.dormancy_penalty_percent")))

    now = timezone.now()
    cutoff = now - timedelta(days=delay_days)
    notified = penalized = cleared = 0

    candidates = Wallet.objects.filter(available_balance__gt=threshold).select_related("owner")[: max(1, limit)]
    for wallet in candidates:
        has_activity = wallet.ledger_entries.filter(
            created_at__gte=cutoff,
            entry_type__in=[LedgerEntryType.WITHDRAWAL, LedgerEntryType.ESCROW_TRANSFER],
        ).exists()
        if has_activity:
            if wallet.dormancy_notified_at is not None:
                wallet.dormancy_notified_at = None
                wallet.save(update_fields=["dormancy_notified_at", "updated_at"])
                cleared += 1
            continue

        if wallet.dormancy_notified_at is None:
            try:
                create_realtime_notification(
                    user=wallet.owner,
                    title="Solde important inactif",
                    body=(
                        f"Votre solde depasse {threshold:,.0f} FCFA sans operation depuis {delay_days} jours. "
                        "Pensez a effectuer un achat ou un retrait."
                    ),
                    payload={"topic": "wallet", "kind": "dormancy_warning"},
                )
            except Exception:
                logger.exception("dormancy_notify_failed wallet=%s", wallet.id)
            wallet.dormancy_notified_at = now
            wallet.save(update_fields=["dormancy_notified_at", "updated_at"])
            notified += 1
            continue

        if penalty_enabled and penalty_percent > 0 and wallet.dormancy_notified_at <= cutoff:
            penalty = quantize_money(wallet.available_balance * penalty_percent / Decimal("100"))
            if penalty <= 0:
                continue
            try:
                WalletAccountingService.mutate_wallet(
                    wallet=wallet,
                    amount=penalty,
                    entry_type=LedgerEntryType.PENALTY,
                    direction=LedgerDirection.DEBIT,
                    available_delta=-penalty,
                    reference=f"dormancy-penalty:{wallet.id}:{now.date().isoformat()}",
                    idempotency_key=f"dormancy:{wallet.id}:{now.date().isoformat()}",
                    metadata={"threshold": str(threshold), "percent": str(penalty_percent)},
                )
                write_audit_log(
                    actor=None,
                    action="Penalite solde dormant appliquee",
                    action_key="wallet.dormancy.penalty",
                    metadata={"wallet_id": wallet.id, "amount": str(penalty)},
                )
                create_realtime_notification(
                    user=wallet.owner,
                    title="Penalite de solde inactif",
                    body=f"Une penalite de {penalty:,.0f} FCFA a ete appliquee sur votre solde inactif.",
                    payload={"topic": "wallet", "kind": "dormancy_penalty"},
                )
            except Exception:
                logger.exception("dormancy_penalty_failed wallet=%s", wallet.id)
                continue
            wallet.dormancy_notified_at = now
            wallet.save(update_fields=["dormancy_notified_at", "updated_at"])
            penalized += 1

    result = {"notified": notified, "penalized": penalized, "cleared": cleared}
    logger.info("dormancy_check_done", extra=result)
    return result
