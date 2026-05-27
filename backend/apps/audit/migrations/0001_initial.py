import uuid
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="AuditEvent",
            fields=[
                ("id", models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, serialize=False)),
                ("category", models.CharField(
                    db_index=True,
                    max_length=16,
                    choices=[
                        ("AUTH", "Authentification"),
                        ("FINANCIAL", "Financier"),
                        ("ORDER", "Commande"),
                        ("ESCROW", "Escrow"),
                        ("DISPUTE", "Litige"),
                        ("KYC", "KYC/Conformité"),
                        ("FRAUD", "Fraude"),
                        ("ADMIN", "Administration"),
                        ("LOGISTICS", "Logistique"),
                        ("SYSTEM", "Système"),
                        ("USER", "Utilisateur"),
                    ],
                )),
                ("event_type", models.CharField(db_index=True, max_length=100)),
                ("actor_id", models.IntegerField(blank=True, db_index=True, null=True)),
                ("actor_role", models.CharField(blank=True, max_length=20)),
                ("entity_type", models.CharField(db_index=True, max_length=60)),
                ("entity_id", models.CharField(db_index=True, max_length=80)),
                ("payload", models.JSONField(default=dict)),
                ("ip_address", models.GenericIPAddressField(blank=True, null=True)),
                ("user_agent", models.TextField(blank=True)),
                ("correlation_id", models.CharField(blank=True, db_index=True, max_length=80)),
                ("chain_hash", models.CharField(blank=True, max_length=64)),
                ("outcome", models.CharField(default="SUCCESS", max_length=10)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddIndex(
            model_name="auditevent",
            index=models.Index(
                fields=["entity_type", "entity_id", "created_at"],
                name="idx_audit_entity",
            ),
        ),
        migrations.AddIndex(
            model_name="auditevent",
            index=models.Index(
                fields=["actor_id", "created_at"],
                name="idx_audit_actor",
            ),
        ),
        migrations.AddIndex(
            model_name="auditevent",
            index=models.Index(
                fields=["category", "created_at"],
                name="idx_audit_category",
            ),
        ),
        migrations.AddIndex(
            model_name="auditevent",
            index=models.Index(
                fields=["event_type", "created_at"],
                name="idx_audit_event_type",
            ),
        ),
    ]
