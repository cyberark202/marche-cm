from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from apps.accounts.models import UserRole
from apps.catalog.models import Product
from apps.wallets.services import InsufficientFundsError
from .models import CartItem, EscrowStatus, Order, OrderReview, OrderStatus, OrderType
from .services import OrderFinanceService


class OrderReviewSerializer(serializers.ModelSerializer):
    photo_url = serializers.SerializerMethodField()

    class Meta:
        model = OrderReview
        fields = (
            "id",
            "order",
            "buyer",
            "seller",
            "product",
            "rating",
            "comment",
            "photo_url",
            "seller_reply",
            "seller_reply_at",
            "is_verified_purchase",
            "created_at",
        )
        read_only_fields = (
            "order", "buyer", "seller", "product", "photo_url",
            "seller_reply", "seller_reply_at", "is_verified_purchase", "created_at",
        )

    def get_photo_url(self, obj):
        request = self.context.get("request")
        try:
            url = obj.photo.url
        except (ValueError, AttributeError):
            return None
        return request.build_absolute_uri(url) if request else url


class CartItemSerializer(serializers.ModelSerializer):
    """Article de panier avec prix/stock/vendeur live (re-lus a chaque lecture)."""

    product_title = serializers.CharField(source="product.title", read_only=True)
    seller_id = serializers.IntegerField(source="product.seller_id", read_only=True)
    seller_name = serializers.CharField(source="product.seller.username", read_only=True)
    unit_price = serializers.DecimalField(
        source="product.price_for_min_qty", max_digits=12, decimal_places=2, read_only=True
    )
    available_qty = serializers.IntegerField(source="product.available_qty", read_only=True)
    image_url = serializers.SerializerMethodField()
    line_total = serializers.SerializerMethodField()
    is_available = serializers.SerializerMethodField()

    class Meta:
        model = CartItem
        fields = (
            "id",
            "product",
            "product_title",
            "seller_id",
            "seller_name",
            "unit_price",
            "available_qty",
            "image_url",
            "quantity",
            "line_total",
            "is_available",
            "added_at",
            "updated_at",
        )
        read_only_fields = ("added_at", "updated_at")

    def get_image_url(self, obj):
        request = self.context.get("request")
        try:
            url = obj.product.image.url
        except (ValueError, AttributeError):
            return None
        return request.build_absolute_uri(url) if request else url

    def get_line_total(self, obj):
        return str((Decimal(obj.product.price_for_min_qty) * obj.quantity).quantize(Decimal("0.01")))

    def get_is_available(self, obj):
        product = obj.product
        in_stock = product.available_qty is None or product.available_qty >= obj.quantity
        seller_ok = getattr(product.seller, "is_active", True) and not getattr(product.seller, "is_suspended", False)
        return bool(product.is_active and seller_ok and in_stock)

    def validate_product(self, value):
        if not value.is_active:
            raise serializers.ValidationError("Ce produit n'est plus disponible.")
        return value


class OrderSerializer(serializers.ModelSerializer):
    shipping_fee = serializers.SerializerMethodField(read_only=True)
    payable_total = serializers.SerializerMethodField(read_only=True)
    has_review = serializers.SerializerMethodField(read_only=True)
    review = OrderReviewSerializer(read_only=True)

    class Meta:
        model = Order
        fields = "__all__"
        read_only_fields = (
            "buyer",
            "seller",
            "unit_price",
            "total_price",
            "status",
            "escrow_status",
            "created_at",
            "updated_at",
            "shipping_fee",
            "payable_total",
            "has_review",
            "review",
            "preferred_transit_agent",
            "logistics_price",
            "seller_response_deadline",
            "seller_accepted_at",
        )

    def get_shipping_fee(self, obj):
        shipment = getattr(obj, "shipment", None)
        if not shipment:
            return "0.00"
        return str(Decimal(shipment.shipping_fee).quantize(Decimal("0.01")))

    def get_payable_total(self, obj):
        shipment = getattr(obj, "shipment", None)
        shipping_fee = Decimal(shipment.shipping_fee) if shipment else Decimal("0")
        return str((Decimal(obj.total_price) + shipping_fee).quantize(Decimal("0.01")))

    def get_has_review(self, obj):
        return hasattr(obj, "review")

    def create(self, validated_data):
        from apps.logistics.models import Shipment, TransportMode
        from .shipping import compute_shipping_fee

        if self.context["request"].user.role != UserRole.BUYER:
            raise serializers.ValidationError("Seul un acheteur peut passer commande.")

        product = validated_data["product"]
        quantity = validated_data["quantity"]
        if not product.is_active:
            raise serializers.ValidationError("Ce produit n'est plus disponible.")
        if not getattr(product.seller, "is_active", True) or getattr(product.seller, "is_suspended", False):
            raise serializers.ValidationError("Ce vendeur n'est plus disponible.")
        preferred_transit_agent = None
        join_grouping = validated_data.get("join_grouping", False)
        explicit_order_type = str(validated_data.get("order_type") or "").strip().upper()
        if explicit_order_type not in {OrderType.LOCAL, OrderType.INTERNATIONAL}:
            buyer_country = (self.context["request"].user.country_code or "CM").upper()
            seller_country = (product.seller.country_code or "CM").upper()
            explicit_order_type = OrderType.LOCAL if buyer_country == seller_country == "CM" else OrderType.INTERNATIONAL

        if join_grouping and not product.allows_group_campaign:
            raise serializers.ValidationError("Ce produit n'accepte pas le regroupage.")

        if quantity < product.min_order_qty or quantity > product.max_order_qty:
            raise serializers.ValidationError("Quantite hors plage min/max.")

        from apps.catalog.models import LISTING_TYPES_WITHOUT_LOGISTICS, ListingType

        if product.listing_type == ListingType.JOB:
            raise serializers.ValidationError("Les offres d'emploi ne sont pas commandables.")
        requires_logistics = product.listing_type not in LISTING_TYPES_WITHOUT_LOGISTICS

        unit_price = product.price_for_min_qty
        if quantity == product.max_order_qty:
            unit_price = product.price_for_max_qty
        total_price = Decimal(quantity) * Decimal(unit_price)
        shipping_fee = (
            compute_shipping_fee(product.seller, self.context["request"].user)
            if requires_logistics
            else Decimal("0.00")
        )
        transport_mode = TransportMode.SEA
        from apps.appconfig.models import get_platform_setting

        category_rates = get_platform_setting("commission.category_rates") or {}
        category_rate = category_rates.get(str(product.category_id)) if product.category_id else None
        platform_commission_rate = Decimal(
            str(category_rate if category_rate is not None else get_platform_setting("commission.default_rate"))
        )
        if platform_commission_rate < Decimal("0") or platform_commission_rate > Decimal("0.30"):
            platform_commission_rate = Decimal("0.10")

        validation_hours = int(get_platform_setting("orders.seller_validation_hours"))
        validated_data.update(
            {
                "buyer": self.context["request"].user,
                "seller": product.seller,
                "unit_price": unit_price,
                "total_price": total_price,
                "logistics_price": shipping_fee,
                "platform_commission_rate": platform_commission_rate,
                "order_type": explicit_order_type,
                "status": OrderStatus.PENDING,
                "escrow_status": EscrowStatus.HELD,
                "seller_response_deadline": timezone.now() + timedelta(hours=validation_hours),
            }
        )
        request_user = self.context["request"].user
        with transaction.atomic():
            locked_product = Product.objects.select_for_update().get(pk=product.pk)
            if locked_product.available_qty is not None:
                if quantity > locked_product.available_qty:
                    raise serializers.ValidationError(
                        "Stock insuffisant pour la quantite demandee."
                    )
                locked_product.available_qty = locked_product.available_qty - quantity
                locked_product.save(update_fields=["available_qty"])
            order = super().create(validated_data)
            if requires_logistics:
                shipment, created = Shipment.objects.get_or_create(
                    order=order,
                    defaults={
                        "buyer": order.buyer,
                        "seller": order.seller,
                        "transit_agent": preferred_transit_agent,
                        "transport_mode": transport_mode,
                        "shipping_fee": shipping_fee,
                        "pickup_address": "A definir avec vendeur",
                        "dropoff_address": "A definir avec acheteur",
                        "country_code": "CM",
                    },
                )
                fields_to_update = []
                if Decimal(shipment.shipping_fee) != shipping_fee:
                    shipment.shipping_fee = shipping_fee
                    fields_to_update.append("shipping_fee")
                if fields_to_update:
                    fields_to_update.append("updated_at")
                    shipment.save(update_fields=fields_to_update)

            try:
                OrderFinanceService.lock_funds_for_order(
                    order=order,
                    actor=request_user,
                    supplier_amount=total_price,
                    logistics_amount=shipping_fee,
                    idempotency_key=f"order-create:{order.id}",
                )
            except InsufficientFundsError as exc:
                raise serializers.ValidationError(str(exc)) from exc
        return order
