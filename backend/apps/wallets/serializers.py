from rest_framework import serializers

from .models import Wallet, WalletTransaction


class WalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = Wallet
        fields = (
            "id",
            "owner",
            "currency",
            "available_balance",
            "locked_balance",
            "pending_balance",
            "balance",
            "blocked_balance",
            "updated_at",
        )
        read_only_fields = fields


class WalletTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletTransaction
        fields = "__all__"
        read_only_fields = tuple(f.name for f in WalletTransaction._meta.get_fields() if hasattr(f, "name"))
