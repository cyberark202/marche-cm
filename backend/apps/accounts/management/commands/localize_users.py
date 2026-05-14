import time

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from apps.accounts.location_service import update_user_location


class Command(BaseCommand):
    help = "Geolocalise les utilisateurs via Nominatim (OpenStreetMap)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--force",
            action="store_true",
            help="Re-geolocaliser aussi les comptes deja localises.",
        )
        parser.add_argument(
            "--sleep-seconds",
            type=float,
            default=1.1,
            help="Pause entre requetes Nominatim (respect policy, default=1.1s).",
        )

    def handle(self, *args, **options):
        force = bool(options["force"])
        sleep_seconds = max(float(options["sleep_seconds"]), 0.0)
        User = get_user_model()

        total = 0
        localized = 0
        for user in User.objects.order_by("id").all():
            total += 1
            changed = update_user_location(user, force=force)
            if changed:
                localized += 1
                self.stdout.write(self.style.SUCCESS(f"Localise: {user.username}"))
            else:
                self.stdout.write(f"Inchange: {user.username}")
            if sleep_seconds > 0:
                time.sleep(sleep_seconds)

        self.stdout.write(
            self.style.SUCCESS(
                f"Termine. Utilisateurs traites: {total}. Localisations mises a jour: {localized}."
            )
        )
