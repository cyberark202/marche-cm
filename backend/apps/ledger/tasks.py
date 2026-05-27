"""
Wallet ↔ Ledger reconciliation tasks.

Audit ref: [FIN-001 follow-up] — the wallet (operational source) and the
double-entry ledger (auditable source) should converge. This periodic job
walks every user, compares the two ledgers, and alerts on drift.

Invariant checked:
    wallet.available_balance ==
    latest LedgerEntry.running_balance for that user's USER_WALLET account

Pending/locked balances are NOT mirrored to the ledger (escrow movements
shift them between buckets without crossing the wallet asset boundary).
The available bucket is the cash position that should match the asset
account 1:1 within the money-quantum tolerance (0.01 XAF).

Drift > tolerance triggers a critical security log entry. A FinOps alert
hook can be wired via settings.FINOPS_ALERT_WEBHOOK_URL.
"""
from __future__ import annotations

import logging
from decimal import Decimal

from celery import shared_task
from django.contrib.auth import get_user_model

from apps.wallets.models import Wallet
from apps.wallets.services import quantize_money
from .models import AccountSubType, LedgerAccount, LedgerEntry

logger = logging.getLogger(__name__)
security_logger = logging.getLogger("security")

DRIFT_TOLERANCE = Decimal("0.01")
User = get_user_model()


@shared_task(
    name="apps.ledger.tasks.reconcile_wallet_ledger",
    queue="financial",
    max_retries=0,
)
def reconcile_wallet_ledger(*, sample_limit: int | None = None) -> dict:
    """Compare wallet.available_balance with ledger USER_WALLET running balance.

    Returns a summary dict — `drift_count` non-zero is a critical signal.
    Operators should investigate every drifted user immediately.
    """
    wallets_qs = Wallet.objects.select_related("owner").only(
        "id", "owner_id", "available_balance",
    )
    if sample_limit:
        wallets_qs = wallets_qs[:sample_limit]

    checked = 0
    drifts: list[dict] = []
    missing_ledger_account = 0
    missing_ledger_entry = 0

    for wallet in wallets_qs.iterator(chunk_size=200):
        checked += 1
        try:
            account = LedgerAccount.objects.only("id").get(
                sub_type=AccountSubType.USER_WALLET, owner_id=wallet.owner_id,
            )
        except LedgerAccount.DoesNotExist:
            missing_ledger_account += 1
            continue

        last_entry = (
            LedgerEntry.objects.filter(account=account)
            .order_by("-created_at", "-id")
            .only("running_balance")
            .first()
        )
        if last_entry is None:
            # No ledger activity yet — only acceptable when wallet is empty.
            if quantize_money(wallet.available_balance) != Decimal("0.00"):
                missing_ledger_entry += 1
                drifts.append({
                    "user_id": wallet.owner_id,
                    "wallet_available": str(wallet.available_balance),
                    "ledger_running_balance": "0.00",
                    "delta": str(wallet.available_balance),
                    "reason": "no_ledger_entry",
                })
            continue

        wallet_amount = quantize_money(wallet.available_balance)
        ledger_amount = quantize_money(last_entry.running_balance)
        delta = (wallet_amount - ledger_amount).copy_abs()
        if delta > DRIFT_TOLERANCE:
            drifts.append({
                "user_id": wallet.owner_id,
                "wallet_available": str(wallet_amount),
                "ledger_running_balance": str(ledger_amount),
                "delta": str(delta),
                "reason": "drift",
            })

    summary = {
        "wallets_checked": checked,
        "drift_count": len(drifts),
        "missing_ledger_account": missing_ledger_account,
        "missing_ledger_entry": missing_ledger_entry,
    }
    if drifts:
        # Critical — every drift is a potential lost or phantom XAF.
        security_logger.error(
            "wallet_ledger_drift_detected",
            extra={"summary": summary, "first_offenders": drifts[:10]},
        )
    else:
        logger.info("wallet_ledger_reconciled", extra=summary)
    return summary
