"""
Domain Event Bus — publishes events via the Outbox Pattern.

Usage:
    from core.events.bus import event_bus

    # Inside a database transaction:
    event_bus.publish(
        event_type="ORDER_CREATED",
        aggregate_type="Order",
        aggregate_id=str(order.id),
        payload={"buyer_id": order.buyer_id, "total": str(order.total_price)},
        correlation_id=request_correlation_id,
    )

The event is written to OutboxEvent within the same DB transaction.
A Celery task polls and dispatches to registered handlers.
"""
from __future__ import annotations

import logging
from typing import Any

from django.db import transaction

from .models import OutboxEvent

logger = logging.getLogger(__name__)


class EventBus:
    """
    Transactional event bus backed by the outbox pattern.
    Events are written to the DB in the same transaction as the domain operation.
    """

    def publish(
        self,
        event_type: str,
        aggregate_type: str,
        aggregate_id: str,
        payload: dict[str, Any] | None = None,
        correlation_id: str = "",
        causation_id: str | None = None,
        max_retries: int = 5,
    ) -> OutboxEvent:
        event = OutboxEvent(
            event_type=event_type,
            aggregate_type=aggregate_type,
            aggregate_id=str(aggregate_id),
            payload=payload or {},
            correlation_id=correlation_id or "",
            causation_id=causation_id,
            max_retries=max_retries,
        )
        event.save()
        logger.info(
            "event_published",
            extra={"event_type": event_type, "aggregate_id": str(aggregate_id), "event_id": str(event.id)},
        )
        return event

    def publish_many(self, events: list[dict[str, Any]]) -> list[OutboxEvent]:
        """Bulk publish — all events written atomically."""
        instances = [
            OutboxEvent(
                event_type=e["event_type"],
                aggregate_type=e["aggregate_type"],
                aggregate_id=str(e["aggregate_id"]),
                payload=e.get("payload", {}),
                correlation_id=e.get("correlation_id", ""),
                causation_id=e.get("causation_id"),
                max_retries=e.get("max_retries", 5),
            )
            for e in events
        ]
        return OutboxEvent.objects.bulk_create(instances)


event_bus = EventBus()


# ---------------------------------------------------------------------------
# Domain event type constants
# ---------------------------------------------------------------------------

class DomainEvents:
    # Orders
    ORDER_CREATED = "ORDER_CREATED"
    ORDER_CONFIRMED = "ORDER_CONFIRMED"
    ORDER_CANCELLED = "ORDER_CANCELLED"
    ORDER_COMPLETED = "ORDER_COMPLETED"

    # Payments
    TOPUP_INITIATED = "TOPUP_INITIATED"
    TOPUP_CONFIRMED = "TOPUP_CONFIRMED"
    TOPUP_FAILED = "TOPUP_FAILED"
    WITHDRAWAL_INITIATED = "WITHDRAWAL_INITIATED"
    WITHDRAWAL_CONFIRMED = "WITHDRAWAL_CONFIRMED"
    WITHDRAWAL_FAILED = "WITHDRAWAL_FAILED"

    # Escrow
    ESCROW_LOCKED = "ESCROW_LOCKED"
    ESCROW_RELEASED = "ESCROW_RELEASED"
    ESCROW_REFUNDED = "ESCROW_REFUNDED"
    ESCROW_FROZEN = "ESCROW_FROZEN"

    # Logistics
    SHIPMENT_CREATED = "SHIPMENT_CREATED"
    SHIPMENT_ASSIGNED = "SHIPMENT_ASSIGNED"
    SHIPMENT_PICKED_UP = "SHIPMENT_PICKED_UP"
    SHIPMENT_DELIVERED = "SHIPMENT_DELIVERED"

    # Disputes
    DISPUTE_OPENED = "DISPUTE_OPENED"
    DISPUTE_RESOLVED = "DISPUTE_RESOLVED"
    DISPUTE_ESCALATED = "DISPUTE_ESCALATED"

    # KYC
    KYC_SUBMITTED = "KYC_SUBMITTED"
    KYC_APPROVED = "KYC_APPROVED"
    KYC_REJECTED = "KYC_REJECTED"

    # Fraud
    FRAUD_FLAG_RAISED = "FRAUD_FLAG_RAISED"
    FRAUD_FLAG_RESOLVED = "FRAUD_FLAG_RESOLVED"

    # Payouts
    PAYOUT_INITIATED = "PAYOUT_INITIATED"
    PAYOUT_CONFIRMED = "PAYOUT_CONFIRMED"
    PAYOUT_FAILED = "PAYOUT_FAILED"
    PAYOUT_RELEASED = "PAYOUT_RELEASED"

    # Notifications
    NOTIFICATION_REQUESTED = "NOTIFICATION_REQUESTED"
