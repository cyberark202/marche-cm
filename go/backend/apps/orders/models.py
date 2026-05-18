from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from apps.catalog.models import Product


class OrderStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    SOURCING = "SOURCING", "Sourcing fournisseur"
    SUPPLIER_VERIFIED = "SUPPLIER_VERIFIED", "Fournisseur verifie"
    ADMIN_APPROVED = "ADMIN_APPROVED", "Validation admin"
    SHIPPING = "SHIPPING", "En expédition"
    DISPUTED = "DISPUTED", "En litige"
    REFUNDED = "REFUNDED", "Remboursee"
    # Legacy statuses kept for compatibility with existing features/tests.
    CONFIRMED = "CONFIRMED", "Confirmee"
    DELIVERED = "DELIVERED", "Livree"
    COMPLETED = "COMPLETED", "Finalisee"
    CANCELLED = "CANCELLED", "Annulee"


class EscrowStatus(models.TextChoices):
    HELD = "HELD", "Bloque chez NotchPay"
    SPLIT_LOCKED = "SPLIT_LOCKED", "Split escrow bloque"
    PARTIALLY_RELEASED = "PARTIALLY_RELEASED", "Partiellement libere"
    FROZEN = "FROZEN", "Gele"
    REFUNDED = "REFUNDED", "Rembourse"
    RELEASED = "RELEASED", "Debloque au vendeur"


class OrderType(models.TextChoices):
    LOCAL = "LOCAL", "Locale"
    INTERNATIONAL = "INTERNATIONAL", "Internationale"


class Order(models.Model):
    buyer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="buyer_orders")
    seller = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="seller_orders")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="orders")
    quantity = models.PositiveIntegerField()
    join_grouping = models.BooleanField(default=False)
    preferred_transit_agent = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="preferred_transit_orders",
    )
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    total_price = models.DecimalField(max_digits=12, decimal_places=2)
    logistics_price = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    platform_commission_rate = models.DecimalField(max_digits=5, decimal_places=4, default=0)
    order_type = models.CharField(max_length=20, choices=OrderType.choices, default=OrderType.LOCAL)
    status = models.CharField(max_length=20, choices=OrderStatus.choices, default=OrderStatus.PENDING)
    escrow_status = models.CharField(max_length=20, choices=EscrowStatus.choices, default=EscrowStatus.HELD)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]


class EscrowType(models.TextChoices):
    LOCAL = "LOCAL", "Escrow local"
    SUPPLIER = "SUPPLIER", "Escrow fournisseur"
    LOGISTICS = "LOGISTICS", "Escrow logistique"


class EscrowLifecycleStatus(models.TextChoices):
    LOCKED = "LOCKED", "Bloque"
    READY = "READY", "Pret a etre libere"
    PAYOUT_PENDING = "PAYOUT_PENDING", "Payout en attente"
    RELEASED = "RELEASED", "Libere"
    FROZEN = "FROZEN", "Gele"
    REFUNDED = "REFUNDED", "Rembourse"


class OrderEscrow(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="escrows")
    escrow_type = models.CharField(max_length=16, choices=EscrowType.choices)
    beneficiary = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="beneficiary_escrows",
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    released_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    status = models.CharField(max_length=20, choices=EscrowLifecycleStatus.choices, default=EscrowLifecycleStatus.LOCKED)
    release_conditions = models.JSONField(default=dict, blank=True)
    requires_transit_confirmation = models.BooleanField(default=False)
    requires_purchase_proof = models.BooleanField(default=False)
    requires_admin_validation = models.BooleanField(default=False)
    requires_buyer_confirmation = models.BooleanField(default=False)
    transit_confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="transit_confirmed_escrows",
    )
    transit_confirmed_at = models.DateTimeField(null=True, blank=True)
    purchase_proof = models.FileField(upload_to="escrow-proofs/", blank=True, null=True)
    purchase_proof_hash = models.CharField(max_length=64, blank=True, db_index=True)
    purchase_proof_uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="escrow_proof_uploads",
    )
    purchase_proof_uploaded_at = models.DateTimeField(null=True, blank=True)
    admin_validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="admin_validated_escrows",
    )
    admin_validated_at = models.DateTimeField(null=True, blank=True)
    buyer_confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="buyer_confirmed_escrows",
    )
    buyer_confirmed_at = models.DateTimeField(null=True, blank=True)
    frozen_reason = models.CharField(max_length=240, blank=True)
    released_at = models.DateTimeField(null=True, blank=True)
    refunded_at = models.DateTimeField(null=True, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["created_at"]
        constraints = [
            models.UniqueConstraint(fields=["order", "escrow_type"], name="uniq_order_escrow_type"),
        ]


class LogisticsVerification(models.Model):
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="logistics_verification")
    supplier_escrow = models.OneToOneField(
        OrderEscrow,
        on_delete=models.CASCADE,
        related_name="logistics_verification",
        null=True,
        blank=True,
    )
    transit_agent_confirmed = models.BooleanField(default=False)
    transit_agent_confirmed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="supplier_confirmations",
    )
    transit_agent_confirmed_at = models.DateTimeField(null=True, blank=True)
    purchase_proof = models.FileField(upload_to="supplier-proof/", null=True, blank=True)
    purchase_proof_hash = models.CharField(max_length=64, blank=True, db_index=True)
    purchase_proof_uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="supplier_proof_uploads",
    )
    purchase_proof_uploaded_at = models.DateTimeField(null=True, blank=True)
    admin_validated = models.BooleanField(default=False)
    admin_validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="supplier_admin_validations",
    )
    admin_validated_at = models.DateTimeField(null=True, blank=True)
    fraud_flagged = models.BooleanField(default=False)
    fraud_reason = models.CharField(max_length=240, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def all_conditions_met(self) -> bool:
        return bool(self.transit_agent_confirmed and self.purchase_proof and self.admin_validated and not self.fraud_flagged)


class OrderReview(models.Model):
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="review")
    buyer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="order_reviews")
    seller = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="received_order_reviews")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="order_reviews")
    rating = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    comment = models.TextField(blank=True)
    is_verified_purchase = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
