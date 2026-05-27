from rest_framework import serializers
from .models import LedgerAccount, LedgerTransaction, LedgerEntry


class LedgerEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = LedgerEntry
        fields = ["id", "transaction", "account", "direction", "amount",
                  "running_balance", "description", "created_at"]
        read_only_fields = ["id", "transaction", "account", "direction", "amount",
                            "running_balance", "description", "created_at"]


class LedgerTransactionSerializer(serializers.ModelSerializer):
    entries = LedgerEntrySerializer(many=True, read_only=True)

    class Meta:
        model = LedgerTransaction
        fields = [
            "id", "transaction_type", "idempotency_key", "reference",
            "description", "currency", "total_amount", "initiated_by",
            "correlation_id", "entries", "posted_at",
        ]
        read_only_fields = [
            "id", "transaction_type", "idempotency_key", "reference",
            "description", "currency", "total_amount", "initiated_by",
            "correlation_id", "entries", "posted_at",
        ]


class LedgerAccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = LedgerAccount
        fields = ["id", "account_type", "sub_type", "owner", "currency",
                  "description", "is_active", "created_at"]
        read_only_fields = ["id", "account_type", "sub_type", "owner", "currency",
                            "description", "is_active", "created_at"]
