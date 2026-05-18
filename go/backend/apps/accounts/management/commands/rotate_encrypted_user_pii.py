from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.accounts.field_crypto import clear_crypto_cache


class Command(BaseCommand):
    help = (
        "Re-encrypt user PII fields with the current DATA_ENCRYPTION_KEY. "
        "Use DATA_ENCRYPTION_FALLBACK_KEYS to decrypt legacy values first."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Only report how many rows would be re-encrypted.",
        )

    def handle(self, *args, **options):
        dry_run = bool(options["dry_run"])
        user_model = get_user_model()
        fields = ["phone_number", "city", "location_label"]

        clear_crypto_cache()
        queryset = user_model.objects.all().only("id", *fields)
        total = queryset.count()
        rewritten = 0

        for user in queryset.iterator():
            values = {field: (getattr(user, field, "") or "") for field in fields}
            if dry_run:
                if any(values.values()):
                    rewritten += 1
                continue
            for field_name, field_value in values.items():
                setattr(user, field_name, field_value)
            user.save(update_fields=fields)
            rewritten += 1

        mode = "DRY-RUN" if dry_run else "EXECUTED"
        self.stdout.write(
            self.style.SUCCESS(
                f"[{mode}] rotate_encrypted_user_pii total={total} rewritten={rewritten}"
            )
        )
