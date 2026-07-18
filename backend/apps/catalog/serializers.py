from rest_framework import serializers
from django.conf import settings

from apps.accounts.upload_security import scrub_image_metadata, validate_uploaded_file
from apps.accounts.models import UserRole
from core.text_sanitize import redact_links
from .models import Product, ProductCategory, ProductFavorite, ProductImage, SavedProductFilter, VideoComment, VideoLike
from .video_poster import generate_video_poster
from .video_probe import validate_video_stream


class ProductSerializer(serializers.ModelSerializer):
    seller_username = serializers.CharField(source="seller.username", read_only=True)
    seller_country_code = serializers.CharField(source="seller.country_code", read_only=True)
    seller_city = serializers.CharField(source="seller.city", read_only=True)
    seller_avatar_url = serializers.SerializerMethodField()
    seller_reference_code = serializers.CharField(source="seller.reference_code", read_only=True)
    seller_location_label = serializers.CharField(source="seller.location_label", read_only=True)
    seller_location_latitude = serializers.FloatField(source="seller.location_latitude", read_only=True)
    seller_location_longitude = serializers.FloatField(source="seller.location_longitude", read_only=True)
    seller_is_verified = serializers.SerializerMethodField()
    seller_trust_score = serializers.DecimalField(
        source="seller.trust_score", max_digits=4, decimal_places=2, read_only=True
    )
    category_name = serializers.CharField(write_only=True, required=False, allow_blank=True)
    category_label = serializers.CharField(source="category.name", read_only=True)
    is_active = serializers.BooleanField(read_only=True)
    status = serializers.CharField(read_only=True)
    price_for_min_qty = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True
    )
    price_for_max_qty = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True
    )
    images = serializers.SerializerMethodField()
    video_likes_count = serializers.SerializerMethodField()
    video_comments_count = serializers.SerializerMethodField()
    video_views_count = serializers.SerializerMethodField()
    is_video_liked = serializers.SerializerMethodField()
    is_following_seller = serializers.SerializerMethodField()
    is_favorited = serializers.SerializerMethodField()

    class Meta:
        model = Product
        fields = "__all__"
        read_only_fields = ("seller", "created_at", "reference_code")

    def get_seller_avatar_url(self, obj):
        if not obj.seller.avatar:
            return ""
        request = self.context.get("request")
        if request:
            return request.build_absolute_uri(obj.seller.avatar.url)
        return obj.seller.avatar.url

    def get_images(self, obj):
        request = self.context.get("request")
        result = []
        for img in obj.images.all():
            try:
                url = img.image.url
            except ValueError:
                continue
            if request:
                url = request.build_absolute_uri(url)
            result.append({"id": img.id, "url": url, "position": img.position})
        return result

    def get_video_likes_count(self, obj):
        return int(getattr(obj, "video_likes_count", 0) or 0)

    def get_video_comments_count(self, obj):
        return int(getattr(obj, "video_comments_count", 0) or 0)

    def get_video_views_count(self, obj):
        return int(getattr(obj, "video_views_count", 0) or 0)

    def get_is_video_liked(self, obj):
        return bool(getattr(obj, "is_video_liked", False))

    def get_is_following_seller(self, obj):
        return bool(getattr(obj, "is_following_seller", False))

    def get_is_favorited(self, obj):
        return bool(getattr(obj, "is_favorited", False))

    def get_seller_is_verified(self, obj):
        seller = obj.seller
        if seller.role in {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}:
            return any(d.status == "APPROVED" for d in seller.compliance_documents.all())
        return bool(seller.is_verified)

    _LEGACY_QTY_ALIASES = {"min_qty": "min_order_qty", "max_qty": "max_order_qty"}

    @classmethod
    def _apply_legacy_aliases(cls, data):
        try:
            mutable = data.copy()
        except (AttributeError, TypeError):
            return data
        for legacy, canonical in cls._LEGACY_QTY_ALIASES.items():
            if mutable.get(legacy) not in (None, "") and not mutable.get(canonical):
                mutable[canonical] = mutable.get(legacy)
        cat = mutable.get("category")
        if cat not in (None, "") and not str(cat).isdigit() and not mutable.get("category_name"):
            mutable["category_name"] = cat
            try:
                del mutable["category"]
            except Exception:
                mutable.pop("category", None)
        return mutable

    def to_internal_value(self, data):
        return super().to_internal_value(self._apply_legacy_aliases(data))

    def validate(self, attrs):
        request = self.context.get("request")
        role = request.user.role if request else None
        category = attrs.get("category", getattr(self.instance, "category", None))
        category_name = (attrs.get("category_name") or "").strip()
        if not category and not category_name:
            raise serializers.ValidationError("La categorie est obligatoire.")

        if role in UserRole.seller_roles():
            available_qty = attrs.get("available_qty", getattr(self.instance, "available_qty", None))
            unit_price = attrs.get("unit_price", getattr(self.instance, "unit_price", None))
            if available_qty is None:
                raise serializers.ValidationError(
                    "Le vendeur doit renseigner la quantite disponible."
                )
            if unit_price is None:
                raise serializers.ValidationError("Le vendeur doit renseigner le prix de l'article.")
            attrs["min_order_qty"] = 1
            attrs["max_order_qty"] = available_qty
            attrs["price_for_min_qty"] = unit_price
            attrs["price_for_max_qty"] = unit_price

        weight_kg = attrs.get("weight_kg", getattr(self.instance, "weight_kg", None))
        if self.instance is None and weight_kg is None:
            raise serializers.ValidationError("Le poids du produit (en Kg) est obligatoire.")
        if weight_kg is not None and weight_kg <= 0:
            raise serializers.ValidationError("Le poids du produit (en Kg) doit etre superieur a 0.")

        min_qty = attrs.get("min_order_qty", getattr(self.instance, "min_order_qty", 1))
        max_qty = attrs.get("max_order_qty", getattr(self.instance, "max_order_qty", 1))
        if min_qty > max_qty:
            raise serializers.ValidationError("La quantite min doit etre <= quantite max.")
        allows_group_campaign = attrs.get(
            "allows_group_campaign",
            getattr(self.instance, "allows_group_campaign", False),
        )
        if allows_group_campaign and request and request.user.role not in UserRole.seller_roles():
            raise serializers.ValidationError("Le regroupage est reserve aux vendeurs.")
        tags = (attrs.get("tags", getattr(self.instance, "tags", "")) or "").strip()
        variants = attrs.get("variant_options", getattr(self.instance, "variant_options", []))
        bundles = attrs.get("bundle_items", getattr(self.instance, "bundle_items", []))
        if not isinstance(variants, list):
            raise serializers.ValidationError("Les variantes doivent etre une liste JSON.")
        if not isinstance(bundles, list):
            raise serializers.ValidationError("Les bundles doivent etre une liste JSON.")
        video = attrs.get("video", getattr(self.instance, "video", None))
        description = (attrs.get("description", getattr(self.instance, "description", "")) or "").strip()
        if video and (not description or not tags):
            raise serializers.ValidationError(
                "Pour publier une video, ajoutez une description et des tags."
            )
        self._gallery_files = self._collect_gallery_files()
        return attrs

    MAX_GALLERY_IMAGES = ProductImage.MAX_IMAGES_PER_PRODUCT

    def _collect_gallery_files(self):
        """Lit `gallery_images` depuis request.FILES, valide chaque fichier
        (extension/MIME/magic-bytes/taille) et renvoie la liste scrubbee.
        Applique le plafond total (existantes + nouvelles)."""
        request = self.context.get("request")
        if request is None or not hasattr(request, "FILES"):
            return []
        files = request.FILES.getlist("gallery_images")
        if not files:
            return []
        existing = self.instance.images.count() if self.instance is not None else 0
        if existing + len(files) > self.MAX_GALLERY_IMAGES:
            raise serializers.ValidationError(
                f"Un produit ne peut pas depasser {self.MAX_GALLERY_IMAGES} images "
                f"(deja {existing}, +{len(files)} demandees)."
            )
        scrubbed = []
        for uploaded in files:
            validate_uploaded_file(
                uploaded,
                field_label="Image produit",
                allowed_extensions={".png", ".jpg", ".jpeg", ".webp"},
                max_mb=settings.MAX_UPLOAD_IMAGE_MB,
                allowed_content_types={"image/png", "image/jpeg", "image/webp"},
            )
            scrubbed.append(scrub_image_metadata(uploaded))
        return scrubbed

    def _save_gallery(self, product):
        files = getattr(self, "_gallery_files", None) or []
        if not files:
            return
        start = product.images.count()
        created = [
            ProductImage.objects.create(product=product, image=uploaded, position=start + idx)
            for idx, uploaded in enumerate(files)
        ]
        if not product.image and created:
            product.image = created[0].image
            product.save(update_fields=["image"])

    def validate_title(self, value):
        return redact_links(value)

    def validate_description(self, value):
        return redact_links(value)

    def validate_image(self, value):
        validate_uploaded_file(
            value,
            field_label="Image produit",
            allowed_extensions={".png", ".jpg", ".jpeg", ".webp"},
            max_mb=settings.MAX_UPLOAD_IMAGE_MB,
            allowed_content_types={"image/png", "image/jpeg", "image/webp"},
        )
        return scrub_image_metadata(value)

    def validate_video(self, value):
        validate_uploaded_file(
            value,
            field_label="Video produit",
            allowed_extensions={".mp4", ".mov", ".webm", ".m4v"},
            max_mb=settings.MAX_UPLOAD_VIDEO_MB,
            allowed_content_types={
                "video/mp4",
                "video/quicktime",
                "video/webm",
                "video/x-m4v",
                "application/octet-stream",
            },
        )
        self._probed_video_duration = validate_video_stream(value)
        return value

    def create(self, validated_data):
        category_name = (validated_data.pop("category_name", "") or "").strip()
        if category_name and not validated_data.get("category"):
            category, _ = ProductCategory.objects.get_or_create(name=category_name)
            validated_data["category"] = category
        validated_data["is_active"] = True
        product = super().create(validated_data)
        self._save_gallery(product)
        self._save_video_poster(product)
        self._apply_probed_duration(product)
        return product

    def update(self, instance, validated_data):
        category_name = (validated_data.pop("category_name", "") or "").strip()
        if category_name:
            category, _ = ProductCategory.objects.get_or_create(name=category_name)
            validated_data["category"] = category
        product = super().update(instance, validated_data)
        self._save_gallery(product)
        self._save_video_poster(product)
        self._apply_probed_duration(product)
        return product

    def _apply_probed_duration(self, product):
        """Enregistre la duree video detectee a la validation (si > 0)."""
        duration = int(getattr(self, "_probed_video_duration", 0) or 0)
        if duration > 0 and product.video and product.video_duration_seconds != duration:
            product.video_duration_seconds = duration
            product.save(update_fields=["video_duration_seconds"])

    def _save_video_poster(self, product):
        """Genere et attache un poster (vignette) extrait de la video.

        Idempotent : ne fait rien si pas de video ou si un poster existe deja.
        Tout echec est silencieux — la publication ne doit jamais casser pour
        un poster manquant.
        """
        if not product.video or product.video_poster:
            return
        poster = generate_video_poster(product.video)
        if poster is None:
            return
        product.video_poster.save(f"poster_{product.pk}.jpg", poster, save=True)


class TrackProductViewSerializer(serializers.Serializer):
    product_id = serializers.IntegerField(min_value=1)


class ProductFavoriteSerializer(serializers.ModelSerializer):
    product_title = serializers.CharField(source="product.title", read_only=True)
    product_reference_code = serializers.CharField(source="product.reference_code", read_only=True)
    product_image = serializers.ImageField(source="product.image", read_only=True)

    class Meta:
        model = ProductFavorite
        fields = (
            "id",
            "user",
            "product",
            "product_title",
            "product_reference_code",
            "product_image",
            "created_at",
        )
        read_only_fields = ("user", "created_at")


class SavedProductFilterSerializer(serializers.ModelSerializer):
    class Meta:
        model = SavedProductFilter
        fields = "__all__"
        read_only_fields = ("user", "created_at")


class VideoCommentSerializer(serializers.ModelSerializer):
    author = serializers.CharField(source="user.username", read_only=True)
    likes_count = serializers.SerializerMethodField()
    replies_count = serializers.SerializerMethodField()
    is_liked = serializers.SerializerMethodField()
    is_seller = serializers.SerializerMethodField()

    class Meta:
        model = VideoComment
        fields = (
            "id",
            "product",
            "parent",
            "author",
            "message",
            "likes_count",
            "replies_count",
            "is_liked",
            "is_seller",
            "created_at",
        )
        read_only_fields = ("author", "created_at")

    def validate_message(self, value):
        return redact_links(value)

    def get_likes_count(self, obj):
        return int(getattr(obj, "likes_count", 0) or 0)

    def get_replies_count(self, obj):
        return int(getattr(obj, "replies_count", 0) or 0)

    def get_is_liked(self, obj):
        return bool(getattr(obj, "is_liked", False))

    def get_is_seller(self, obj):
        return obj.user_id == obj.product.seller_id
