from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.accounts.models import UserRole
from core.permissions.rbac import IsGeneralAdmin
from .models import LedgerAccount, LedgerTransaction, LedgerEntry
from .serializers import LedgerAccountSerializer, LedgerTransactionSerializer
from .services import ledger_service


class LedgerAccountViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = LedgerAccountSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Audit ref: [NEW-004] enum comparison — a rename of the role enum
        # would otherwise silently expose ALL ledger accounts to non-admins.
        user = self.request.user
        if getattr(user, "role", None) == UserRole.GENERAL_ADMIN:
            return LedgerAccount.objects.all()
        return LedgerAccount.objects.filter(owner=user)

    @action(detail=True, methods=["get"], url_path="balance")
    def balance(self, request, pk=None):
        account = self.get_object()
        balance = ledger_service.get_account_balance(account)
        return Response({"account_id": str(account.pk), "balance": str(balance), "currency": account.currency})


class LedgerTransactionViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = LedgerTransactionSerializer
    permission_classes = [IsAuthenticated, IsGeneralAdmin]

    def get_queryset(self):
        return LedgerTransaction.objects.prefetch_related("entries").order_by("-posted_at")
