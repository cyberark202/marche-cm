"""
Migration 0010 — Idempotency records, transaction state audit log, performance indexes.

Phase 1 — IdempotencyRecord:
  Dedicated request-level lock table that prevents race-condition double charges
  and validates request-body hashes to block key-reuse fraud.

Phase 2 — WalletTransactionStateLog:
  Append-only audit log for every state transition of a WalletTransaction.
  Used for: compliance audit, reconciliation, ML training, incident response.

Phase 10 — PostgreSQL performance indexes:
  (wallet_id, created_at) on WalletTransaction — speeds up paginated
  per-user transaction lists (the most common query).
  (status, created_at) on WalletTransaction — speeds up pending
  reconciliation queries and admin dashboards.
"""

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("wallets", "0009_fraudevent"),
        ("accounts", "0001_initial"),
    ]

    operations = [
        # ── Phase 1: IdempotencyRecord ────────────────────────────────────────
        migrations.CreateModel(
            name="IdempotencyRecord",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("key", models.CharField(max_length=120)),
                ("endpoint", models.CharField(max_length=60)),
                ("request_hash", models.CharField(max_length=64)),
                ("response_snapshot", models.JSONField(blank=True, null=True)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("processing", "En cours"),
                            ("complete", "Termine"),
                            ("failed", "Echec"),
                        ],
                        default="processing",
                        max_length=12,
                    ),
                ),
                ("expires_at", models.DateTimeField()),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="idempotency_records",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"ordering": ["-created_at"]},
        ),
        migrations.AddConstraint(
            model_name="idempotencyrecord",
            constraint=models.UniqueConstraint(
                fields=["key", "user", "endpoint"],
                name="uniq_idempotency_key_user_endpoint",
            ),
        ),
        migrations.AddIndex(
            model_name="idempotencyrecord",
            index=models.Index(fields=["expires_at"], name="idx_idempotency_expires_at"),
        ),

        # ── Phase 2: WalletTransactionStateLog ───────────────────────────────
        migrations.CreateModel(
            name="WalletTransactionStateLog",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("from_status", models.CharField(blank=True, max_length=20)),
                ("to_status", models.CharField(max_length=20)),
                ("extended_status", models.CharField(blank=True, max_length=40)),
                ("reason", models.CharField(blank=True, max_length=240)),
                ("actor_id", models.IntegerField(blank=True, null=True)),
                ("metadata", models.JSONField(blank=True, default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "transaction",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="state_logs",
                        to="wallets.wallettransaction",
                    ),
                ),
            ],
            options={"ordering": ["created_at"]},
        ),
        migrations.AddIndex(
            model_name="wallettransactionstatelog",
            index=models.Index(
                fields=["transaction", "created_at"],
                name="idx_tx_state_log_tx_ts",
            ),
        ),

        # ── Phase 10: Performance indexes on WalletTransaction ───────────────
        migrations.AddIndex(
            model_name="wallettransaction",
            index=models.Index(
                fields=["wallet", "created_at"],
                name="idx_wallettx_wallet_created",
            ),
        ),
        migrations.AddIndex(
            model_name="wallettransaction",
            index=models.Index(
                fields=["status", "created_at"],
                name="idx_wallettx_status_created",
            ),
        ),
        migrations.AddIndex(
            model_name="wallettransaction",
            index=models.Index(
                fields=["wallet", "status", "created_at"],
                name="idx_wallettx_wallet_status_created",
            ),
        ),
    ]
