from django.core.management.base import BaseCommand, CommandError
from decimal import Decimal

from apps.wallets.reconciliation import run_daily_reconciliation


class Command(BaseCommand):
    help = "Reconciliation financiere quotidienne: wallets/escrows/commissions/payouts."

    def add_arguments(self, parser):
        parser.add_argument(
            "--provider-real-balance",
            dest="provider_real_balance",
            default="",
            help="Solde reel NotchPay (FCFA) pour comparaison stricte.",
        )

    def handle(self, *args, **options):
        raw_provider_balance = str(options.get("provider_real_balance") or "").strip()
        provider_real_balance = None
        if raw_provider_balance:
            try:
                provider_real_balance = Decimal(raw_provider_balance).quantize(Decimal("0.01"))
            except Exception as exc:
                raise CommandError("--provider-real-balance invalide.") from exc

        report = run_daily_reconciliation(provider_real_balance=provider_real_balance, provider="NOTCHPAY")
        self.stdout.write(
            self.style.SUCCESS(
                f"Reconciliation {report.report_date}: status={report.status} variance={report.variance} unresolved_payouts={report.unresolved_payout_count}"
            )
        )
