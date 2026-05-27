"""
Escrow state machine — enforces ESCROW_TRANSITIONS strictly.
"""
from __future__ import annotations
import logging
from django.db import transaction
from django.utils import timezone
from .models import EscrowHold, EscrowState, EscrowTransition, ESCROW_TRANSITIONS

logger = logging.getLogger(__name__)


class EscrowStateMachineError(Exception):
    pass


class EscrowStateMachine:
    def __init__(self, hold: EscrowHold):
        self.hold = hold

    def can_transition_to(self, target: str) -> bool:
        return target in ESCROW_TRANSITIONS.get(self.hold.state, [])

    def transition_to(
        self,
        target: str,
        actor=None,
        reason: str = "",
        metadata: dict | None = None,
    ) -> None:
        if not self.can_transition_to(target):
            raise EscrowStateMachineError(
                f"Invalid escrow transition: {self.hold.state!r} → {target!r} "
                f"for hold {self.hold.id}"
            )
        from_state = self.hold.state
        with transaction.atomic():
            hold = EscrowHold.objects.select_for_update().get(pk=self.hold.pk)
            if not (target in ESCROW_TRANSITIONS.get(hold.state, [])):
                raise EscrowStateMachineError(
                    f"Race condition: hold state changed to {hold.state!r} before transition."
                )
            hold.state = target
            hold.updated_at = timezone.now()
            if target == EscrowState.FROZEN:
                hold.frozen_at = timezone.now()
                hold.frozen_by = actor
                hold.frozen_reason = reason
            elif target == EscrowState.RELEASED:
                hold.released_at = timezone.now()
            elif target == EscrowState.REFUNDED:
                hold.refunded_at = timezone.now()
            hold.save(update_fields=[
                "state", "updated_at", "frozen_at", "frozen_by_id",
                "frozen_reason", "released_at", "refunded_at"
            ])
            EscrowTransition.objects.create(
                escrow_hold=hold,
                from_state=from_state,
                to_state=target,
                triggered_by=actor,
                reason=reason,
                metadata=metadata or {},
            )
            self.hold = hold
        logger.info(
            "escrow_transition",
            extra={"hold_id": str(self.hold.id), "from": from_state, "to": target}
        )

    def mark_condition_met(self, condition: str, actor=None) -> bool:
        """Mark a release condition as satisfied. Returns True if all conditions now met."""
        with transaction.atomic():
            hold = EscrowHold.objects.select_for_update().get(pk=self.hold.pk)
            if condition not in hold.met_conditions:
                hold.met_conditions.append(condition)
                hold.save(update_fields=["met_conditions", "updated_at"])
            self.hold = hold
        all_met = self.hold.all_conditions_met
        if all_met and self.hold.state == EscrowState.LOCKED:
            self.transition_to(EscrowState.READY_TO_RELEASE, actor=actor, reason="All conditions met")
        return all_met
