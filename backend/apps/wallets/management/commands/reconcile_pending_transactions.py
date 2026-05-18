"""
Management command: reconcile_pending_transactions — Phase 3.

Finds WalletTransactions stuck in PENDING beyond a configurable age
threshold, queries NotchPay for their current status, and resolves
them (SUCCESS/FAILED) or marks them for manual review.

Also cleans up expired IdempotencyRecord rows.

Safe to run repeatedly — idempotent by design.

Usage:
    python manage.py reconcile_pending_transactions
    python manage.py reconcile_pending_transactions --dry-run
    python manage.py reconcile_pending_transactions --max-age-minutes 60
    python manage.py reconcile_pending_transactions --kind TOPUP
    python manage.py reconcile_pending_transactions --limit 50

Schedule: run every 5–10 minutes via cron, systemd timer, or APScheduler.
"""

import logging
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

logger = logging.getLogger("wallets.reconcile")


class Command(BaseCommand):
    help = "Reconcile PENDING wallet transactions stuck beyond the age threshold."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            default=False,
            help="Print what would be done without changing any data.",
        )
        parser.add_argument(
            "--max-age-minutes",
            type=int,
            default=15,
            help="Transactions older than this many minutes are considered stale (default: 15).",
        )
        parser.add_argument(
            "--kind",
            type=str,
            default="",
            help="Restrict to a specific kind (TOPUP|WITHDRAWAL). Empty = all.",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=100,
            help="Max transactions to process per run (default: 100).",
        )
        parser.add_argument(
            "--notchpay-verify",
            action="store_true",
            default=True,
            help="Query NotchPay API for each transaction status (default: True).",
        )

    def handle(self, *args, **options):
        dry_run: bool = options["dry_run"]
        max_age: int = options["max_age_minutes"]
        kind_filter: str = (options["kind"] or "").strip().upper()
        limit: int = options["limit"]
        use_notchpay: bool = options["notchpay_verify"]

        cutoff = timezone.now() - timedelta(minutes=max_age)

        from apps.wallets.models import TransactionStatus, WalletTransaction

        qs = WalletTransaction.objects.filter(
            status=TransactionStatus.PENDING,
            created_at__lt=cutoff,
        ).select_related("wallet__owner").order_by("created_at")

        if kind_filter:
            qs = qs.filter(kind=kind_filter)

        stale_txs = list(qs[:limit])
        total = len(stale_txs)

        if total == 0:
            self.stdout.write(self.style.SUCCESS("No stale PENDING transactions found."))
            self._cleanup_idempotency(dry_run)
            return

        self.stdout.write(f"Found {total} stale PENDING transaction(s) (age > {max_age}m).")

        stats = {"resolved_success": 0, "resolved_failed": 0, "skipped": 0, "errors": 0}

        for tx in stale_txs:
            try:
                self._process_transaction(tx, dry_run=dry_run, use_notchpay=use_notchpay, stats=stats)
            except Exception as exc:
                logger.exception("reconcile_error tx_id=%s err=%s", tx.external_transaction_id, exc)
                stats["errors"] += 1

        self._cleanup_idempotency(dry_run)

        prefix = "[DRY RUN] " if dry_run else ""
        self.stdout.write(
            self.style.SUCCESS(
                f"{prefix}Reconciliation complete: "
                f"resolved_success={stats['resolved_success']} "
                f"resolved_failed={stats['resolved_failed']} "
                f"skipped={stats['skipped']} "
                f"errors={stats['errors']}"
            )
        )

    def _process_transaction(self, tx, *, dry_run: bool, use_notchpay: bool, stats: dict) -> None:
        from apps.wallets.models import TransactionStatus
        from apps.wallets.notchpay_checkout_service import NotchPayCheckoutService

        tx_ref = tx.external_transaction_id or ""
        age_minutes = int((timezone.now() - tx.created_at).total_seconds() / 60)

        self.stdout.write(
            f"  TX {tx_ref} kind={tx.kind} age={age_minutes}m wallet={tx.wallet.owner.username}"
        )

        # --- Try to resolve via NotchPay API query ---
        notchpay_status: str | None = None
        if use_notchpay and tx.kind in {"TOPUP"} and tx_ref:
            # For topup: the external_transaction_id is the NotchPay reference.
            # For WITHDRAWAL: the provider-side tx is prefixed WITHDRAW-{id},
            # which NotchPay uses as the disburse reference — queryable via
            # NotchPayDisbursementService (not implemented here to keep this
            # command read-only; the disburse webhook is the authoritative path).
            try:
                result = NotchPayCheckoutService.confirm_invoice(token=tx_ref)
                raw_status = str(result.get("status") or "").lower()
                if raw_status in {"complete", "completed", "paid", "success"}:
                    notchpay_status = "SUCCESS"
                elif raw_status in {"failed", "canceled", "cancelled", "expired"}:
                    notchpay_status = "FAILED"
                else:
                    notchpay_status = None  # Still pending or unknown
                self.stdout.write(
                    f"    NotchPay status for {tx_ref}: raw={raw_status!r} → resolved={notchpay_status}"
                )
            except Exception as exc:
                logger.warning("notchpay_query_failed tx=%s err=%s", tx_ref, exc)
                notchpay_status = None

        if notchpay_status == "SUCCESS":
            if dry_run:
                self.stdout.write(self.style.SUCCESS(f"    [DRY RUN] Would mark SUCCESS: {tx_ref}"))
                stats["resolved_success"] += 1
            else:
                self._mark_success(tx)
                stats["resolved_success"] += 1
                self.stdout.write(self.style.SUCCESS(f"    Marked SUCCESS: {tx_ref}"))
        elif notchpay_status == "FAILED":
            if dry_run:
                self.stdout.write(self.style.WARNING(f"    [DRY RUN] Would mark FAILED: {tx_ref}"))
                stats["resolved_failed"] += 1
            else:
                self._mark_failed(tx, reason="reconciliation: provider reported failed/expired")
                stats["resolved_failed"] += 1
                self.stdout.write(self.style.WARNING(f"    Marked FAILED: {tx_ref}"))
        else:
            # Cannot determine status — leave as PENDING for now.
            # Very old transactions (> 2 hours) are flagged in audit log.
            if age_minutes > 120 and not dry_run:
                from apps.accounts.security import write_audit_log
                write_audit_log(
                    actor=None,
                    action="Transaction PENDING depuis plus de 2 heures",
                    action_key="wallet.reconcile.stale",
                    metadata={
                        "transaction_id": tx_ref,
                        "kind": tx.kind,
                        "age_minutes": age_minutes,
                        "owner": tx.wallet.owner.username,
                    },
                )
            stats["skipped"] += 1
            self.stdout.write(f"    Skipped (status unknown): {tx_ref}")

    def _mark_success(self, tx) -> None:
        from apps.wallets.views import WalletViewSet
        # Instantiate with minimal setup just to reuse _mark_transaction_success.
        vs = WalletViewSet()
        vs._mark_transaction_success(tx=tx, payload={"source": "reconciliation_command"}, mark_payout=None)

    def _mark_failed(self, tx, *, reason: str) -> None:
        from apps.wallets.views import WalletViewSet
        vs = WalletViewSet()
        vs._mark_transaction_failed(tx=tx, reason=reason)

    def _cleanup_idempotency(self, dry_run: bool) -> None:
        from apps.wallets.idempotency_service import IdempotencyService
        if dry_run:
            from apps.wallets.models import IdempotencyRecord
            from django.utils import timezone
            expired = IdempotencyRecord.objects.filter(expires_at__lt=timezone.now()).count()
            self.stdout.write(f"[DRY RUN] Would delete {expired} expired idempotency record(s).")
        else:
            deleted = IdempotencyService.cleanup_expired()
            if deleted:
                self.stdout.write(f"Cleaned up {deleted} expired idempotency record(s).")
