"""
Dedicated dispute domain — event-sourced dispute case management.

DisputeCase: the main case
DisputeEvent: event-sourced timeline (append-only)
DisputeEvidence: uploaded evidence files
DisputeDecision: admin/mediator decisions

All state transitions go through DisputeStateMachine.
"""
import uuid
from django.conf import settings
from django.db import models


class DisputeState(models.TextChoices):
    OPEN = "OPEN", "Ouvert"
    UNDER_REVIEW = "UNDER_REVIEW", "En révision"
    AWAITING_EVIDENCE = "AWAITING_EVIDENCE", "En attente de preuves"
    ESCALATED = "ESCALATED", "Escaladé admin"
    ARBITRATION = "ARBITRATION", "Arbitrage en cours"
    RESOLVED_BUYER = "RESOLVED_BUYER", "Résolu en faveur acheteur"
    RESOLVED_SELLER = "RESOLVED_SELLER", "Résolu en faveur vendeur"
    RESOLVED_SPLIT = "RESOLVED_SPLIT", "Résolu — partage"
    CLOSED_NO_ACTION = "CLOSED_NO_ACTION", "Fermé sans action"
    APPEALED = "APPEALED", "Appel en cours"


DISPUTE_TRANSITIONS: dict[str, list[str]] = {
    DisputeState.OPEN: [
        DisputeState.UNDER_REVIEW,
        DisputeState.AWAITING_EVIDENCE,
        DisputeState.ESCALATED,
        DisputeState.CLOSED_NO_ACTION,
    ],
    DisputeState.UNDER_REVIEW: [
        DisputeState.AWAITING_EVIDENCE,
        DisputeState.ESCALATED,
        DisputeState.ARBITRATION,
        DisputeState.RESOLVED_BUYER,
        DisputeState.RESOLVED_SELLER,
        DisputeState.RESOLVED_SPLIT,
        DisputeState.CLOSED_NO_ACTION,
    ],
    DisputeState.AWAITING_EVIDENCE: [
        DisputeState.UNDER_REVIEW,
        DisputeState.ESCALATED,
        DisputeState.CLOSED_NO_ACTION,
    ],
    DisputeState.ESCALATED: [
        DisputeState.ARBITRATION,
        DisputeState.RESOLVED_BUYER,
        DisputeState.RESOLVED_SELLER,
        DisputeState.RESOLVED_SPLIT,
        DisputeState.CLOSED_NO_ACTION,
    ],
    DisputeState.ARBITRATION: [
        DisputeState.RESOLVED_BUYER,
        DisputeState.RESOLVED_SELLER,
        DisputeState.RESOLVED_SPLIT,
        DisputeState.CLOSED_NO_ACTION,
    ],
    DisputeState.RESOLVED_BUYER: [DisputeState.APPEALED],
    DisputeState.RESOLVED_SELLER: [DisputeState.APPEALED],
    DisputeState.RESOLVED_SPLIT: [DisputeState.APPEALED],
    DisputeState.APPEALED: [
        DisputeState.RESOLVED_BUYER,
        DisputeState.RESOLVED_SELLER,
        DisputeState.RESOLVED_SPLIT,
        DisputeState.CLOSED_NO_ACTION,
    ],
    DisputeState.CLOSED_NO_ACTION: [],
}


class DisputeCategory(models.TextChoices):
    PRODUCT_QUALITY = "PRODUCT_QUALITY", "Qualité produit"
    DELIVERY = "DELIVERY", "Livraison"
    FINANCIAL = "FINANCIAL", "Financier"
    FRAUD = "FRAUD", "Fraude"
    PLATFORM = "PLATFORM", "Plateforme"
    KYC = "KYC", "KYC/Conformité"
    OTHER = "OTHER", "Autre"


class DisputeCase(models.Model):
    """
    A dispute case. Event-sourced: history is in DisputeEvent.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    reference = models.CharField(max_length=20, unique=True)  # e.g. DSP-20240523-001
    category = models.CharField(max_length=20, choices=DisputeCategory.choices, db_index=True)
    dispute_type = models.CharField(max_length=40, db_index=True)
    state = models.CharField(
        max_length=24, choices=DisputeState.choices,
        default=DisputeState.OPEN, db_index=True
    )
    opened_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="opened_dispute_cases",
    )
    accused_party = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="accused_dispute_cases",
    )
    assigned_mediator = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="mediated_dispute_cases",
    )
    entity_type = models.CharField(max_length=60)
    entity_id = models.CharField(max_length=80)
    title = models.CharField(max_length=200)
    description = models.TextField()
    # Escrow reference — frozen escrow during dispute
    escrow_hold_id = models.UUIDField(null=True, blank=True)
    escrow_frozen_amount = models.DecimalField(max_digits=14, decimal_places=2, null=True, blank=True)
    # SLA
    sla_due_at = models.DateTimeField(null=True, blank=True)
    sla_breached = models.BooleanField(default=False)
    # Resolution
    resolution_outcome = models.CharField(max_length=30, blank=True)
    resolution_note = models.TextField(blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="resolved_dispute_cases",
    )
    # Appeal
    appeal_deadline = models.DateTimeField(null=True, blank=True)
    is_critical = models.BooleanField(default=False)
    guarantee_fund_used = models.BooleanField(default=False)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["state", "sla_due_at"], name="idx_dispute_state_sla"),
            models.Index(fields=["opened_by", "state"], name="idx_dispute_opener_state"),
            models.Index(fields=["entity_type", "entity_id"], name="idx_dispute_entity"),
        ]

    def can_transition_to(self, target: str) -> bool:
        return target in DISPUTE_TRANSITIONS.get(self.state, [])

    def __str__(self) -> str:
        return f"DisputeCase({self.reference}, {self.state})"


class DisputeEventType(models.TextChoices):
    OPENED = "OPENED", "Ouvert"
    STATE_CHANGED = "STATE_CHANGED", "État modifié"
    EVIDENCE_ADDED = "EVIDENCE_ADDED", "Preuve ajoutée"
    MEDIATOR_ASSIGNED = "MEDIATOR_ASSIGNED", "Médiateur assigné"
    MESSAGE_ADDED = "MESSAGE_ADDED", "Message ajouté"
    ESCROW_FROZEN = "ESCROW_FROZEN", "Escrow gelé"
    ESCROW_RELEASED = "ESCROW_RELEASED", "Escrow libéré"
    DECISION_MADE = "DECISION_MADE", "Décision rendue"
    APPEAL_FILED = "APPEAL_FILED", "Appel déposé"
    ESCALATED = "ESCALATED", "Escaladé"
    SLA_BREACH = "SLA_BREACH", "SLA dépassé"


class DisputeEvent(models.Model):
    """
    Append-only event log — the event-sourced history of a DisputeCase.
    Never update or delete these rows.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    dispute = models.ForeignKey(DisputeCase, on_delete=models.CASCADE, related_name="events")
    event_type = models.CharField(max_length=30, choices=DisputeEventType.choices)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="dispute_events_as_actor",
    )
    from_state = models.CharField(max_length=24, blank=True)
    to_state = models.CharField(max_length=24, blank=True)
    description = models.TextField(blank=True)
    payload = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]


class EvidenceType(models.TextChoices):
    PHOTO = "PHOTO", "Photo"
    VIDEO = "VIDEO", "Vidéo"
    DOCUMENT = "DOCUMENT", "Document"
    SCREENSHOT = "SCREENSHOT", "Capture d'écran"
    INSPECTION_REPORT = "INSPECTION_REPORT", "Rapport d'inspection"
    CHAT_EXPORT = "CHAT_EXPORT", "Export conversation"


class DisputeEvidence(models.Model):
    """Evidence uploaded to support a dispute. Immutable after upload."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    dispute = models.ForeignKey(DisputeCase, on_delete=models.CASCADE, related_name="evidences")
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="uploaded_case_evidences",
    )
    evidence_type = models.CharField(max_length=20, choices=EvidenceType.choices)
    file_key = models.CharField(max_length=300)  # S3 key or storage path
    file_hash = models.CharField(max_length=64)  # SHA-256 for tamper detection
    file_size_bytes = models.PositiveIntegerField(default=0)
    description = models.CharField(max_length=400, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["uploaded_at"]


class DisputeDecision(models.Model):
    """Formal decision record — immutable once created."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    dispute = models.OneToOneField(DisputeCase, on_delete=models.CASCADE, related_name="decision")
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="made_dispute_decisions",
    )
    outcome = models.CharField(max_length=30)  # REFUND_BUYER | RELEASE_SELLER | SPLIT | NO_ACTION
    buyer_refund_amount = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    seller_release_amount = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    reasoning = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
