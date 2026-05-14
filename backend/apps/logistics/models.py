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


class DisputeStatus(models.TextChoices):
    OPEN = "OPEN", "Ouvert"
    UNDER_REVIEW = "UNDER_REVIEW", "En traitement"
    RESOLVED = "RESOLVED", "Resolu"


class ShipmentDispute(models.Model):
    shipment = models.ForeignKey(Shipment, on_delete=models.CASCADE, related_name="disputes")
    opened_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="opened_disputes")
    reason = models.CharField(max_length=200)
    details = models.TextField()
    status = models.CharField(max_length=15, choices=DisputeStatus.choices, default=DisputeStatus.OPEN)
    sla_due_at = models.DateTimeField(null=True, blank=True)
    evidence_file = models.FileField(upload_to="shipment-disputes/", blank=True, null=True)
    admin_decision = models.CharField(max_length=20, blank=True)  # REFUND_BUYER, RELEASE_SELLER, SPLIT
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="decided_disputes"
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    resolution_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]


class TransitAgentRating(models.Model):
    shipment = models.OneToOneField(Shipment, on_delete=models.CASCADE, related_name="transit_rating")
    transit_agent = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="ratings")
    buyer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="transit_agent_ratings")
    score = models.PositiveIntegerField()  # 1..5
    review = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
