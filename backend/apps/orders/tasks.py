"""Tâches planifiées commandes — expiration de la validation vendeur (doc 13).

Le vendeur dispose d'un délai configurable (clé "orders.seller_validation_hours",
24 h par défaut) pour accepter ou refuser. Passé ce délai, la commande expire
automatiquement et l'acheteur est remboursé intégralement.
"""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.orders.tasks.expire_unanswered_orders",
    queue="financial",
)
def expire_unanswered_orders(limit: int = 200) -> dict:
    from django.utils import timezone

    from apps.notifications.service import create_realtime_notification
    from .models import Order, OrderStatus
    from .services import OrderFinanceService

    now = timezone.now()
    expired = failed = 0
    candidates = Order.objects.filter(
        status=OrderStatus.PENDING,
        seller_accepted_at__isnull=True,
        seller_response_deadline__isnull=False,
        seller_response_deadline__lt=now,
    ).select_related("buyer", "seller")[: max(1, limit)]

    for order in candidates:
        try:
            refund_amount = OrderFinanceService.cancel_order(
                order=order,
                actor=None,
                system=True,
                reason="Expiration: le vendeur n'a pas valide la commande dans le delai imparti.",
            )
        except Exception:
            logger.exception("order_expiry_failed order=%s", order.id)
            failed += 1
            continue
        expired += 1
        for user, title, body in (
            (
                order.buyer,
                "Commande expiree",
                f"Le vendeur n'a pas repondu a temps. Commande #{order.id} annulee, "
                f"{refund_amount:,.0f} XAF rembourses sur votre wallet.",
            ),
            (
                order.seller,
                "Commande expiree",
                f"Vous n'avez pas valide la commande #{order.id} dans le delai imparti. Elle a ete annulee.",
            ),
        ):
            try:
                create_realtime_notification(user=user, title=title, body=body, payload={"order_id": order.id})
            except Exception:
                logger.exception("order_expiry_notify_failed order=%s user=%s", order.id, user.id)

    result = {"expired": expired, "failed": failed}
    logger.info("order_expiry_done", extra=result)
    return result
