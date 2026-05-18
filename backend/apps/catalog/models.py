from decimal import Decimal
import random
import string

from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models


class ProductCategory(models.Model):
    name = models.CharField(max_length=120, unique=True)

    def __str__(self) -> str:
        return self.name


class Product(models.Model):
    REF_PREFIX = "PRD"
    seller = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="products")
    reference_code = models.CharField(max_length=24, unique=True, blank=True, null=True, db_index=True)
    title = models.CharField(max_length=200)
    description = models.TextField()
    brand = models.CharField(max_length=120)
    category = models.ForeignKey(ProductCategory, on_delete=models.SET_NULL, null=True, blank=True)
    min_order_qty = models.PositiveIntegerField(default=1)
    max_order_qty = models.PositiveIntegerField(default=1)
    price_for_min_qty = models.DecimalField(max_digits=12, decimal_places=2)
    price_for_max_qty = models.DecimalField(max_digits=12, decimal_places=2)
    weight_kg = models.DecimalField(
        max_digits=10,
        decimal_places=3,
        null=True,
        blank=True,
        validators=[MinValueValidator(Decimal("0.001"))],
    )
    image = models.ImageField(upload_to="products/images/", blank=True, null=True)
    video = models.FileField(upload_to="products/videos/", blank=True, null=True)
    video_duration_seconds = models.PositiveIntegerField(
        default=0, validators=[MinValueValidator(0), MaxValueValidator(180)]
    )
    available_qty = models.PositiveIntegerField(null=True, blank=True)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    colors = models.CharField(max_length=300, blank=True)
    tags = models.CharField(max_length=300, blank=True)
    variant_options = models.JSONField(default=list, blank=True)
    bundle_items = models.JSONField(default=list, blank=True)
    allows_group_campaign = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.title

    @classmethod
    def _generate_reference_code(cls) -> str:
        alphabet = string.ascii_uppercase + string.digits
        return f"{cls.REF_PREFIX}-{''.join(random.choice(alphabet) for _ in range(10))}"

    @classmethod
    def _next_available_reference_code(cls) -> str:
        for _ in range(50):
            candidate = cls._generate_reference_code()
            if not cls.objects.filter(reference_code=candidate).exists():
                return candidate
        raise RuntimeError("Impossible de generer un code de reference produit unique.")

    def save(self, *args, **kwargs):
        if not self.reference_code:
            self.reference_code = self._next_available_reference_code()
        super().save(*args, **kwargs)


class ProductStatsSnapshot(models.Model):
    product = models.OneToOneField(Product, on_delete=models.CASCADE, related_name="stats")
    total_orders = models.PositiveIntegerField(default=0)
    avg_purchase_price = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    updated_at = models.DateTimeField(auto_now=True)


class BuyerPreferenceProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="buyer_preference_profile")
    keyword_weights = models.JSONField(default=dict, blank=True)
    locality_weights = models.JSONField(default=dict, blank=True)
    preferred_price_sum = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    preferred_price_count = models.PositiveIntegerField(default=0)
    updated_at = models.DateTimeField(auto_now=True)


class BuyerProductInteraction(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="buyer_product_interactions")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="buyer_interactions")
    view_count = models.PositiveIntegerField(default=0)
    last_viewed_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "product"], name="unique_buyer_product_interaction"),
        ]


class ProductFavorite(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="product_favorites")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="favorites")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(fields=["user", "product"], name="unique_user_product_favorite"),
        ]


class VideoLike(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="video_likes")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="video_likes")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "product"], name="unique_video_like"),
        ]


class VideoComment(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="video_comments")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="video_comments")
    message = models.TextField(max_length=500)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class SavedProductFilter(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="saved_product_filters")
    name = models.CharField(max_length=80)
    query = models.CharField(max_length=120, blank=True)
    category = models.CharField(max_length=80, blank=True)
    country_code = models.CharField(max_length=8, blank=True)
    min_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    max_price = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    only_verified = models.BooleanField(default=False)
    sort_mode = models.CharField(max_length=20, default="relevance")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
