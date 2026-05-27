"""
Celery entry point for Marché CM.
Named celery_app.py (not celery.py) to avoid shadowing the celery package.

Usage:
  celery -A celery_app worker -Q default -c 4
  celery -A celery_app worker -Q financial -c 1
  celery -A celery_app worker -Q outbox -c 2
  celery -A celery_app beat --scheduler django_celery_beat.schedulers:DatabaseScheduler
"""
import os
from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

app = Celery("marche_cm")

app.config_from_object("django.conf:settings", namespace="CELERY")

app.autodiscover_tasks()

app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Africa/Abidjan",
    enable_utc=True,
    task_track_started=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    task_reject_on_worker_lost=True,
    task_routes={
        "apps.wallets.tasks.*": {"queue": "financial"},
        "apps.escrow.tasks.*": {"queue": "financial"},
        "apps.ledger.tasks.*": {"queue": "financial"},
        "apps.notifications.tasks.*": {"queue": "default"},
        "apps.logistics.tasks.*": {"queue": "default"},
        "apps.audit.tasks.*": {"queue": "default"},
        "core.events.tasks.*": {"queue": "outbox"},
    },
    beat_schedule={
        "process-outbox-events": {
            "task": "core.events.tasks.process_outbox_events",
            "schedule": 5.0,
            "options": {"queue": "outbox"},
        },
        "process-auto-escrow-releases": {
            "task": "apps.escrow.tasks.process_auto_releases",
            "schedule": 300.0,
            "options": {"queue": "financial"},
        },
        "retry-failed-payouts": {
            "task": "apps.wallets.tasks.retry_failed_payouts",
            "schedule": 180.0,
            "options": {"queue": "financial"},
        },
        "daily-reconciliation": {
            "task": "apps.wallets.tasks.run_daily_reconciliation",
            "schedule": 86400.0,
            "options": {"queue": "financial"},
        },
        "check-dispute-sla": {
            "task": "apps.disputes.tasks.check_sla_breaches",
            "schedule": 1800.0,
            "options": {"queue": "default"},
        },
        "cleanup-expired-idempotency": {
            "task": "apps.wallets.tasks.cleanup_expired_idempotency",
            "schedule": 3600.0,
            "options": {"queue": "default"},
        },
        # Audit ref: [NEW-005] verifier was missing — every 6 h.
        "verify-audit-chain-integrity": {
            "task": "apps.audit.tasks.verify_audit_chain_integrity",
            "schedule": 21600.0,
            "options": {"queue": "default"},
        },
        # Audit ref: [FIN-001 follow-up] wallet ↔ ledger reconciliation
        # every hour. Single-beat protected on the financial queue (c=1).
        "reconcile-wallet-ledger": {
            "task": "apps.ledger.tasks.reconcile_wallet_ledger",
            "schedule": 3600.0,
            "options": {"queue": "financial"},
        },
    },
)
