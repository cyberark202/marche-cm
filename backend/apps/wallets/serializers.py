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
            "is_blocked",
            "updated_at",
        )
        read_only_fields = fields


class WalletTransactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = WalletTransaction
        fields = "__all__"
        # Toutes les transactions sont creees/mutees uniquement par les services
        # internes (WalletAccountingService). Aucun champ ne doit etre modifiable
        # via le serializer DRF.
        read_only_fields = tuple(f.name for f in WalletTransaction._meta.get_fields() if hasattr(f, "name"))
