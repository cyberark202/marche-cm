"""
Migration 0009 — FraudEvent model for fraud detection audit trail.

Security rationale (OWASP ASVS V10, PCI-DSS Req. 10):
  Every fraud evaluation with a non-zero risk score is persisted for:
  - Compliance audit and reporting
  - Manual review of held transactions
  - Pattern analysis and ML training data
  - Incident response investigation
"""

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("wallets", "0008_alter_dailyreconciliationreport_provider_and_more"),
        ("accounts", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="FraudEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("event_type", models.CharField(max_length=40)),
                ("risk_score", models.PositiveSmallIntegerField()),
                (
                    "decision",
                    models.CharField(
                        choices=[("allow", "Autorise"), ("hold", "En attente de revue"), ("block", "Bloque")],
                        max_length=10,
                    ),
                ),
                ("metadata", models.JSONField(blank=True, default=dict)),
                ("resolved", models.BooleanField(default=False)),
                ("resolved_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="fraud_events",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "resolved_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="resolved_fraud_events",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"ordering": ["-created_at"]},
        ),
        migrations.AddIndex(
            model_name="fraudevent",
            index=models.Index(fields=["user", "decision", "resolved"], name="fraud_user_decision_idx"),
        ),
        migrations.AddIndex(
            model_name="fraudevent",
            index=models.Index(fields=["risk_score", "resolved"], name="fraud_score_idx"),
        ),
    ]
