from django.conf import settings
from django.db import models

from apps.analytics.models import RFQOffer
from apps.catalog.models import Product


class PriceAlert(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="price_alerts")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="price_alerts")
    target_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    notify_on_back_in_stock = models.BooleanField(default=True)
    is_active = models.BooleanField(default=True)
    last_notified_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    triggered_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class CounterOfferStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    ACCEPTED = "ACCEPTED", "Accepte"
    REJECTED = "REJECTED", "Rejete"


class RFQCounterOffer(models.Model):
    rfq_offer = models.ForeignKey(RFQOffer, on_delete=models.CASCADE, related_name="counter_offers")
    creator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="created_counter_offers")
    target_price = models.DecimalField(max_digits=12, decimal_places=2)
    lead_time_days = models.PositiveIntegerField(default=2)
    note = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=CounterOfferStatus.choices, default=CounterOfferStatus.PENDING)
    expires_at = models.DateTimeField(null=True, blank=True)
    decided_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class ApprovalRequestStatus(models.TextChoices):
    PENDING = "PENDING", "En attente"
    APPROVED = "APPROVED", "Approuve"
    REJECTED = "REJECTED", "Rejete"


class WalletApprovalRequest(models.Model):
    requester = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="wallet_approval_requests")
    approver = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="wallet_approval_decisions",
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reason = models.CharField(max_length=200)
    status = models.CharField(max_length=10, choices=ApprovalRequestStatus.choices, default=ApprovalRequestStatus.PENDING)
    decided_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class LoyaltyTier(models.TextChoices):
    BRONZE = "BRONZE", "Bronze"
    SILVER = "SILVER", "Silver"
    GOLD = "GOLD", "Gold"


class LoyaltyAccount(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="loyalty_account")
    points_balance = models.IntegerField(default=0)
    tier = models.CharField(max_length=10, choices=LoyaltyTier.choices, default=LoyaltyTier.BRONZE)
    updated_at = models.DateTimeField(auto_now=True)


class LoyaltyTransactionType(models.TextChoices):
    EARN = "EARN", "Gain"
    REDEEM = "REDEEM", "Consommation"
    ADJUST = "ADJUST", "Ajustement"


class LoyaltyTransaction(models.Model):
    account = models.ForeignKey(LoyaltyAccount, on_delete=models.CASCADE, related_name="transactions")
    action_type = models.CharField(max_length=10, choices=LoyaltyTransactionType.choices)
    points = models.IntegerField()
    reason = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class PartnerApiKey(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="partner_api_keys")
    name = models.CharField(max_length=120)
    key_prefix = models.CharField(max_length=16)
    key_hash = models.CharField(max_length=128)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]


class WebhookSubscription(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="webhook_subscriptions")
    topic = models.CharField(max_length=40)
    endpoint_url = models.URLField(max_length=500)
    secret = models.CharField(max_length=120, blank=True)
    is_active = models.BooleanField(default=True)
    last_delivery_status = models.CharField(max_length=40, blank=True)
    last_delivered_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
