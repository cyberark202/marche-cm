from __future__ import annotations

from decimal import Decimal

from django.conf import settings
from django.db.models import Sum
from django.utils import timezone

from apps.accounts.security import write_audit_log
from apps.orders.models import EscrowLifecycleStatus, OrderEscrow

from .models import (
    DailyReconciliationReport,
    LedgerEntryType,
    PayoutRetryStatus,
    ReconciliationStatus,
    Wallet,
    WalletLedgerEntry,
    WalletTransaction,
)


def run_daily_reconciliation(*, provider_real_balance: Decimal | None = None, provider: str = "NOTCHPAY"):
    today = timezone.localdate()

    wallet_totals = Wallet.objects.aggregate(
        available=Sum("available_balance"),
        locked=Sum("locked_balance"),
        pending=Sum("pending_balance"),
    )
    wallets_available = Decimal(wallet_totals.get("available") or 0)
    wallets_locked = Decimal(wallet_totals.get("locked") or 0)
    wallets_pending = Decimal(wallet_totals.get("pending") or 0)

    escrow_locked_total = (
        OrderEscrow.objects.filter(
            status__in=[
                EscrowLifecycleStatus.LOCKED,
                EscrowLifecycleStatus.READY,
                EscrowLifecycleStatus.PAYOUT_PENDING,
                EscrowLifecycleStatus.FROZEN,
            ]
        ).aggregate(value=Sum("amount"))["value"]
        or Decimal("0")
    )
    commission_total = (
        WalletLedgerEntry.objects.filter(entry_type=LedgerEntryType.COMMISSION).aggregate(value=Sum("amount"))["value"]
        or Decimal("0")
    )

    topup_total = (
        WalletTransaction.objects.filter(kind="TOPUP", status="SUCCESS").aggregate(value=Sum("amount"))["value"] or Decimal("0")
    )
    payout_total = (
        WalletTransaction.objects.filter(kind__startswith="PAYOUT_", status="SUCCESS").aggregate(value=Sum("amount"))["value"]
        or Decimal("0")
    )
    provider_net_flow = Decimal(topup_total) - abs(Decimal(payout_total))

    unresolved_payout_count = (
        WalletTransaction.objects.filter(kind__startswith="PAYOUT_", status__in=["PENDING", "FAILED"]).count()
        + WalletTransaction.objects.filter(
            payout_retry__status__in=[PayoutRetryStatus.PENDING, PayoutRetryStatus.RETRYING]
        ).count()
    )

    internal_liability = wallets_available + wallets_locked + wallets_pending
    expected_liability = provider_real_balance if provider_real_balance is not None else provider_net_flow
    variance = (internal_liability - expected_liability).quantize(Decimal("0.01"))
    require_real_balance = bool(getattr(settings, "RECONCILIATION_REQUIRE_PROVIDER_BALANCE", True))
    missing_real_balance = provider_real_balance is None and require_real_balance
    if missing_real_balance:
        status = ReconciliationStatus.FAILED
    elif variance == Decimal("0.00") and unresolved_payout_count == 0:
        status = ReconciliationStatus.OK
    else:
        status = ReconciliationStatus.ALERT

    report, _ = DailyReconciliationReport.objects.update_or_create(
        report_date=today,
        defaults={
            "provider": provider,
            "provider_reported_balance": provider_real_balance,
            "provider_net_flow": provider_net_flow,
            "wallets_available_total": wallets_available,
            "wallets_locked_total": wallets_locked,
            "wallets_pending_total": wallets_pending,
            "escrow_locked_total": escrow_locked_total,
            "platform_commission_total": commission_total,
            "unresolved_payout_count": unresolved_payout_count,
            "variance": variance,
            "status": status,
            "details": {
                "strict_provider_balance_mode": require_real_balance,
                "missing_provider_real_balance": missing_real_balance,
                "topup_success_total": str(topup_total),
                "payout_success_total": str(payout_total),
                "wallet_count": Wallet.objects.count(),
                "escrow_count": OrderEscrow.objects.count(),
                "pending_tx_count": WalletTransaction.objects.filter(status="PENDING").count(),
            },
        },
    )

    write_audit_log(
        actor=None,
        action="Daily reconciliation generated",
        action_key="wallet.reconcile.daily",
        metadata={
            "report_date": str(report.report_date),
            "status": report.status,
            "variance": str(report.variance),
            "unresolved_payout_count": report.unresolved_payout_count,
            "provider_reported_balance": str(report.provider_reported_balance or ""),
        },
    )
    return report

