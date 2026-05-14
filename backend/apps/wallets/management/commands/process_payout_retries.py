from django.core.management.base import BaseCommand

from apps.wallets.payout_retry import process_due_payout_retries


class Command(BaseCommand):
    help = "Traite les retries payout en attente (NotchPay Transfers)."

    def add_arguments(self, parser):
        parser.add_argument("--limit", type=int, default=100)

    def handle(self, *args, **options):
        stats = process_due_payout_retries(limit=int(options["limit"] or 100))
        self.stdout.write(
            self.style.SUCCESS(
                "Payout retries: "
                f"processed={stats['processed']} succeeded={stats['succeeded']} "
                f"failed={stats['failed']} rescheduled={stats['rescheduled']}"
            )
        )
