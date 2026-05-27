from __future__ import annotations
import logging
import uuid
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.audit.services import audit_service
from .models import (
    DisputeCase, DisputeCategory, DisputeEvent, DisputeEventType,
    DisputeState, DisputeDecision,
)
from .state_machine import DisputeStateMachine

logger = logging.getLogger(__name__)

CRITICAL_TYPES = {"COUNTERFEIT", "FAKE_DOCUMENTS", "DATA_BREACH", "INTERNAL_THEFT", "HISTORY_TAMPER"}


def _to_decimal(value, field: str) -> Decimal:
    """Audit ref: [FIN-005] no float() on financial amounts."""
    if value is None or value == "":
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    try:
        return Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError) as exc:
        raise ValidationError(f"Montant {field} invalide.") from exc


class DisputeService:
    def open_dispute(
        self,
        opened_by,
        entity_type: str,
        entity_id: str,
        dispute_type: str,
        category: str,
        title: str,
        description: str,
        accused_party=None,
        escrow_hold_id=None,
        sla_hours: int = 72,
    ) -> DisputeCase:
        reference = f"DSP-{timezone.now().strftime('%Y%m%d')}-{str(uuid.uuid4())[:6].upper()}"
        is_critical = dispute_type in CRITICAL_TYPES

        with transaction.atomic():
            case = DisputeCase.objects.create(
                reference=reference,
                category=category,
                dispute_type=dispute_type,
                state=DisputeState.OPEN,
                opened_by=opened_by,
                accused_party=accused_party,
                entity_type=entity_type,
                entity_id=entity_id,
                title=title,
                description=description,
                escrow_hold_id=escrow_hold_id,
                sla_due_at=timezone.now() + timedelta(hours=sla_hours),
                is_critical=is_critical,
            )
            DisputeEvent.objects.create(
                dispute=case,
                event_type=DisputeEventType.OPENED,
                actor=opened_by,
                to_state=DisputeState.OPEN,
                description=f"Litige ouvert: {title}",
            )
            # Audit ref: [FIN-021] when a buyer opens a dispute on an Order
            # we must IMMEDIATELY freeze all associated escrow rows so the
            # auto-release timer cannot release funds to the seller while
            # the case is pending review.
            if entity_type == "Order":
                self._freeze_order_escrows_safe(entity_id=entity_id, actor=opened_by, reference=reference)
        return case

    @staticmethod
    def _freeze_order_escrows_safe(*, entity_id, actor, reference: str) -> None:
        """Best-effort freeze — never blocks dispute creation. A freeze
        failure (missing order, already-released escrows) is logged but
        does not raise: the case still needs to be reviewable by admin.
        """
        from apps.orders.models import Order
        from apps.orders.services import OrderFinanceService

        try:
            order = Order.objects.get(pk=entity_id)
        except (Order.DoesNotExist, ValueError, TypeError):
            logger.warning(
                "dispute.freeze_skipped_missing_order",
                extra={"entity_id": entity_id, "dispute_ref": reference},
            )
            return
        try:
            OrderFinanceService.freeze_order_escrows(
                order=order, actor=actor, reason=f"dispute:{reference}",
            )
        except Exception:
            logger.exception(
                "dispute.freeze_escrow_failed order_id=%s dispute_ref=%s",
                order.id, reference,
            )

    def escalate(self, case: DisputeCase, actor, reason: str) -> DisputeCase:
        machine = DisputeStateMachine(case)
        machine.transition_to(DisputeState.ESCALATED, actor=actor, reason=reason)
        return machine.case

    def make_decision(
        self,
        case: DisputeCase,
        decided_by,
        outcome: str,
        buyer_refund,
        seller_release,
        reasoning: str,
    ) -> DisputeDecision:
        """
        Audit ref: [FIN-005] decisions previously had no financial effect.

        This method now executes the matching financial primitive atomically
        with the state transition. The DisputeDecision row, the DisputeEvent
        log entry, and the wallet/escrow mutations are all committed in the
        same transaction — partial failure rolls back everything.

        Idempotency: a second call with the same outcome on a terminal-state
        case is rejected by the state machine.
        """
        # ── 1. Validate inputs as Decimal — no float() anywhere ────────────
        buyer_refund_d = _to_decimal(buyer_refund, "buyer_refund_amount")
        seller_release_d = _to_decimal(seller_release, "seller_release_amount")
        if buyer_refund_d < 0 or seller_release_d < 0:
            raise ValidationError("Montants negatifs interdits.")

        state_map = {
            "REFUND_BUYER": DisputeState.RESOLVED_BUYER,
            "RELEASE_SELLER": DisputeState.RESOLVED_SELLER,
            "SPLIT": DisputeState.RESOLVED_SPLIT,
            "NO_ACTION": DisputeState.CLOSED_NO_ACTION,
        }
        target = state_map.get(outcome, DisputeState.CLOSED_NO_ACTION)

        with transaction.atomic():
            # ── 2. Lock the case row to serialize concurrent decisions ─────
            case_locked = DisputeCase.objects.select_for_update().get(pk=case.pk)
            machine = DisputeStateMachine(case_locked)
            machine.transition_to(
                target, actor=decided_by, reason=f"Decision: {outcome}",
            )

            # ── 3. Execute the financial action ────────────────────────────
            executed = self._execute_financial_action(
                case=case_locked,
                outcome=outcome,
                decided_by=decided_by,
                buyer_refund=buyer_refund_d,
                seller_release=seller_release_d,
                reasoning=reasoning,
            )

            # ── 4. Persist the decision + event timeline ───────────────────
            decision = DisputeDecision.objects.create(
                dispute=machine.case,
                decided_by=decided_by,
                outcome=outcome,
                buyer_refund_amount=buyer_refund_d,
                seller_release_amount=seller_release_d,
                reasoning=reasoning,
            )
            DisputeEvent.objects.create(
                dispute=machine.case,
                event_type=DisputeEventType.DECISION_MADE,
                actor=decided_by,
                description=reasoning,
                payload={
                    "outcome": outcome,
                    "buyer_refund": str(buyer_refund_d),
                    "seller_release": str(seller_release_d),
                    "executed": executed,
                },
            )

            # ── 5. Immutable financial audit trail ─────────────────────────
            audit_service.log_dispute(
                event_type="dispute.decision.executed",
                dispute_id=str(machine.case.pk),
                payload={
                    "outcome": outcome,
                    "buyer_refund": str(buyer_refund_d),
                    "seller_release": str(seller_release_d),
                    "executed": executed,
                    "entity_type": machine.case.entity_type,
                    "entity_id": machine.case.entity_id,
                },
                actor=decided_by,
            )
        return decision

    def _execute_financial_action(
        self,
        *,
        case: DisputeCase,
        outcome: str,
        decided_by,
        buyer_refund: Decimal,
        seller_release: Decimal,
        reasoning: str,
    ) -> dict:
        """
        Map a decision outcome to a concrete monetary operation. Returns a
        machine-readable summary that gets persisted in the event + audit log.
        """
        # NO_ACTION still needs to record an explicit "no movement" trace.
        if outcome == "NO_ACTION":
            return {"action": "none"}

        # Only Order-typed disputes have a settlement path today.
        if case.entity_type != "Order":
            raise ValidationError(
                f"Type d'entite '{case.entity_type}' non supporte pour le settlement automatique."
            )

        # Lazy import to avoid a hard cross-app cycle.
        from apps.orders.models import Order
        from apps.orders.services import OrderFinanceService

        try:
            order = Order.objects.select_for_update().get(pk=case.entity_id)
        except (Order.DoesNotExist, ValueError) as exc:
            raise ValidationError(
                f"Commande {case.entity_id} introuvable pour le settlement."
            ) from exc

        reason = (reasoning or "")[:240]

        if outcome == "REFUND_BUYER":
            refunded = OrderFinanceService.refund_order_locked_funds(
                order=order, actor=decided_by,
                reason=f"dispute:{case.reference}",
            )
            return {"action": "refund_buyer", "amount": str(refunded)}

        if outcome == "RELEASE_SELLER":
            released = OrderFinanceService.admin_force_release_locked_escrows(
                order=order, actor=decided_by,
            )
            return {"action": "release_seller", "escrow_types": released}

        if outcome == "SPLIT":
            result = OrderFinanceService.dispute_split_release(
                order=order, actor=decided_by,
                buyer_refund=buyer_refund,
                seller_release=seller_release,
                reason=reason,
            )
            return {
                "action": "split",
                "buyer_refund": str(result["buyer_refund"]),
                "seller_release": str(result["seller_release"]),
            }

        raise ValidationError(f"Outcome inconnu: {outcome}")


dispute_service = DisputeService()
