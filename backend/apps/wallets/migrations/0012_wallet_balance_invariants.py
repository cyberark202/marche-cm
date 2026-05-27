"""
[FIN-002] Wallet balance invariants.

Two database-level invariants are added to prevent the silent corruption
that was possible before this migration:

  1. `wallet_blocked_eq_locked`
     blocked_balance == locked_balance  (legacy field is a mirror)

  2. `wallet_balance_eq_components`
     balance == available_balance + locked_balance + pending_balance

A forward data step normalises any drift on existing rows before the
constraints are added, so deploys against a non-empty database succeed.
The reverse step only drops the constraints — no data is mutated on
rollback.
"""
from decimal import Decimal

from django.db import migrations, models


def normalize_existing_wallets(apps, schema_editor):
    Wallet = apps.get_model("wallets", "Wallet")
    quant = Decimal("0.01")
    # Stream-update in bulk, in chunks of 500 rows to avoid loading the whole
    # table for very large deployments. The arithmetic uses Python Decimal
    # (the database value is already Decimal because of the DecimalField).
    qs = Wallet.objects.all().only(
        "id", "available_balance", "locked_balance", "pending_balance",
        "balance", "blocked_balance",
    )
    batch = []
    BATCH_SIZE = 500
    for wallet in qs.iterator(chunk_size=BATCH_SIZE):
        avail = (wallet.available_balance or Decimal("0")).quantize(quant)
        locked = (wallet.locked_balance or Decimal("0")).quantize(quant)
        pending = (wallet.pending_balance or Decimal("0")).quantize(quant)
        wallet.available_balance = avail
        wallet.locked_balance = locked
        wallet.pending_balance = pending
        wallet.blocked_balance = locked
        wallet.balance = (avail + locked + pending).quantize(quant)
        batch.append(wallet)
        if len(batch) >= BATCH_SIZE:
            Wallet.objects.bulk_update(
                batch,
                ["available_balance", "locked_balance", "pending_balance",
                 "balance", "blocked_balance"],
            )
            batch.clear()
    if batch:
        Wallet.objects.bulk_update(
            batch,
            ["available_balance", "locked_balance", "pending_balance",
             "balance", "blocked_balance"],
        )


def noop_reverse(apps, schema_editor):
    """Constraint drops are handled by the AddConstraint reverse. Data is
    intentionally left as-is on rollback to keep the audit trail consistent.
    """
    return None


class Migration(migrations.Migration):

    dependencies = [
        ("wallets", "0011_wallet_currency"),
    ]

    operations = [
        migrations.RunPython(normalize_existing_wallets, noop_reverse),
        migrations.AddConstraint(
            model_name="wallet",
            constraint=models.CheckConstraint(
                condition=models.Q(blocked_balance=models.F("locked_balance")),
                name="wallet_blocked_eq_locked",
            ),
        ),
        migrations.AddConstraint(
            model_name="wallet",
            constraint=models.CheckConstraint(
                condition=models.Q(
                    balance=models.F("available_balance")
                    + models.F("locked_balance")
                    + models.F("pending_balance")
                ),
                name="wallet_balance_eq_components",
            ),
        ),
    ]
