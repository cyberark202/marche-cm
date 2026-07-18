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


class ListingType(models.TextChoices):
    PHYSICAL = "PHYSICAL", "Produit physique"
    SERVICE = "SERVICE", "Service"
    DIGITAL = "DIGITAL", "Produit numerique"
    JOB = "JOB", "Offre d'emploi"


# Types sans logistique : pas d'expedition, pas d'escrow livreur (docs 03/12).
LISTING_TYPES_WITHOUT_LOGISTICS = frozenset({ListingType.SERVICE, ListingType.DIGITAL, ListingType.JOB})


class ProductStatus(models.TextChoices):
    DRAFT = "DRAFT", "Brouillon"
    PUBLISHED = "PUBLISHED", "Publie"
    SUSPENDED = "SUSPENDED", "Suspendu"
    REJECTED = "REJECTED", "Refuse"
    ARCHIVED = "ARCHIVED", "Archive"


# Statuts poses par la moderation admin : le vendeur ne peut pas les lever
# lui-meme (docs 12/22).
PRODUCT_ADMIN_LOCKED_STATUSES = frozenset({ProductStatus.SUSPENDED, ProductStatus.REJECTED})


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
    # Poster (vignette) extrait automatiquement de la video a la publication.
    # Sert d'image d'attente avant chargement du flux dans le feed.
    video_poster = models.ImageField(upload_to="products/posters/", blank=True, null=True)
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
    # Type d'annonce (docs 03 R13 / 12) : les services, produits numeriques et
    # offres d'emploi n'ont pas de flux logistique.
    listing_type = models.CharField(max_length=10, choices=ListingType.choices, default=ListingType.PHYSICAL)
    # Machine a etats produit (docs 12/22). Publication immediate + moderation
    # a posteriori : le produit nait PUBLISHED, l'admin peut le suspendre ou le
    # refuser apres coup. `is_active` reste le miroir legacy (clients existants).
    status = models.CharField(max_length=12, choices=ProductStatus.choices, default=ProductStatus.PUBLISHED)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.title

    def _sync_status_and_active(self) -> None:
        """Synchronise le miroir legacy `is_active` avec la machine a etats.

        - Un statut pose par l'admin (SUSPENDED/REJECTED) force is_active=False
          et ne peut pas etre leve via le toggle legacy.
        - Le toggle legacy is_active=False sur un produit publie = archivage
          (masquer / soft-delete historique).
        - is_active=True sur un brouillon/archive = publication.
        """
        if self.status in PRODUCT_ADMIN_LOCKED_STATUSES:
            self.is_active = False
        elif self.status == ProductStatus.PUBLISHED and not self.is_active:
            self.status = ProductStatus.ARCHIVED
        elif self.status in {ProductStatus.ARCHIVED, ProductStatus.DRAFT} and self.is_active:
            self.status = ProductStatus.PUBLISHED
        elif self.status == ProductStatus.PUBLISHED:
            self.is_active = True
        else:
            self.is_active = False

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
        self._sync_status_and_active()
        update_fields = kwargs.get("update_fields")
        if update_fields:
            merged = set(update_fields)
            if merged & {"is_active", "status"}:
                merged.update({"is_active", "status"})
            kwargs["update_fields"] = list(merged)
        super().save(*args, **kwargs)


class ProductImage(models.Model):
    """Audit ref: [BUG-S1] Galerie multi-images d'un produit.

    Le `Product.image` historique reste l'image principale (vignette /
    rétro-compatibilité). Cette table porte les images supplémentaires, jusqu'à
    `MAX_IMAGES_PER_PRODUCT` au total. L'ordre d'affichage suit `position`.
    """

    MAX_IMAGES_PER_PRODUCT = 10

    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="images")
    image = models.ImageField(upload_to="products/images/")
    position = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["position", "id"]

    def __str__(self) -> str:
        return f"Image #{self.position} de {self.product_id}"


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


class SellerFollow(models.Model):
    """Abonnement d'un utilisateur a un vendeur (relation user -> seller).

    Sert au bouton « S'abonner » du feed video. Un vendeur ne peut pas se
    suivre lui-meme (verifie cote vue).
    """

    follower = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="seller_follows"
    )
    seller = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="follower_links"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["follower", "seller"], name="unique_seller_follow"),
        ]


class VideoComment(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="video_comments")
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="video_comments")
    message = models.TextField(max_length=500)
    # Réponse à un commentaire (fil à 1 niveau, façon TikTok). CASCADE : la
    # suppression d'un commentaire emporte ses réponses.
    parent = models.ForeignKey("self", null=True, blank=True, on_delete=models.CASCADE, related_name="replies")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class VideoCommentLike(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="video_comment_likes")
    comment = models.ForeignKey(VideoComment, on_delete=models.CASCADE, related_name="likes")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "comment"], name="unique_video_comment_like"),
        ]


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
