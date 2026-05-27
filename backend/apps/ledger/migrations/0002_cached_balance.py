"""
Materialise the latest running_balance on LedgerAccount.

Audit ref: V11.3 — `_get_account_balance` previously hit the LedgerEntry
table on every post via ``ORDER BY -created_at LIMIT 1``. On hot platform
accounts (PROVIDER_FLOAT, PLATFORM_REVENUE) that is O(log n) on every
financial mutation — the architecture audit flagged it as the main scale
bottleneck. The cached_balance + cached_balance_updated_at columns let us
fetch the current balance directly from the locked row.
"""
from decimal import Decimal

from django.db import migrations, models


def backfill_cached_balance(apps, schema_editor):
    """Copy each account's latest LedgerEntry.running_balance into the new column."""
    LedgerAccount = apps.get_model("ledger", "LedgerAccount")
    LedgerEntry = apps.get_model("ledger", "LedgerEntry")
    from django.utils import timezone

    now = timezone.now()
    BATCH = 200
    accounts = LedgerAccount.objects.all().only("id")
    for offset in range(0, accounts.count(), BATCH):
        chunk = list(accounts[offset : offset + BATCH])
        for account in chunk:
            last = (
                LedgerEntry.objects.filter(account_id=account.id)
                .order_by("-created_at", "-id")
                .only("running_balance")
                .first()
            )
            if last is None:
                continue
            LedgerAccount.objects.filter(pk=account.id).update(
                cached_balance=last.running_balance,
                cached_balance_updated_at=now,
            )


def noop_reverse(apps, schema_editor):
    """Column drop is handled by RemoveField on rollback. Data left untouched."""
    return None


class Migration(migrations.Migration):

    dependencies = [
        ("ledger", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="ledgeraccount",
            name="cached_balance",
            field=models.DecimalField(
                max_digits=18, decimal_places=2, default=Decimal("0.00"),
            ),
        ),
        migrations.AddField(
            model_name="ledgeraccount",
            name="cached_balance_updated_at",
            field=models.DateTimeField(null=True, blank=True),
        ),
        migrations.RunPython(backfill_cached_balance, noop_reverse),
    ]
