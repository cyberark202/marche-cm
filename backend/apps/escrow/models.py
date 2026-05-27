"""
Escrow domain — dedicated escrow engine with strict state machines.

EscrowHold: a hold of funds for a specific purpose (ORDER, DISPUTE, etc.)
EscrowRelease: records each partial/full release from an EscrowHold
EscrowTransition: immutable log of all state transitions (tamper-evident)

State machine:
  PENDING → LOCKED → READY_TO_RELEASE → RELEASED
                   → FROZEN ← DISPUTE
                   → REFUNDED
  LOCKED → PARTIALLY_RELEASED → RELEASED
"""
import uuid
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class EscrowPurpose(models.TextChoices):
    ORDER_PAYMENT = "ORDER_PAYMENT", "Paiement commande"
    LOGISTICS_FEE = "LOGISTICS_FEE", "Frais logistique"
    DISPUTE_FREEZE = "DISPUTE_FREEZE", "Gel litige"
    PLATFORM_GUARANTEE = "PLATFORM_GUARANTEE", "Garantie plateforme"


class EscrowState(models.TextChoices):
    PENDING = "PENDING", "En attente de fonds"
    LOCKED = "LOCKED", "Fonds verrouillés"
    PARTIALLY_RELEASED = "PARTIALLY_RELEASED", "Partiellement libéré"
    READY_TO_RELEASE = "READY_TO_RELEASE", "Prêt à libérer"
    FROZEN = "FROZEN", "Gelé (litige)"
    RELEASED = "RELEASED", "Libéré au bénéficiaire"
    REFUNDED = "REFUNDED", "Remboursé à l'acheteur"
    CANCELLED = "CANCELLED", "Annulé"


ESCROW_TRANSITIONS: dict[str, list[str]] = {
    EscrowState.PENDING: [EscrowState.LOCKED, EscrowState.CANCELLED],
    EscrowState.LOCKED: [
        EscrowState.READY_TO_RELEASE,
        EscrowState.FROZEN,
        EscrowState.PARTIALLY_RELEASED,
        EscrowState.REFUNDED,
    ],
    EscrowState.PARTIALLY_RELEASED: [
        EscrowState.READY_TO_RELEASE,
        EscrowState.FROZEN,
        EscrowState.REFUNDED,
    ],
    EscrowState.READY_TO_RELEASE: [EscrowState.RELEASED, EscrowState.FROZEN],
    EscrowState.FROZEN: [
        EscrowState.RELEASED,
        EscrowState.REFUNDED,
        EscrowState.READY_TO_RELEASE,
    ],
    EscrowState.RELEASED: [],
    EscrowState.REFUNDED: [],
    EscrowState.CANCELLED: [],
}


class ReleaseCondition(models.TextChoices):
    BUYER_CONFIRMED = "BUYER_CONFIRMED", "Confirmation acheteur"
    ADMIN_VALIDATED = "ADMIN_VALIDATED", "Validation admin"
    TRANSIT_CONFIRMED = "TRANSIT_CONFIRMED", "Confirmation transitaire"
    PURCHASE_PROOF = "PURCHASE_PROOF", "Preuve d'achat"
    AUTO_RELEASE_TIMER = "AUTO_RELEASE_TIMER", "Libération automatique (timer)"
    DISPUTE_RESOLVED = "DISPUTE_RESOLVED", "Litige résolu"


class EscrowHold(models.Model):
    """
    An escrow hold — funds locked pending release conditions.
    One hold per purpose per entity (e.g., one ORDER_PAYMENT escrow per order).
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    purpose = models.CharField(max_length=24, choices=EscrowPurpose.choices, db_index=True)
    state = models.CharField(
        max_length=24, choices=EscrowState.choices,
        default=EscrowState.PENDING, db_index=True
    )
    beneficiary = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="escrow_holds_as_beneficiary",
        help_text="Who receives funds on release",
    )
    payer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="escrow_holds_as_payer",
        help_text="Who funded this escrow",
    )
    currency = models.CharField(max_length=3, default="XAF")
    amount = models.DecimalField(
        max_digits=14, decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))],
    )
    released_amount = models.DecimalField(
        max_digits=14, decimal_places=2, default=Decimal("0.00"),
    )
    commission_amount = models.DecimalField(
        max_digits=14, decimal_places=2, default=Decimal("0.00"),
    )
    # Reference to the domain entity (e.g., Order, Shipment)
    entity_type = models.CharField(max_length=60, db_index=True)
    entity_id = models.CharField(max_length=80, db_index=True)
    # Release conditions — all must be met before READY_TO_RELEASE
    required_conditions = models.JSONField(default=list)   # list of ReleaseCondition values
    met_conditions = models.JSONField(default=list)        # conditions already satisfied
    # Auto-release timer
    auto_release_at = models.DateTimeField(null=True, blank=True)
    # Freeze info
    frozen_reason = models.CharField(max_length=300, blank=True)
    frozen_at = models.DateTimeField(null=True, blank=True)
    frozen_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True,
        on_delete=models.SET_NULL, related_name="frozen_escrow_holds",
    )
    # Release info
    released_at = models.DateTimeField(null=True, blank=True)
    refunded_at = models.DateTimeField(null=True, blank=True)
    # Idempotency
    idempotency_key = models.CharField(max_length=120, unique=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["entity_type", "entity_id"], name="idx_escrow_entity"),
            models.Index(fields=["beneficiary", "state"], name="idx_escrow_beneficiary_state"),
            models.Index(fields=["state", "auto_release_at"], name="idx_escrow_auto_release"),
        ]

    @property
    def remaining_amount(self) -> Decimal:
        return self.amount - self.released_amount

    @property
    def all_conditions_met(self) -> bool:
        required = set(self.required_conditions)
        met = set(self.met_conditions)
        return required.issubset(met)

    def can_transition_to(self, target: str) -> bool:
        return target in ESCROW_TRANSITIONS.get(self.state, [])

    def __str__(self) -> str:
        return f"EscrowHold({self.purpose}, {self.amount} {self.currency}, {self.state})"


class EscrowRelease(models.Model):
    """
    Records each release (partial or full) from an EscrowHold.
    Immutable after creation.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    escrow_hold = models.ForeignKey(EscrowHold, on_delete=models.PROTECT, related_name="releases")
    released_to = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="received_escrow_releases",
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    commission = models.DecimalField(max_digits=14, decimal_places=2, default=Decimal("0.00"))
    release_reason = models.CharField(max_length=300, blank=True)
    released_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="processed_escrow_releases",
    )
    ledger_transaction_id = models.UUIDField(null=True, blank=True)
    idempotency_key = models.CharField(max_length=120, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]


class EscrowTransition(models.Model):
    """
    Immutable log of every state transition of an EscrowHold.
    Used for compliance, audit, and dispute investigation.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    escrow_hold = models.ForeignKey(EscrowHold, on_delete=models.CASCADE, related_name="transitions")
    from_state = models.CharField(max_length=24)
    to_state = models.CharField(max_length=24)
    triggered_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="triggered_escrow_transitions",
    )
    reason = models.CharField(max_length=300, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
