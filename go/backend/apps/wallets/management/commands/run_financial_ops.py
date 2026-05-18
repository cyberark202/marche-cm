import json
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from apps.wallets.models import ReconciliationStatus
from apps.wallets.ops_alerts import send_finops_alert
from apps.wallets.payout_retry import process_due_payout_retries
from apps.wallets.provider_balance import resolve_provider_real_balance
from apps.wallets.reconciliation import run_daily_reconciliation


class Command(BaseCommand):
    help = "Orchestrateur FinOps: retries payout + reconciliation + alerting."

    def add_arguments(self, parser):
        parser.add_argument("--skip-retries", action="store_true", help="Ne pas traiter la queue retries payout.")
        parser.add_argument("--skip-reconciliation", action="store_true", help="Ne pas lancer la reconciliation.")
        parser.add_argument("--retries-limit", type=int, default=200)
        parser.add_argument("--provider-real-balance", default="", help="Override manuel du solde reel provider.")
        parser.add_argument(
            "--strict-provider-balance",
            action="store_true",
            help="Echoue si aucun solde provider reel n'est disponible.",
        )
        parser.add_argument("--send-alerts", action="store_true", default=True)
        parser.add_argument("--no-send-alerts", action="store_false", dest="send_alerts")
        parser.add_argument("--fail-on-alert", action="store_true", help="Retour non-zero si alerte detectee.")

    def handle(self, *args, **options):
        summary: dict = {
            "retries": None,
            "reconciliation": None,
            "provider_balance_source": "",
            "provider_balance_error": "",
            "alerts_sent": False,
        }

        if not options["skip_retries"]:
            retries_limit = max(1, int(options["retries_limit"] or 200))
            summary["retries"] = process_due_payout_retries(limit=retries_limit)

        provider_balance = None
        provider_balance_source = "not_required"
        provider_balance_error = ""
        raw_provider_balance = str(options.get("provider_real_balance") or "").strip()
        if raw_provider_balance:
            try:
                provider_balance = Decimal(raw_provider_balance).quantize(Decimal("0.01"))
            except Exception as exc:
                raise CommandError("--provider-real-balance invalide.") from exc
            provider_balance_source = "cli_override"
        elif not options["skip_reconciliation"]:
            provider_balance, provider_balance_source, provider_balance_error = resolve_provider_real_balance()

        summary["provider_balance_source"] = provider_balance_source
        summary["provider_balance_error"] = provider_balance_error

        report = None
        if not options["skip_reconciliation"]:
            report = run_daily_reconciliation(provider_real_balance=provider_balance, provider="NOTCHPAY")
            summary["reconciliation"] = {
                "date": str(report.report_date),
                "status": report.status,
                "variance": str(report.variance),
                "unresolved_payout_count": int(report.unresolved_payout_count),
            }

        strict_required = bool(options["strict_provider_balance"] or getattr(settings, "RECONCILIATION_REQUIRE_PROVIDER_BALANCE", True))
        missing_provider_balance = not options["skip_reconciliation"] and provider_balance is None and strict_required

        retries_stats = summary["retries"] or {}
        retries_failed = int(retries_stats.get("failed", 0) or 0)
        retries_backlog = int((summary.get("reconciliation") or {}).get("unresolved_payout_count", 0) or 0)
        backlog_threshold = int(getattr(settings, "FINOPS_RETRIES_BACKLOG_THRESHOLD", 10) or 10)

        should_alert = False
        alert_reasons = []
        if report and bool(getattr(settings, "FINOPS_ALERT_ON_RECON_ALERT", True)) and report.status in {
            ReconciliationStatus.ALERT,
            ReconciliationStatus.FAILED,
        }:
            should_alert = True
            alert_reasons.append(f"reconciliation_status={report.status}")
        if retries_failed > 0 and bool(getattr(settings, "FINOPS_ALERT_ON_RETRIES_FAILURE", True)):
            should_alert = True
            alert_reasons.append(f"retries_failed={retries_failed}")
        if retries_backlog > backlog_threshold and bool(getattr(settings, "FINOPS_ALERT_ON_RETRIES_BACKLOG", True)):
            should_alert = True
            alert_reasons.append(f"retries_backlog={retries_backlog}")
        if missing_provider_balance:
            should_alert = True
            alert_reasons.append("provider_balance_missing")

        if should_alert and options["send_alerts"]:
            title = "Central Market FinOps Alert"
            body = (
                f"Reasons: {', '.join(alert_reasons)}\n"
                f"Provider source: {provider_balance_source}\n"
                f"Provider error: {provider_balance_error}\n"
                f"Summary: {json.dumps(summary, ensure_ascii=True)}"
            )
            send_finops_alert(
                title=title,
                body=body,
                metadata={
                    "alert_reasons": alert_reasons,
                    "provider_balance_source": provider_balance_source,
                },
            )
            summary["alerts_sent"] = True

        self.stdout.write(self.style.SUCCESS(json.dumps(summary, ensure_ascii=True)))

        if missing_provider_balance:
            raise CommandError("Mode strict: solde provider reel manquant.")
        if options["fail_on_alert"] and should_alert:
            raise CommandError("Alerte FinOps detectee.")

