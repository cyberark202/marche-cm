from django.conf import settings
from django.db import models

from apps.catalog.models import Product


class GroupCampaign(models.Model):
    wholesaler = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="campaigns")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="campaigns")
    target_quantity = models.PositiveIntegerField()
    current_quantity = models.PositiveIntegerField(default=0)
    is_open = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)


class RFQStatus(models.TextChoices):
    OPEN = "OPEN", "Ouvert"
    CLOSED = "CLOSED", "Ferme"


class RequestForQuotation(models.Model):
    buyer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rfqs")
    product_name = models.CharField(max_length=180)
    quantity = models.PositiveIntegerField()
    target_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    destination_city = models.CharField(max_length=120)
    country_code = models.CharField(max_length=4, default="CM")
    notes = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=RFQStatus.choices, default=RFQStatus.OPEN)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class RFQOffer(models.Model):
    rfq = models.ForeignKey(RequestForQuotation, on_delete=models.CASCADE, related_name="offers")
    seller = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rfq_offers")
    price = models.DecimalField(max_digits=12, decimal_places=2)
    lead_time_days = models.PositiveIntegerField(default=2)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
