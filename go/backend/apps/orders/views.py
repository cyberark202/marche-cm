from decimal import Decimal

from django.db.models import Count, Q, Sum
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import ValidationError

from apps.accounts.models import User, UserRole
from apps.accounts.security import write_audit_log
from apps.notifications.realtime import broadcast_event
from apps.notifications.service import create_realtime_notification
from .models import Order, OrderReview, OrderStatus, OrderType
from .services import FraudRiskError, OrderFinanceService
from .serializers import OrderReviewSerializer, OrderSerializer

ORDER_STATUS_TRANSITIONS = {
    OrderStatus.PENDING: {OrderStatus.SOURCING, OrderStatus.SHIPPING, OrderStatus.DISPUTED, OrderStatus.CANCELLED},
    OrderStatus.SOURCING: {OrderStatus.SUPPLIER_VERIFIED, OrderStatus.DISPUTED, OrderStatus.CANCELLED},
    OrderStatus.SUPPLIER_VERIFIED: {OrderStatus.ADMIN_APPROVED, OrderStatus.DISPUTED},
    OrderStatus.ADMIN_APPROVED: {OrderStatus.SHIPPING, OrderStatus.DISPUTED},
    OrderStatus.SHIPPING: {OrderStatus.DELIVERED, OrderStatus.DISPUTED, OrderStatus.CANCELLED},
    OrderStatus.DELIVERED: {OrderStatus.COMPLETED, OrderStatus.DISPUTED},
    OrderStatus.DISPUTED: {OrderStatus.REFUNDED, OrderStatus.COMPLETED},
    OrderStatus.REFUNDED: set(),
    # Legacy compatibility.
    OrderStatus.CONFIRMED: {OrderStatus.DELIVERED, OrderStatus.CANCELLED, OrderStatus.SHIPPING},
    OrderStatus.COMPLETED: set(),
    OrderStatus.CANCELLED: set(),
}
SALES_STATUSES = (
    OrderStatus.CONFIRMED,
    OrderStatus.SHIPPING,
    OrderStatus.DELIVERED,
    OrderStatus.COMPLETED,
)


def _money(value) -> str:
    return str(Decimal(value or 0).quantize(Decimal("0.01")))


def _aggregate_summary(queryset):
    totals = queryset.aggregate(
        orders_count=Count("id"),
        total_amount=Sum("total_price"),
        completed_orders_count=Count("id", filter=Q(status=OrderStatus.COMPLETED)),
        completed_amount=Sum("total_price", filter=Q(status=OrderStatus.COMPLETED)),
    )
    return {
        "orders_count": int(totals["orders_count"] or 0),
        "total_amount": _money(totals["total_amount"]),
        "completed_orders_count": int(totals["completed_orders_count"] or 0),
        "completed_amount": _money(totals["completed_amount"]),
    }


class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.select_related("buyer", "seller", "product", "shipment").all()
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]
    # Restreint a la lecture + creation: les transitions d'etat passent par les
    # actions @action dediees, jamais par PATCH/PUT/DELETE generiques.
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        user = self.request.user
        if user.is_superuser or user.role == UserRole.GENERAL_ADMIN:
            return self.queryset
        if user.role == UserRole.BUYER:
            return self.queryset.filter(buyer=user)
        if user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
            return self.queryset.filter(seller=user)
        if user.role == UserRole.TRANSIT_AGENT:
            return self.queryset.filter(shipment__transit_agent=user).distinct()
        return self.queryset.none()

    def perform_create(self, serializer):
        order = serializer.save()
        write_audit_log(actor=self.request.user, action="Creation commande", metadata={"order_id": order.id})
        try:
            create_realtime_notification(
                user=order.seller,
                title="Nouvelle commande",
                body=f"Vous avez recu la commande #{order.id}.",
                payload={"order_id": order.id},
            )
        except Exception:
            pass
        broadcast_event(
            "orders",
            "created",
            {
                "id": order.id,
                "buyer_id": order.buyer_id,
                "seller_id": order.seller_id,
                "status": order.status,
                "total_price": str(order.total_price),
            },
        )
        broadcast_event("wallets", "order_debit", {"order_id": order.id, "amount": str(order.total_price)})

    @decorators.action(detail=False, methods=["get"], url_path="sales-summary")
    def sales_summary(self, request):
        user = request.user
        sales_queryset = Order.objects.filter(status__in=SALES_STATUSES)
        my_sales_queryset = sales_queryset.filter(seller=user)
        my_purchases_queryset = sales_queryset.filter(buyer=user)

        payload = {
            "scope": "my_account",
            "currency": "FCFA",
            "sales_statuses": list(SALES_STATUSES),
            "my_account": {
                "user_id": user.id,
                "username": user.username,
                "reference_code": user.reference_code or f"USR-{user.id}",
                "role": user.role,
            },
            "my_sales": _aggregate_summary(my_sales_queryset),
            "my_purchases": _aggregate_summary(my_purchases_queryset),
        }

        if user.is_superuser or user.role == UserRole.GENERAL_ADMIN:
            aggregated_sales = {
                row["seller_id"]: row
                for row in sales_queryset.values("seller_id").annotate(
                    orders_count=Count("id"),
                    total_amount=Sum("total_price"),
                    completed_orders_count=Count("id", filter=Q(status=OrderStatus.COMPLETED)),
                    completed_amount=Sum("total_price", filter=Q(status=OrderStatus.COMPLETED)),
                )
            }
            account_rows = []
            for account in User.objects.exclude(role=UserRole.GENERAL_ADMIN).order_by("id"):
                stats = aggregated_sales.get(account.id, {})
                total_amount = Decimal(stats.get("total_amount") or 0)
                completed_amount = Decimal(stats.get("completed_amount") or 0)
                account_rows.append(
                    (
                        completed_amount,
                        total_amount,
                        {
                            "user_id": account.id,
                            "username": account.username,
                            "reference_code": account.reference_code or f"USR-{account.id}",
                            "role": account.role,
                            "orders_count": int(stats.get("orders_count") or 0),
                            "total_amount": _money(total_amount),
                            "completed_orders_count": int(stats.get("completed_orders_count") or 0),
                            "completed_amount": _money(completed_amount),
                        },
                    )
                )
            account_rows.sort(key=lambda item: (item[0], item[1]), reverse=True)
            payload.update(
                {
                    "scope": "all_accounts",
                    "overall_sales": _aggregate_summary(sales_queryset),
                    "accounts_count": len(account_rows),
                    "accounts": [row[2] for row in account_rows],
                }
            )

        return response.Response(payload, status=status.HTTP_200_OK)

    @decorators.action(detail=True, methods=["post"])
    def confirm_delivery(self, request, pk=None):
        order = self.get_object()
        if order.buyer_id != request.user.id:
            return response.Response({"detail": "Action reservee a l'acheteur."}, status=status.HTTP_403_FORBIDDEN)
        if OrderStatus.COMPLETED not in ORDER_STATUS_TRANSITIONS.get(order.status, set()):
            return response.Response(
                {"detail": f"Transition invalide: {order.status} -> {OrderStatus.COMPLETED}."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            if order.order_type == OrderType.INTERNATIONAL:
                OrderFinanceService.release_logistics_escrow_after_buyer_confirmation(order=order, actor=request.user)
            else:
                OrderFinanceService.release_local_escrow_after_buyer_confirmation(order=order, actor=request.user)
            order.refresh_from_db(fields=["status", "escrow_status"])
        except (ValidationError, FraudRiskError) as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        if order.status == OrderStatus.DISPUTED:
            return response.Response(
                {"detail": "Livraison enregistree mais payout en echec: fonds replaces en litige admin."},
                status=status.HTTP_409_CONFLICT,
            )

        try:
            create_realtime_notification(
                user=order.buyer,
                title="Commande finalisee",
                body=f"La commande #{order.id} est finalisee. Vous pouvez laisser un avis verifie.",
                payload={"order_id": order.id, "can_review": True},
            )
        except Exception:
            pass
        write_audit_log(actor=request.user, action="Confirmation livraison commande", metadata={"order_id": order.id})
        broadcast_event(
            "orders",
            "completed",
            {"id": order.id, "status": order.status, "escrow_status": order.escrow_status, "order_type": order.order_type},
        )
        broadcast_event("wallets", "escrow_released", {"order_id": order.id})
        return response.Response({"detail": "Livraison validee, fonds debloques au vendeur."})

    @decorators.action(detail=True, methods=["post", "get"])
    def review(self, request, pk=None):
        order = self.get_object()
        if request.method == "GET":
            if not hasattr(order, "review"):
                return response.Response({"detail": "Aucun avis pour cette commande."}, status=status.HTTP_404_NOT_FOUND)
            return response.Response(OrderReviewSerializer(order.review).data, status=status.HTTP_200_OK)

        if order.buyer_id != request.user.id:
            return response.Response(
                {"detail": "Seul l'acheteur peut laisser un avis sur cette commande."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if order.status != OrderStatus.COMPLETED:
            return response.Response(
                {"detail": "Avis autorise uniquement apres finalisation de la commande."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if hasattr(order, "review"):
            return response.Response({"detail": "Un avis existe deja pour cette commande."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            rating = int(request.data.get("rating"))
        except (TypeError, ValueError):
            return response.Response({"detail": "Note invalide (1 a 5)."}, status=status.HTTP_400_BAD_REQUEST)
        if rating < 1 or rating > 5:
            return response.Response({"detail": "Note invalide (1 a 5)."}, status=status.HTTP_400_BAD_REQUEST)
        comment = str(request.data.get("comment") or "").strip()
        review = OrderReview.objects.create(
            order=order,
            buyer=order.buyer,
            seller=order.seller,
            product=order.product,
            rating=rating,
            comment=comment,
            is_verified_purchase=True,
        )
        write_audit_log(
            actor=request.user,
            action="Avis verifie commande",
            action_key="orders.review",
            metadata={"order_id": order.id, "rating": rating},
        )
        try:
            create_realtime_notification(
                user=order.seller,
                title="Nouvel avis verifie",
                body=f"Commande #{order.id}: note {rating}/5.",
                payload={"order_id": order.id, "rating": rating},
            )
        except Exception:
            pass
        return response.Response(OrderReviewSerializer(review).data, status=status.HTTP_201_CREATED)
