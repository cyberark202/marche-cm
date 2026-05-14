from rest_framework import serializers

from .models import (
    LoyaltyAccount,
    LoyaltyTransaction,
    PartnerApiKey,
    PriceAlert,
    RFQCounterOffer,
    WalletApprovalRequest,
    WebhookSubscription,
)


class PriceAlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = PriceAlert
        fields = "__all__"
        read_only_fields = ("user", "last_notified_price", "triggered_at", "created_at")


class RFQCounterOfferSerializer(serializers.ModelSerializer):
    class Meta:
        model = RFQCounterOffer
        fields = "__all__"
        read_only_fields = ("creator", "status", "decided_at", "created_at")


class WalletApprovalRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletApprovalRequest
        fields = "__all__"
        read_only_fields = ("requester", "approver", "status", "decided_at", "created_at")


class LoyaltyTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = LoyaltyTransaction
        fields = ("id", "action_type", "points", "reason", "created_at")


class LoyaltyAccountSerializer(serializers.ModelSerializer):
    transactions = LoyaltyTransactionSerializer(many=True, read_only=True)

    class Meta:
        model = LoyaltyAccount
        fields = ("points_balance", "tier", "updated_at", "transactions")


class PartnerApiKeySerializer(serializers.ModelSerializer):
    plain_key = serializers.CharField(read_only=True)

    class Meta:
        model = PartnerApiKey
        fields = ("id", "name", "key_prefix", "is_active", "created_at", "last_used_at", "plain_key")
        read_only_fields = ("key_prefix", "created_at", "last_used_at")


class WebhookSubscriptionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WebhookSubscription
        fields = "__all__"
        read_only_fields = ("owner", "last_delivery_status", "last_delivered_at", "created_at")
