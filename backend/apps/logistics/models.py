import hashlib
from django.conf import settings
from django.db import models

from apps.orders.models import Order


class TransportProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="transport_profile")
    company_name = models.CharField(max_length=180)
    air_price_per_kg = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    sea_price_per_kg = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    coverage_countries = models.CharField(max_length=120, default="CM")
    operating_zones = models.TextField(blank=True)
    vehicle_count = models.PositiveIntegerField(default=0)
    vehicle_types = models.CharField(max_length=240, blank=True)
    max_payload_kg = models.PositiveIntegerField(default=0)
    average_eta_days = models.PositiveIntegerField(default=0)
    has_customs_license = models.BooleanField(default=False)
    insurance_valid_until = models.DateField(null=True, blank=True)
    rating = models.DecimalField(max_digits=3, decimal_places=2, default=0)
    completed_shipments = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)


class ShipmentStatus(models.TextChoices):
    PICKUP_PENDING = "PICKUP_PENDING", "En attente de collecte"
    IN_TRANSIT = "IN_TRANSIT", "En transit"
    AT_CUSTOMS = "AT_CUSTOMS", "En douane"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY", "En cours de livraison"
    DELIVERED = "DELIVERED", "Livre"
    DISPUTED = "DISPUTED", "En litige"
    CANCELLED = "CANCELLED", "Annule"


class TransportMode(models.TextChoices):
    AIR = "AIR", "Avion"
    SEA = "SEA", "Bateau"


class Shipment(models.Model):
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="shipment")
    buyer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="shipments_as_buyer")
    seller = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="shipments_as_seller")
    transit_agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="shipments_as_agent"
    )
    pickup_address = models.CharField(max_length=250)
    dropoff_address = models.CharField(max_length=250)
    country_code = models.CharField(max_length=4, default="CM")
    transport_mode = models.CharField(max_length=8, choices=TransportMode.choices, default=TransportMode.SEA)
    shipping_fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    status = models.CharField(max_length=20, choices=ShipmentStatus.choices, default=ShipmentStatus.PICKUP_PENDING)
    expected_delivery_at = models.DateTimeField(null=True, blank=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    # 48-hour window after delivery during which quality/quantity disputes may be opened.
    contest_deadline = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]


class QuoteStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    ACCEPTED = "ACCEPTED", "Accepte"
    REJECTED = "REJECTED", "Rejete"


class TransportQuote(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name="quotes")
    transit_agent = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="transport_quotes")
    fee = models.DecimalField(max_digits=12, decimal_places=2)
    eta_days = models.PositiveIntegerField(default=2)
    notes = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=QuoteStatus.choices, default=QuoteStatus.PENDING)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["shipment", "transit_agent"],
                name="uniq_quote_per_agent_per_shipment",
            ),
        ]


class ShipmentEvent(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name="events")
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    status = models.CharField(max_length=20, choices=ShipmentStatus.choices)
    note = models.CharField(max_length=240, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class DeliveryProof(models.Model):
    shipment = models.OneToOneField(Shipment, on_delete=models.CASCADE, related_name="delivery_proof")
    otp = models.CharField(max_length=10, blank=True)
    photo = models.ImageField(upload_to="delivery-proofs/", blank=True, null=True)
    signed_by = models.CharField(max_length=120, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    validated = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)


# ---------------------------------------------------------------------------
# Chain of Custody — immutable log of every physical handover
# ---------------------------------------------------------------------------

class CustodyEventType(models.TextChoices):
    PICKUP = "PICKUP", "Prise en charge par le transporteur"
    WAREHOUSE_IN = "WAREHOUSE_IN", "Entree en entrepot"
    WAREHOUSE_OUT = "WAREHOUSE_OUT", "Sortie d'entrepot"
    HANDOVER = "HANDOVER", "Transfert de garde"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY", "Depart pour livraison"
    DELIVERED = "DELIVERED", "Remis au destinataire"


class CustodyEvent(models.Model):
    """
    Immutable record of each physical custody transfer.
    The last party who logged a custody event without a subsequent log
    is presumed responsible for any loss or damage.
    integrity_hash = SHA-256(shipment_id:event_type:actor_id:scanned_at_iso)
    """
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name="custody_events")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="logged_custody_events",
    )
    event_type = models.CharField(max_length=20, choices=CustodyEventType.choices)
    photo = models.ImageField(upload_to="custody-events/", blank=True, null=True)
    location = models.CharField(max_length=250, blank=True)
    notes = models.CharField(max_length=500, blank=True)
    integrity_hash = models.CharField(max_length=64, blank=True, db_index=True)
    scanned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["scanned_at"]

    @staticmethod
    def compute_hash(shipment_id: int, event_type: str, actor_id, scanned_at_iso: str) -> str:
        raw = f"{shipment_id}:{event_type}:{actor_id}:{scanned_at_iso}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Disputes
# ---------------------------------------------------------------------------

class DisputeType(models.TextChoices):
    # Qualite / conformite produit
    QUALITY_DEFECT = "QUALITY_DEFECT", "Marchandise de mauvaise qualite"
    WRONG_QUANTITY = "WRONG_QUANTITY", "Quantite incomplete"
    COUNTERFEIT = "COUNTERFEIT", "Produit contrefait"
    # Mauvaise foi acheteur
    FALSE_NON_RECEIPT = "FALSE_NON_RECEIPT", "Fausse declaration de non-reception"
    USED_THEN_DISPUTED = "USED_THEN_DISPUTED", "Produit utilise puis conteste"
    # Livraison
    DELIVERY_DELAY = "DELIVERY_DELAY", "Retard de livraison"
    LOST_PARCEL = "LOST_PARCEL", "Colis perdu"
    WRONG_RECIPIENT = "WRONG_RECIPIENT", "Livraison au mauvais destinataire"
    # Escrow
    ESCROW_BLOCKED = "ESCROW_BLOCKED", "Fonds bloques trop longtemps"
    PREMATURE_RELEASE = "PREMATURE_RELEASE", "Liberation prematuree des fonds"
    WALLET_FROZEN = "WALLET_FROZEN", "Gel de wallet injustifie"
    # Financiers
    DOUBLE_CHARGE = "DOUBLE_CHARGE", "Double debit Mobile Money"
    WITHDRAWAL_ERROR = "WITHDRAWAL_ERROR", "Erreur de retrait wallet"
    CHARGEBACK = "CHARGEBACK", "Chargeback bancaire"
    # KYC / Conformite
    FAKE_DOCUMENTS = "FAKE_DOCUMENTS", "Faux documents vendeur"
    UNJUST_SUSPENSION = "UNJUST_SUSPENSION", "Suspension injustifiee"
    # Logistique
    DAMAGED_GOODS = "DAMAGED_GOODS", "Marchandise endommagee durant transport"
    INTERNAL_THEFT = "INTERNAL_THEFT", "Vol interne"
    FALSE_TRACKING = "FALSE_TRACKING", "Fausse mise a jour de suivi"
    # Publicite / Boost
    MISLEADING_AD = "MISLEADING_AD", "Publicite trompeuse"
    FAKE_STATS = "FAKE_STATS", "Faux chiffres de visibilite campagne"
    # Donnees personnelles
    DATA_BREACH = "DATA_BREACH", "Fuite de donnees KYC"
    UNAUTHORIZED_ACCESS = "UNAUTHORIZED_ACCESS", "Acces non autorise au compte"
    # Entre vendeurs
    CATALOG_COPY = "CATALOG_COPY", "Copie de catalogue"
    FAKE_REVIEWS = "FAKE_REVIEWS", "Faux avis negatifs"
    # Internes plateforme
    MODERATION_BIAS = "MODERATION_BIAS", "Favoritisme dans la moderation"
    HISTORY_TAMPER = "HISTORY_TAMPER", "Modification de l'historique"
    # Reglementaires
    FINANCIAL_REGULATION = "FINANCIAL_REGULATION", "Activite financiere non autorisee"
    TAX_COMPLIANCE = "TAX_COMPLIANCE", "Non-conformite fiscale"
    # Multi-acteurs
    MULTI_ACTOR = "MULTI_ACTOR", "Responsabilite multi-acteurs indeterminee"
    # Generique
    OTHER = "OTHER", "Autre (a preciser dans les details)"


# These types require the dispute to be opened within the 48-hour contest window.
DISPUTE_TYPES_CONTEST_WINDOW = frozenset({
    DisputeType.QUALITY_DEFECT,
    DisputeType.WRONG_QUANTITY,
    DisputeType.DAMAGED_GOODS,
    DisputeType.USED_THEN_DISPUTED,
})

# These types are immediately escalated to GENERAL_ADMIN and trigger protective actions.
DISPUTE_TYPES_CRITICAL = frozenset({
    DisputeType.COUNTERFEIT,
    DisputeType.FAKE_DOCUMENTS,
    DisputeType.DATA_BREACH,
    DisputeType.INTERNAL_THEFT,
    DisputeType.HISTORY_TAMPER,
    DisputeType.FINANCIAL_REGULATION,
})

# Seller accuses the BUYER (bad-faith buyer behaviour).
DISPUTE_TYPES_AGAINST_BUYER = frozenset({
    DisputeType.FALSE_NON_RECEIPT,
    DisputeType.USED_THEN_DISPUTED,
    DisputeType.CHARGEBACK,
    DisputeType.FAKE_REVIEWS,
})

# Seller accuses the TRANSIT AGENT (logistics misconduct).
DISPUTE_TYPES_AGAINST_TRANSIT = frozenset({
    DisputeType.INTERNAL_THEFT,
    DisputeType.FALSE_TRACKING,
    DisputeType.DAMAGED_GOODS,
    DisputeType.LOST_PARCEL,
    DisputeType.WRONG_RECIPIENT,
})

# Buyer accuses the SELLER (product / commerce disputes).
DISPUTE_TYPES_AGAINST_SELLER = frozenset({
    DisputeType.QUALITY_DEFECT,
    DisputeType.WRONG_QUANTITY,
    DisputeType.COUNTERFEIT,
    DisputeType.MISLEADING_AD,
    DisputeType.FAKE_DOCUMENTS,
    DisputeType.DELIVERY_DELAY,
    DisputeType.FAKE_STATS,
    DisputeType.CATALOG_COPY,
})

# Buyer accuses the TRANSIT AGENT (logistics misconduct).
DISPUTE_TYPES_BUYER_VS_TRANSIT = frozenset({
    DisputeType.LOST_PARCEL,
    DisputeType.DAMAGED_GOODS,
    DisputeType.WRONG_RECIPIENT,
    DisputeType.FALSE_TRACKING,
})

# Platform-level disputes — no individual accused party; platform itself is responsible.
DISPUTE_TYPES_PLATFORM = frozenset({
    DisputeType.WALLET_FROZEN,
    DisputeType.WITHDRAWAL_ERROR,
    DisputeType.UNJUST_SUSPENSION,
    DisputeType.PREMATURE_RELEASE,
    DisputeType.DATA_BREACH,
    DisputeType.UNAUTHORIZED_ACCESS,
    DisputeType.HISTORY_TAMPER,
    DisputeType.FINANCIAL_REGULATION,
    DisputeType.TAX_COMPLIANCE,
    DisputeType.MODERATION_BIAS,
    DisputeType.ESCROW_BLOCKED,
    DisputeType.DOUBLE_CHARGE,
    DisputeType.MULTI_ACTOR,
})


class DisputeStatus(models.TextChoices):
    OPEN = "OPEN", "Ouvert"
    UNDER_REVIEW = "UNDER_REVIEW", "En traitement"
    INSPECTION_PENDING = "INSPECTION_PENDING", "Inspection physique en cours"
    APPEAL_REQUESTED = "APPEAL_REQUESTED", "Appel en cours"
    RESOLVED = "RESOLVED", "Resolu"
    CLOSED_NO_ACTION = "CLOSED_NO_ACTION", "Ferme sans action"


class ShipmentDispute(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name="disputes")
    opened_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="opened_disputes")
    accused_party = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name="disputes_as_accused",
    )

    dispute_type = models.CharField(
        max_length=30, choices=DisputeType.choices, default=DisputeType.QUALITY_DEFECT
    )
    reason = models.CharField(max_length=200)
    details = models.TextField()
    status = models.CharField(max_length=20, choices=DisputeStatus.choices, default=DisputeStatus.OPEN)
    sla_due_at = models.DateTimeField(null=True, blank=True)

    # Legacy single-file evidence — kept for backward compat; new evidence uses DisputeEvidence
    evidence_file = models.FileField(upload_to="shipment-disputes/", blank=True, null=True)

    # SHA-256 of serialized chat-room messages at dispute-open time (tamper detection)
    chat_integrity_hash = models.CharField(max_length=64, blank=True)

    # Physical inspection workflow
    inspection_required = models.BooleanField(default=False)
    inspection_requested_at = models.DateTimeField(null=True, blank=True)
    inspector_report = models.FileField(upload_to="dispute-inspections/", blank=True, null=True)
    inspector_report_uploaded_at = models.DateTimeField(null=True, blank=True)

    # Guarantee fund — platform absorbs loss when no actor can be held responsible
    guarantee_fund_activated = models.BooleanField(default=False)
    guarantee_fund_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    guarantee_fund_activated_at = models.DateTimeField(null=True, blank=True)

    # Last confirmed custody holder (populated from custody chain analysis)
    last_custody_holder = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="disputes_as_last_holder",
    )

    # Appeal workflow — appeal reviewer must differ from initial decider
    appeal_requested = models.BooleanField(default=False)
    appeal_requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="appeal_requested_disputes",
    )
    appeal_requested_at = models.DateTimeField(null=True, blank=True)
    appeal_reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="appeal_reviewed_disputes",
    )
    appeal_decision = models.TextField(blank=True)
    appeal_resolved_at = models.DateTimeField(null=True, blank=True)

    escalation_count = models.PositiveSmallIntegerField(default=0)
    is_multi_actor = models.BooleanField(default=False)

    # Admin resolution
    admin_decision = models.CharField(max_length=20, blank=True)  # REFUND_BUYER | RELEASE_SELLER | SPLIT
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="decided_disputes",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    resolution_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]


# ---------------------------------------------------------------------------
# Evidence — multiple files per dispute, each integrity-hashed
# ---------------------------------------------------------------------------

class DisputeEvidenceType(models.TextChoices):
    PHOTO = "PHOTO", "Photo"
    VIDEO = "VIDEO", "Video"
    DOCUMENT = "DOCUMENT", "Document"
    SCREENSHOT = "SCREENSHOT", "Capture d'ecran"
    INSPECTION_REPORT = "INSPECTION_REPORT", "Rapport d'inspection"


class DisputeEvidence(models.Model):
    """
    Evidence is immutable once uploaded (only GENERAL_ADMIN may delete).
    file_integrity_hash = SHA-256(file bytes) computed at upload time.
    """
    dispute = models.ForeignKey(ShipmentDispute, on_delete=models.CASCADE, related_name="evidences")
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="uploaded_dispute_evidences",
    )
    file = models.FileField(upload_to="dispute-evidences/")
    evidence_type = models.CharField(
        max_length=20, choices=DisputeEvidenceType.choices, default=DisputeEvidenceType.DOCUMENT
    )
    description = models.CharField(max_length=300, blank=True)
    file_integrity_hash = models.CharField(max_length=64, blank=True, db_index=True)
    file_size_bytes = models.PositiveIntegerField(default=0)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["uploaded_at"]


class TransitAgentRating(models.Model):
    shipment = models.OneToOneField(Shipment, on_delete=models.CASCADE, related_name="transit_rating")
    transit_agent = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="ratings")
    buyer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="transit_agent_ratings")
    score = models.PositiveIntegerField()  # 1..5
    review = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
