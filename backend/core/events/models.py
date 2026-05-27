import uuid
from django.db import models


class OutboxStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    PROCESSING = "PROCESSING", "En cours"
    PROCESSED = "PROCESSED", "Traité"
    FAILED = "FAILED", "Échoué"
    DEAD = "DEAD", "Dead letter"


class OutboxEvent(models.Model):
    """
    Outbox pattern: persisted domain events published atomically with domain operations.
    A Celery beat task reads PENDING events and dispatches them to handlers.
    Never delete rows — they are the audit trail of all domain events.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    event_type = models.CharField(max_length=80, db_index=True)   # e.g. ORDER_CREATED
    aggregate_type = models.CharField(max_length=60, db_index=True)  # e.g. Order
    aggregate_id = models.CharField(max_length=80, db_index=True)
    payload = models.JSONField(default=dict)
    correlation_id = models.CharField(max_length=80, blank=True, db_index=True)
    causation_id = models.UUIDField(null=True, blank=True)  # ID of the causing event
    status = models.CharField(max_length=12, choices=OutboxStatus.choices, default=OutboxStatus.PENDING, db_index=True)
    retry_count = models.PositiveSmallIntegerField(default=0)
    max_retries = models.PositiveSmallIntegerField(default=5)
    next_retry_at = models.DateTimeField(null=True, blank=True, db_index=True)
    processed_at = models.DateTimeField(null=True, blank=True)
    error_message = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        app_label = "core_events"
        ordering = ["created_at"]
        indexes = [
            models.Index(fields=["status", "next_retry_at"], name="idx_outbox_status_retry"),
            models.Index(fields=["event_type", "status"], name="idx_outbox_type_status"),
            models.Index(fields=["aggregate_type", "aggregate_id"], name="idx_outbox_aggregate"),
        ]

    def __str__(self) -> str:
        return f"OutboxEvent({self.event_type}, {self.aggregate_id}, {self.status})"
