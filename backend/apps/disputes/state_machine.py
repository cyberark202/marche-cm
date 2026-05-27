from __future__ import annotations
import logging
from django.db import transaction
from django.utils import timezone
from .models import DisputeCase, DisputeState, DisputeEvent, DisputeEventType, DISPUTE_TRANSITIONS

logger = logging.getLogger(__name__)


class DisputeStateMachineError(Exception):
    pass


class DisputeStateMachine:
    def __init__(self, case: DisputeCase):
        self.case = case

    def can_transition_to(self, target: str) -> bool:
        return target in DISPUTE_TRANSITIONS.get(self.case.state, [])

    def transition_to(
        self,
        target: str,
        actor=None,
        reason: str = "",
        payload: dict | None = None,
    ) -> None:
        if not self.can_transition_to(target):
            raise DisputeStateMachineError(
                f"Invalid dispute transition: {self.case.state!r} → {target!r}"
            )
        from_state = self.case.state
        with transaction.atomic():
            case = DisputeCase.objects.select_for_update().get(pk=self.case.pk)
            case.state = target
            if target in (DisputeState.RESOLVED_BUYER, DisputeState.RESOLVED_SELLER,
                          DisputeState.RESOLVED_SPLIT, DisputeState.CLOSED_NO_ACTION):
                case.resolved_at = timezone.now()
                case.resolved_by = actor
                case.resolution_outcome = target
            case.updated_at = timezone.now()
            case.save(update_fields=["state", "resolved_at", "resolved_by_id", "resolution_outcome", "updated_at"])

            DisputeEvent.objects.create(
                dispute=case,
                event_type=DisputeEventType.STATE_CHANGED,
                actor=actor,
                from_state=from_state,
                to_state=target,
                description=reason,
                payload=payload or {},
            )
            self.case = case

        logger.info(
            "dispute_transition",
            extra={"dispute_id": str(self.case.id), "from": from_state, "to": target}
        )
