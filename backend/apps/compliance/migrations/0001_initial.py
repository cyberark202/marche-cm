import uuid
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="SanctionsList",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("list_name", models.CharField(max_length=60)),
                ("entry_type", models.CharField(max_length=20)),
                ("full_name", models.CharField(db_index=True, max_length=300)),
                ("aliases", models.JSONField(default=list)),
                ("country", models.CharField(blank=True, max_length=4)),
                ("date_of_birth", models.CharField(blank=True, max_length=20)),
                ("reference_id", models.CharField(blank=True, max_length=100)),
                ("is_active", models.BooleanField(default=True)),
                ("last_updated", models.DateTimeField(auto_now=True)),
            ],
            options={
                "app_label": "compliance",
            },
        ),
        migrations.CreateModel(
            name="KYCApplication",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                (
                    "target_level",
                    models.PositiveSmallIntegerField(
                        choices=[
                            (0, "Aucun"),
                            (1, "KYC Basique (ID)"),
                            (2, "KYC Avancé (Business)"),
                        ]
                    ),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("PENDING", "En attente de revue"),
                            ("UNDER_REVIEW", "En cours de revue"),
                            ("APPROVED", "Approuvé"),
                            ("REJECTED", "Rejeté"),
                            ("EXPIRED", "Expiré"),
                            ("RESUBMIT_REQUIRED", "Nouvelle soumission requise"),
                        ],
                        db_index=True,
                        default="PENDING",
                        max_length=20,
                    ),
                ),
                ("submitted_at", models.DateTimeField(auto_now_add=True)),
                ("reviewed_at", models.DateTimeField(blank=True, null=True)),
                ("rejection_reason", models.TextField(blank=True)),
                ("risk_score", models.PositiveSmallIntegerField(default=0)),
                ("ocr_result", models.JSONField(blank=True, default=dict)),
                ("metadata", models.JSONField(blank=True, default=dict)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "reviewed_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="reviewed_kyc_applications",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="kyc_applications",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "app_label": "compliance",
                "ordering": ["-created_at"],
            },
        ),
        migrations.CreateModel(
            name="KYCDocument",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                (
                    "document_type",
                    models.CharField(
                        choices=[
                            ("NATIONAL_ID", "Carte nationale d'identité"),
                            ("PASSPORT", "Passeport"),
                            ("DRIVERS_LICENSE", "Permis de conduire"),
                            ("RCCM", "Registre Commerce (RCCM)"),
                            ("TAX_CERTIFICATE", "Attestation fiscale"),
                            ("PROOF_OF_ADDRESS", "Justificatif de domicile"),
                            ("SELFIE", "Selfie liveness"),
                        ],
                        max_length=24,
                    ),
                ),
                ("storage_key", models.CharField(max_length=400)),
                ("file_hash", models.CharField(max_length=64)),
                ("file_size_bytes", models.PositiveIntegerField(default=0)),
                ("mime_type", models.CharField(blank=True, max_length=60)),
                ("ocr_extracted", models.JSONField(blank=True, default=dict)),
                ("is_verified", models.BooleanField(default=False)),
                ("uploaded_at", models.DateTimeField(auto_now_add=True)),
                (
                    "application",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="documents",
                        to="compliance.kycapplication",
                    ),
                ),
            ],
            options={
                "app_label": "compliance",
            },
        ),
        migrations.CreateModel(
            name="AMLScreening",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("screening_type", models.CharField(max_length=30)),
                ("entity_type", models.CharField(blank=True, max_length=60)),
                ("entity_id", models.CharField(blank=True, max_length=80)),
                ("result", models.CharField(default="CLEAR", max_length=10)),
                ("hits", models.JSONField(default=list)),
                ("provider", models.CharField(default="INTERNAL", max_length=40)),
                ("screened_at", models.DateTimeField(auto_now_add=True)),
                ("metadata", models.JSONField(blank=True, default=dict)),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="aml_screenings",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "app_label": "compliance",
                "ordering": ["-screened_at"],
            },
        ),
        migrations.AddIndex(
            model_name="kycapplication",
            index=models.Index(
                fields=["user", "status"],
                name="idx_kyc_user_status",
            ),
        ),
        migrations.AddIndex(
            model_name="kycapplication",
            index=models.Index(
                fields=["status", "created_at"],
                name="idx_kyc_status_ts",
            ),
        ),
        migrations.AddIndex(
            model_name="sanctionslist",
            index=models.Index(
                fields=["list_name", "is_active"],
                name="idx_sanctions_list_active",
            ),
        ),
    ]
