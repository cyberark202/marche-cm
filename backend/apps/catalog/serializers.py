from rest_framework import serializers
from django.conf import settings

from apps.accounts.upload_security import scrub_image_metadata, validate_uploaded_file
from apps.accounts.models import UserRole
from .models import Product, ProductCategory, ProductFavorite, SavedProductFilter, VideoComment, VideoLike


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
    # Audit ref: [C-2] `is_active` is SERVER-controlled, never client-writable.
    # Two reasons: (1) a DRF BooleanField absent from a multipart/form-data body
    # is coerced to False, which silently created every image-upload product as
    # inactive (invisible in the catalogue); (2) it stops a manipulated payload
    # from publishing/forcing an arbitrary activation state. New products are
    # active by default (set in create()), identically for JSON and multipart.
    is_active = serializers.BooleanField(read_only=True)
    # Audit ref: [M-4] These are model-required (non-null DecimalField), which
    # made DRF mark them required at field level — so the wholesaler flow 400'd
    # before validate() could derive them from `unit_price`. Mark them optional
    # here; validate() fills them server-side for WHOLESALER and still enforces
    # their presence for SUPPLIER.
    price_for_min_qty = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True
    )
    price_for_max_qty = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True
    )

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

    def get_seller_is_verified(self, obj):
        seller = obj.seller
        if seller.role in {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}:
            return any(d.status == "APPROVED" for d in seller.compliance_documents.all())
        return bool(seller.is_verified)

    # Audit ref: [C-1] Backward-compatible field aliases. Older mobile builds
    # POST `category` (a name string), `min_qty`, `max_qty` instead of the
    # canonical `category_name`, `min_order_qty`, `max_order_qty`. Translate them
    # here BEFORE field validation so those clients keep working without an app
    # update. Canonical payloads are untouched.
    _LEGACY_QTY_ALIASES = {"min_qty": "min_order_qty", "max_qty": "max_order_qty"}

    @classmethod
    def _apply_legacy_aliases(cls, data):
        try:
            mutable = data.copy()  # QueryDict.copy() -> mutable, or dict.copy()
        except Exception:
            return data
        for legacy, canonical in cls._LEGACY_QTY_ALIASES.items():
            if mutable.get(legacy) not in (None, "") and not mutable.get(canonical):
                mutable[canonical] = mutable.get(legacy)
        # `category` carrying a non-numeric string is a legacy category *name*.
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

        if role == UserRole.SUPPLIER:
            min_qty = attrs.get("min_order_qty", getattr(self.instance, "min_order_qty", None))
            max_qty = attrs.get("max_order_qty", getattr(self.instance, "max_order_qty", None))
            min_price = attrs.get("price_for_min_qty", getattr(self.instance, "price_for_min_qty", None))
            max_price = attrs.get("price_for_max_qty", getattr(self.instance, "price_for_max_qty", None))
            if min_qty is None or max_qty is None:
                raise serializers.ValidationError(
                    "Le fournisseur doit renseigner les quantites min et max."
                )
            if min_price is None or max_price is None:
                raise serializers.ValidationError(
                    "Le fournisseur doit renseigner les prix min et max."
                )
            # Audit ref: [C-1] guard against an inverted price mapping. With a
            # volume discount, the unit price for the MINIMUM quantity (low
            # volume) must be >= the unit price for the MAXIMUM quantity (bulk).
            if min_price < max_price:
                raise serializers.ValidationError(
                    "Prix incoherents: le prix pour la quantite minimale doit etre "
                    ">= au prix pour la quantite maximale (remise sur volume)."
                )
        if role == UserRole.WHOLESALER:
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
        if allows_group_campaign and request and request.user.role != UserRole.WHOLESALER:
            raise serializers.ValidationError("Le regroupage est reserve aux grossistes.")
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
        return attrs

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
        return value

    def create(self, validated_data):
        category_name = (validated_data.pop("category_name", "") or "").strip()
        if category_name and not validated_data.get("category"):
            category, _ = ProductCategory.objects.get_or_create(name=category_name)
            validated_data["category"] = category
        # Audit ref: [C-2] server controls activation — always publish on create,
        # regardless of request content type (JSON or multipart).
        validated_data["is_active"] = True
        return super().create(validated_data)

    def update(self, instance, validated_data):
        category_name = (validated_data.pop("category_name", "") or "").strip()
        if category_name:
            category, _ = ProductCategory.objects.get_or_create(name=category_name)
            validated_data["category"] = category
        return super().update(instance, validated_data)


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

    class Meta:
        model = VideoComment
        fields = ("id", "product", "author", "message", "created_at")
        read_only_fields = ("author", "created_at")
