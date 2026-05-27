"""
Strict state machine base class.
All domain state transitions MUST go through a StateMachine subclass.
Direct field assignment bypassing the machine is prohibited by convention.

Usage:
    class OrderStateMachine(StateMachine):
        TRANSITIONS = {
            OrderStatus.PENDING: [OrderStatus.CONFIRMED, OrderStatus.CANCELLED],
            OrderStatus.CONFIRMED: [OrderStatus.SHIPPING, OrderStatus.CANCELLED],
            OrderStatus.SHIPPING: [OrderStatus.DELIVERED, OrderStatus.DISPUTED],
            OrderStatus.DELIVERED: [OrderStatus.COMPLETED],
        }

    machine = OrderStateMachine(order, "status")
    machine.transition_to(OrderStatus.CONFIRMED, actor=user, reason="Payment confirmed")
"""
from __future__ import annotations

import logging
from typing import Any

from django.db import transaction
from django.utils import timezone

logger = logging.getLogger(__name__)


class InvalidTransitionError(Exception):
    def __init__(self, current: str, target: str, entity: str = ""):
        self.current = current
        self.target = target
        super().__init__(
            f"Invalid transition [{entity}]: {current!r} → {target!r}"
        )


class StateMachine:
    """
    Base state machine.

    Subclasses define:
        TRANSITIONS: dict[str, list[str]]  — allowed transitions
        STATUS_FIELD: str = "status"       — model field name (override if needed)

    Optional hooks (override in subclass):
        on_transition(instance, from_status, to_status, actor, reason, metadata)
        on_enter_<state>(instance, from_status, actor, reason, metadata)
    """

    TRANSITIONS: dict[str, list[str]] = {}
    STATUS_FIELD: str = "status"

    def __init__(self, instance: Any, status_field: str | None = None):
        self.instance = instance
        self._field = status_field or self.STATUS_FIELD

    @property
    def current_state(self) -> str:
        return getattr(self.instance, self._field)

    def can_transition_to(self, target: str) -> bool:
        allowed = self.TRANSITIONS.get(self.current_state, [])
        return target in allowed

    def transition_to(
        self,
        target: str,
        actor: Any = None,
        reason: str = "",
        metadata: dict | None = None,
        save: bool = True,
    ) -> None:
        if not self.can_transition_to(target):
            raise InvalidTransitionError(
                current=self.current_state,
                target=target,
                entity=type(self.instance).__name__,
            )

        from_status = self.current_state
        setattr(self.instance, self._field, target)

        if save:
            with transaction.atomic():
                self.instance.save(update_fields=[self._field, "updated_at"])
                self._log_transition(from_status, target, actor, reason, metadata or {})

        self.on_transition(self.instance, from_status, target, actor, reason, metadata or {})

        hook_name = f"on_enter_{target.lower()}"
        if hasattr(self, hook_name):
            getattr(self, hook_name)(self.instance, from_status, actor, reason, metadata or {})

        logger.info(
            "state_transition",
            extra={
                "entity": type(self.instance).__name__,
                "entity_id": getattr(self.instance, "pk", None),
                "from": from_status,
                "to": target,
                "actor_id": getattr(actor, "pk", None),
                "reason": reason,
            },
        )

    def _log_transition(
        self,
        from_status: str,
        to_status: str,
        actor: Any,
        reason: str,
        metadata: dict,
    ) -> None:
        """Override to persist transition logs (e.g., write to audit table)."""
        pass

    def on_transition(
        self,
        instance: Any,
        from_status: str,
        to_status: str,
        actor: Any,
        reason: str,
        metadata: dict,
    ) -> None:
        """Hook called on every transition. Override in subclass."""
        pass
