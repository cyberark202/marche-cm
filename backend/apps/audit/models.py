"""
Immutable audit trail for Marché CM.

Rules:
  - AuditEvent rows are NEVER updated or deleted (append-only).
  - Every critical domain action MUST generate an AuditEvent.
  - AuditEvents are signed with a chain hash to detect tampering.
  - actor_id may be null for system-generated events.
"""
import uuid
import hashlib
import json
from django.conf import settings
from django.db import models, transaction


class AuditCategory(models.TextChoices):
    AUTH = "AUTH", "Authentification"
    FINANCIAL = "FINANCIAL", "Financier"
    ORDER = "ORDER", "Commande"
    ESCROW = "ESCROW", "Escrow"
    DISPUTE = "DISPUTE", "Litige"
    KYC = "KYC", "KYC/Conformité"
    FRAUD = "FRAUD", "Fraude"
    ADMIN = "ADMIN", "Administration"
    LOGISTICS = "LOGISTICS", "Logistique"
    SYSTEM = "SYSTEM", "Système"
    USER = "USER", "Utilisateur"


class AuditEvent(models.Model):
    """
    Immutable audit event.
    chain_hash = SHA-256(prev_chain_hash + event_type + actor_id + entity_id + payload_json)
    This creates a tamper-evident chain of events per entity.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    category = models.CharField(max_length=16, choices=AuditCategory.choices, db_index=True)
    event_type = models.CharField(max_length=100, db_index=True)
    actor_id = models.IntegerField(null=True, blank=True, db_index=True)
    actor_role = models.CharField(max_length=20, blank=True)
    entity_type = models.CharField(max_length=60, db_index=True)
    entity_id = models.CharField(max_length=80, db_index=True)
    payload = models.JSONField(default=dict)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    correlation_id = models.CharField(max_length=80, blank=True, db_index=True)
    chain_hash = models.CharField(max_length=64, blank=True)
    outcome = models.CharField(max_length=10, default="SUCCESS")  # SUCCESS | FAILURE | PARTIAL
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["entity_type", "entity_id", "created_at"], name="idx_audit_entity"),
            models.Index(fields=["actor_id", "created_at"], name="idx_audit_actor"),
            models.Index(fields=["category", "created_at"], name="idx_audit_category"),
            models.Index(fields=["event_type", "created_at"], name="idx_audit_event_type"),
        ]

    def save(self, *args, **kwargs):
        # Audit ref: [FIN-007] previously the chain hash was read without any
        # locking, so two events arriving concurrently for the same entity
        # could share the same `prev_hash` and create a forked chain. We now
        # serialize the read+write with a short distributed Redis lock keyed
        # on (entity_type, entity_id) — the lock is auto-released on exit and
        # has a 5 s TTL so a crashed process cannot poison the chain forever.
        if self.chain_hash:
            super().save(*args, **kwargs)
            return

        from core.locks import acquire_lock, LockAcquisitionError

        lock_key = f"audit-chain:{self.entity_type}:{self.entity_id}"
        try:
            with acquire_lock(lock_key, ttl_seconds=5, retry_count=10, retry_delay_ms=50):
                with transaction.atomic():
                    self.chain_hash = self._compute_chain_hash()
                    super().save(*args, **kwargs)
        except LockAcquisitionError:
            # Lock saturation — write anyway with best-effort hash to keep
            # the audit trail alive. A reconciliation job can verify the
            # chain offline and flag any forked segment.
            self.chain_hash = self._compute_chain_hash()
            super().save(*args, **kwargs)

    def _compute_chain_hash(self) -> str:
        prev = (
            AuditEvent.objects
            .filter(entity_type=self.entity_type, entity_id=self.entity_id)
            .order_by("-created_at")
            .values_list("chain_hash", flat=True)
            .first()
        ) or ""
        raw = f"{prev}:{self.event_type}:{self.actor_id}:{self.entity_id}:{json.dumps(self.payload, sort_keys=True)}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()

    def __str__(self) -> str:
        return f"AuditEvent({self.event_type}, {self.entity_type}/{self.entity_id})"
