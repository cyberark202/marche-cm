"""
migrate_wallet_pin — force users with a legacy 4-digit wallet PIN to reset.

Audit ref: V9.1 raised the minimum wallet-PIN length from 4 to 6 digits. The
verify path remains permissive until this command flags every user whose
PIN was set under the old rule, then clears their `wallet_pin_hash` and
notifies them to re-enter a new PIN on next sensitive action.

We cannot read the actual PIN length from the PBKDF2 hash. Instead we treat
EVERY existing `wallet_pin_hash` as legacy and clear it (worst case: a user
whose PIN was already 6+ digits has to re-enter the same value). This is
the only correct safety move — leaving any unknown-length PIN in place
would silently bypass the new rule.

Usage:
    python manage.py migrate_wallet_pin --dry-run
    python manage.py migrate_wallet_pin --execute --notify
"""
from __future__ import annotations

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction

User = get_user_model()


class Command(BaseCommand):
    help = "Clear legacy 4-digit wallet PINs and notify affected users."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report counts without modifying any row.",
        )
        parser.add_argument(
            "--execute",
            action="store_true",
            help="Actually clear wallet_pin_hash for affected users.",
        )
        parser.add_argument(
            "--notify",
            action="store_true",
            help="Send an in-app notification asking the user to re-enter a PIN.",
        )
        parser.add_argument(
            "--batch-size",
            type=int,
            default=500,
            help="Rows per UPDATE batch (default 500).",
        )

    def handle(self, *args, **opts):
        dry = opts["dry_run"]
        execute = opts["execute"]
        notify = opts["notify"]
        batch_size = max(1, opts["batch_size"])

        if not dry and not execute:
            self.stderr.write(
                "Refusing to run: pass --dry-run to preview or --execute to apply."
            )
            return

        # Find every user with a non-blank PIN hash. We can't introspect the
        # original PIN length from the hash, so we treat all of them as legacy.
        qs = User.objects.exclude(wallet_pin_hash="").only(
            "id", "wallet_pin_hash", "wallet_pin_failed_attempts",
        )
        total = qs.count()
        self.stdout.write(f"Users with a wallet PIN set: {total}")

        if dry:
            self.stdout.write(self.style.NOTICE("DRY RUN — no rows modified."))
            return

        cleared = 0
        notified = 0
        ids = list(qs.values_list("id", flat=True))
        for offset in range(0, len(ids), batch_size):
            chunk_ids = ids[offset : offset + batch_size]
            with transaction.atomic():
                cleared += User.objects.filter(id__in=chunk_ids).update(
                    wallet_pin_hash="",
                    wallet_pin_failed_attempts=0,
                    wallet_pin_locked_until=None,
                )
                if notify:
                    notified += _send_pin_reset_notifications(chunk_ids)

        self.stdout.write(self.style.SUCCESS(f"PIN cleared for {cleared} user(s)."))
        if notify:
            self.stdout.write(self.style.SUCCESS(f"Notifications enqueued: {notified}"))


def _send_pin_reset_notifications(user_ids: list[int]) -> int:
    """Enqueue an in-app notification per user. Returns count actually written.

    The notifications app may or may not be installed; failure to notify is
    NOT a reason to abort the PIN reset.
    """
    try:
        from apps.notifications.models import Notification
    except Exception:
        return 0
    rows = [
        Notification(
            user_id=uid,
            kind="WALLET_PIN_RESET_REQUIRED",
            title="Reconfigurez votre PIN portefeuille",
            body=(
                "Pour des raisons de securite, votre PIN doit etre reconfigure "
                "(6 chiffres minimum). Ouvrez les parametres du portefeuille pour "
                "en choisir un nouveau."
            ),
            is_read=False,
        )
        for uid in user_ids
    ]
    Notification.objects.bulk_create(rows, ignore_conflicts=True)
    return len(rows)
