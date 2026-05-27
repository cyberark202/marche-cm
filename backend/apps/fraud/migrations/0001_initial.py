import uuid
import django.db.models.deletion
import django.utils.timezone
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="BlacklistEntry",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("entry_type", models.CharField(
                    choices=[
                        ("PHONE", "Numéro de téléphone"),
                        ("IP", "Adresse IP"),
                        ("DEVICE", "Empreinte appareil"),
                        ("EMAIL", "Email"),
                        ("IBAN", "IBAN"),
                    ],
                    max_length=10,
                )),
                ("value", models.CharField(db_index=True, max_length=200)),
                ("reason", models.CharField(max_length=300)),
                ("expires_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "added_by",
                    models.ForeignKey(
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="blacklist_additions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "app_label": "fraud",
                "unique_together": {("entry_type", "value")},
            },
        ),
        migrations.CreateModel(
            name="FraudAssessment",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("action_type", models.CharField(db_index=True, max_length=40)),
                ("risk_score", models.PositiveSmallIntegerField()),
                (
                    "risk_level",
                    models.CharField(
                        choices=[
                            ("LOW", "Faible (0-30)"),
                            ("MEDIUM", "Moyen (31-60)"),
                            ("HIGH", "Élevé (61-80)"),
                            ("CRITICAL", "Critique (81-100)"),
                        ],
                        max_length=10,
                    ),
                ),
                (
                    "decision",
                    models.CharField(
                        choices=[
                            ("ALLOW", "Autorisé"),
                            ("REVIEW", "En révision"),
                            ("BLOCK", "Bloqué"),
                        ],
                        max_length=8,
                    ),
                ),
                ("signals", models.JSONField(default=list)),
                ("entity_type", models.CharField(blank=True, max_length=60)),
                ("entity_id", models.CharField(blank=True, max_length=80)),
                ("correlation_id", models.CharField(blank=True, max_length=80)),
                ("ip_address", models.GenericIPAddressField(blank=True, null=True)),
                ("device_fingerprint", models.CharField(blank=True, max_length=64)),
                ("reviewed", models.BooleanField(default=False)),
                ("reviewed_at", models.DateTimeField(blank=True, null=True)),
                ("review_outcome", models.CharField(blank=True, max_length=10)),
                ("metadata", models.JSONField(blank=True, default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "reviewed_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="reviewed_fraud_assessments",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="fraud_assessments",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "app_label": "fraud",
                "ordering": ["-created_at"],
            },
        ),
        migrations.CreateModel(
            name="UserRiskProfile",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("overall_score", models.PositiveSmallIntegerField(default=0)),
                ("assessment_count", models.PositiveIntegerField(default=0)),
                ("last_assessed_at", models.DateTimeField(blank=True, null=True)),
                ("is_watchlisted", models.BooleanField(default=False)),
                ("watchlist_reason", models.CharField(blank=True, max_length=300)),
                ("is_blocked", models.BooleanField(default=False)),
                ("blocked_reason", models.CharField(blank=True, max_length=300)),
                ("blocked_at", models.DateTimeField(blank=True, null=True)),
                ("lifetime_withdrawal_total", models.DecimalField(decimal_places=2, default=0, max_digits=16)),
                ("last_30d_withdrawal_total", models.DecimalField(decimal_places=2, default=0, max_digits=14)),
                ("failed_auth_count", models.PositiveSmallIntegerField(default=0)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="risk_profile",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "app_label": "fraud",
            },
        ),
        migrations.AddIndex(
            model_name="fraudassessment",
            index=models.Index(
                fields=["user", "decision", "reviewed"],
                name="idx_fraud_user_decision",
            ),
        ),
        migrations.AddIndex(
            model_name="fraudassessment",
            index=models.Index(
                fields=["risk_score", "reviewed"],
                name="idx_fraud_score_reviewed",
            ),
        ),
        migrations.AddIndex(
            model_name="fraudassessment",
            index=models.Index(
                fields=["action_type", "created_at"],
                name="idx_fraud_action_ts",
            ),
        ),
    ]
