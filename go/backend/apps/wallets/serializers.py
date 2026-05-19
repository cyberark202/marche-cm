from rest_framework import serializers

from .models import Wallet, WalletTransaction


class WalletSerializer(serializers.ModelSerializer):
    class Meta:
        model = Wallet
        # Liste blanche stricte: aucun champ technique (is_blocked, currency,
        # owner_id, etc.) ne doit etre modifiable via API.
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
        # Liste blanche stricte: on n'expose jamais reference (contient le
        # numero de telephone/email en clair), idempotency_key (implementation
        # interne), metadata (donnees provider brutes) ni cinetpay_transfered
        # (champ legacy interne).
        fields = (
            "id",
            "wallet",
            "kind",
            "provider",
            "status",
            "amount",
            "external_transaction_id",
            "failure_reason",
            "created_at",
            "updated_at",
            "reconciled_at",
        )
        read_only_fields = fields
