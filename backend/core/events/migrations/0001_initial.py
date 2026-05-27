import uuid
import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = []

    operations = [
        migrations.CreateModel(
            name="OutboxEvent",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("event_type", models.CharField(db_index=True, max_length=80)),
                ("aggregate_type", models.CharField(db_index=True, max_length=60)),
                ("aggregate_id", models.CharField(db_index=True, max_length=80)),
                ("payload", models.JSONField(default=dict)),
                ("correlation_id", models.CharField(blank=True, db_index=True, max_length=80)),
                ("causation_id", models.UUIDField(blank=True, null=True)),
                ("status", models.CharField(choices=[("PENDING","En attente"),("PROCESSING","En cours"),("PROCESSED","Traité"),("FAILED","Échoué"),("DEAD","Dead letter")], db_index=True, default="PENDING", max_length=12)),
                ("retry_count", models.PositiveSmallIntegerField(default=0)),
                ("max_retries", models.PositiveSmallIntegerField(default=5)),
                ("next_retry_at", models.DateTimeField(blank=True, db_index=True, null=True)),
                ("processed_at", models.DateTimeField(blank=True, null=True)),
                ("error_message", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True, db_index=True)),
            ],
            options={"ordering": ["created_at"], "app_label": "core_events"},
        ),
        migrations.AddIndex(
            model_name="outboxevent",
            index=models.Index(fields=["status", "next_retry_at"], name="idx_outbox_status_retry"),
        ),
        migrations.AddIndex(
            model_name="outboxevent",
            index=models.Index(fields=["event_type", "status"], name="idx_outbox_type_status"),
        ),
        migrations.AddIndex(
            model_name="outboxevent",
            index=models.Index(fields=["aggregate_type", "aggregate_id"], name="idx_outbox_aggregate"),
        ),
    ]
