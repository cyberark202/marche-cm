from decimal import Decimal

from django.conf import settings
from django.db import transaction
from rest_framework import serializers

from apps.accounts.models import UserRole
from apps.wallets.services import InsufficientFundsError
from .models import EscrowStatus, Order, OrderReview, OrderStatus, OrderType
from .services import OrderFinanceService


class OrderReviewSerializer(serializers.ModelSerializer):
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
            "is_verified_purchase",
            "created_at",
        )
        read_only_fields = ("order", "buyer", "seller", "product", "is_verified_purchase", "created_at")


class OrderSerializer(serializers.ModelSerializer):
    transport_mode = serializers.ChoiceField(
        choices=(("AIR", "Avion"), ("SEA", "Bateau")),
        write_only=True,
        required=True,
    )
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
        from apps.logistics.models import Shipment, TransportMode, TransportProfile

        if self.context["request"].user.role != UserRole.BUYER:
            raise serializers.ValidationError("Seul un acheteur peut passer commande.")

        product = validated_data["product"]
        quantity = validated_data["quantity"]
        preferred_transit_agent = validated_data.get("preferred_transit_agent")
        transport_mode = validated_data.pop("transport_mode", None)
        join_grouping = validated_data.get("join_grouping", False)
        explicit_order_type = str(validated_data.get("order_type") or "").strip().upper()
        if explicit_order_type not in {OrderType.LOCAL, OrderType.INTERNATIONAL}:
            buyer_country = (self.context["request"].user.country_code or "CM").upper()
            seller_country = (product.seller.country_code or "CM").upper()
            explicit_order_type = OrderType.LOCAL if buyer_country == seller_country == "CM" else OrderType.INTERNATIONAL

        if join_grouping and not product.allows_group_campaign:
            raise serializers.ValidationError("Ce produit n'accepte pas le regroupage.")
        if preferred_transit_agent and preferred_transit_agent.role != UserRole.TRANSIT_AGENT:
            raise serializers.ValidationError("Le transitaire choisi est invalide.")
        if not preferred_transit_agent:
            raise serializers.ValidationError("Selectionnez un transitaire pour cette commande.")
        if transport_mode not in {TransportMode.AIR, TransportMode.SEA}:
            raise serializers.ValidationError("Selectionnez un mode de transport valide (avion ou bateau).")
        if product.weight_kg is None or Decimal(product.weight_kg) <= 0:
            raise serializers.ValidationError("Le produit n'a pas de poids valide pour calculer le transport.")

        transit_profile = TransportProfile.objects.filter(user=preferred_transit_agent, is_active=True).first()
        if not transit_profile:
            raise serializers.ValidationError("Le transitaire choisi n'a pas de configuration tarifaire active.")

        if quantity < product.min_order_qty or quantity > product.max_order_qty:
            raise serializers.ValidationError("Quantite hors plage min/max.")

        unit_price = product.price_for_min_qty
        if quantity == product.max_order_qty:
            unit_price = product.price_for_max_qty
        total_price = Decimal(quantity) * Decimal(unit_price)
        price_per_kg = Decimal(transit_profile.sea_price_per_kg)
        if transport_mode == TransportMode.AIR:
            price_per_kg = Decimal(transit_profile.air_price_per_kg)
        shipping_fee = (Decimal(product.weight_kg) * Decimal(quantity) * price_per_kg).quantize(Decimal("0.01"))
        # Le taux de commission est fixe par la plateforme (config serveur),
        # jamais controle par le client. Defaut: 5%.
        platform_commission_rate = Decimal(
            str(getattr(settings, "PLATFORM_COMMISSION_RATE", "0.05"))
        )
        if platform_commission_rate < Decimal("0") or platform_commission_rate > Decimal("0.30"):
            platform_commission_rate = Decimal("0.05")

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
            }
        )
        request_user = self.context["request"].user
        with transaction.atomic():
            order = super().create(validated_data)
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
            if not created and preferred_transit_agent and shipment.transit_agent_id != preferred_transit_agent.id:
                shipment.transit_agent = preferred_transit_agent
                fields_to_update.append("transit_agent")
            if shipment.transport_mode != transport_mode:
                shipment.transport_mode = transport_mode
                fields_to_update.append("transport_mode")
            if Decimal(shipment.shipping_fee) != shipping_fee:
                shipment.shipping_fee = shipping_fee
                fields_to_update.append("shipping_fee")
            if fields_to_update:
                fields_to_update.append("updated_at")
                shipment.save(update_fields=fields_to_update)

            try:
                supplier_lock_amount = total_price + shipping_fee if explicit_order_type == OrderType.LOCAL else total_price
                OrderFinanceService.lock_funds_for_order(
                    order=order,
                    actor=request_user,
                    supplier_amount=supplier_lock_amount,
                    logistics_amount=shipping_fee if explicit_order_type == OrderType.INTERNATIONAL else Decimal("0.00"),
                    idempotency_key=f"order-create:{order.id}",
                )
            except InsufficientFundsError as exc:
                raise serializers.ValidationError(str(exc)) from exc
        return order
