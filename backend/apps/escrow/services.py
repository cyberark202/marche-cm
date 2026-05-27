"""
EscrowService — display & lifecycle helpers around the EscrowHold model.

Audit ref: [FIN-008/009] EscrowService was a "ghost" service that created
EscrowHold rows without touching wallets or the ledger. Any production call to
`create_order_escrow`, `release_to_beneficiary`, or `refund_to_payer` would
declare a financial state that did not exist — guaranteed 100% loss on every
call.

Design decision after audit:
    Money flow has a SINGLE authoritative path:
        apps.orders.services.OrderFinanceService

    EscrowHold remains as a DENORMALIZED VIEW MODEL backing the
    /api/escrow/holds/ read API. Lifecycle metadata (state, conditions met,
    auto_release_at) lives here. Actual cash movement lives in OrderEscrow
    + WalletAccountingService + LedgerService (single source of truth).

The previously dangerous write methods now raise EscrowServiceUnsupportedError
to surface any code path that still relies on the ghost behaviour. They are
NOT silently fixed because silently routing them to the real engine would
risk double-debit on workflows that already locked funds via OrderFinanceService.

Read & state-only helpers (`freeze_for_dispute`, `mark_condition_met`,
`process_auto_releases`) remain functional — they touch the EscrowHold
state machine only, never money.
"""
from __future__ import annotations

import logging
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from .models import EscrowHold, EscrowState, ReleaseCondition
from .state_machine import EscrowStateMachine

logger = logging.getLogger(__name__)


class EscrowServiceUnsupportedError(RuntimeError):
    """
    Raised when a caller invokes a financial primitive that was previously
    a no-op ghost. The correct API is documented in the message.
    """


_MIGRATION_HINT = (
    "EscrowService.{name}() was decommissioned (audit ref: FIN-008/009). "
    "It used to mutate state without moving money. Use the authoritative API:\n"
    "  * lock funds       -> apps.orders.services.OrderFinanceService.lock_funds_for_order\n"
    "  * refund buyer     -> apps.orders.services.OrderFinanceService.refund_order_locked_funds\n"
    "  * release seller   -> apps.orders.services.OrderFinanceService.admin_force_release_locked_escrows\n"
    "  * split settlement -> apps.orders.services.OrderFinanceService.dispute_split_release\n"
    "If you need an EscrowHold display row, create it via\n"
    "  EscrowService.attach_display_record(order_escrow=...)\n"
)


class EscrowService:
    # ────────────────────────────────────────────────────────────────────
    # Refused write paths — formerly ghost methods that lost money.
    # ────────────────────────────────────────────────────────────────────

    def create_order_escrow(self, *args, **kwargs):  # noqa: ARG002
        raise EscrowServiceUnsupportedError(_MIGRATION_HINT.format(name="create_order_escrow"))

    def release_to_beneficiary(self, *args, **kwargs):  # noqa: ARG002
        raise EscrowServiceUnsupportedError(_MIGRATION_HINT.format(name="release_to_beneficiary"))

    def refund_to_payer(self, *args, **kwargs):  # noqa: ARG002
        raise EscrowServiceUnsupportedError(_MIGRATION_HINT.format(name="refund_to_payer"))

    # ────────────────────────────────────────────────────────────────────
    # State-only helpers — safe, never touch wallets.
    # ────────────────────────────────────────────────────────────────────

    def freeze_for_dispute(self, hold: EscrowHold, actor, reason: str) -> EscrowHold:
        """
        Mark an EscrowHold display row as FROZEN. The underlying money lives
        in OrderEscrow; freezing it for dispute purposes is handled
        atomically by `OrderFinanceService.freeze_order_escrows`.

        This method is retained for admin UI flows where the operator only
        wants to flag a hold as under-investigation without yet running a
        settlement decision. It is a metadata-only state change.
        """
        with transaction.atomic():
            locked = EscrowHold.objects.select_for_update().get(pk=hold.pk)
            machine = EscrowStateMachine(locked)
            machine.transition_to(EscrowState.FROZEN, actor=actor, reason=reason)
            return machine.hold

    def mark_condition_met(self, hold: EscrowHold, condition: str, actor=None) -> EscrowHold:
        with transaction.atomic():
            locked = EscrowHold.objects.select_for_update().get(pk=hold.pk)
            machine = EscrowStateMachine(locked)
            machine.mark_condition_met(condition, actor=actor)
            return machine.hold

    def process_auto_releases(self) -> int:
        """
        Called by Celery beat. Marks the AUTO_RELEASE_TIMER condition on
        EscrowHold rows past their deadline so dashboards reflect the
        ready-for-release state. The actual money release is driven by
        OrderFinanceService.release_local_escrow_after_buyer_confirmation
        (or its sibling helpers) — never by this loop.
        """
        now = timezone.now()
        # Tight queryset: only state=LOCKED rows whose timer has elapsed.
        holds = EscrowHold.objects.filter(
            state=EscrowState.LOCKED,
            auto_release_at__lte=now,
        ).order_by("pk").only("pk")[:500]
        count = 0
        for hold in holds:
            try:
                with transaction.atomic():
                    locked = EscrowHold.objects.select_for_update().get(pk=hold.pk)
                    if locked.state != EscrowState.LOCKED:
                        continue
                    machine = EscrowStateMachine(locked)
                    machine.mark_condition_met(ReleaseCondition.AUTO_RELEASE_TIMER)
                count += 1
            except Exception:
                logger.exception("auto_release_error hold=%s", hold.pk)
        return count

    # ────────────────────────────────────────────────────────────────────
    # Display record creation — strictly read-only mirror of OrderEscrow.
    # ────────────────────────────────────────────────────────────────────

    @staticmethod
    def attach_display_record(*, order_escrow, idempotency_key: str) -> EscrowHold:
        """
        Create (or fetch) an EscrowHold row that mirrors an existing
        OrderEscrow for UI / dispute / audit display purposes only. This
        method does NOT debit or credit any wallet — the source-of-truth
        money movement must have already happened via OrderFinanceService.

        The unique idempotency_key guarantees one display row per
        OrderEscrow; concurrent callers either reuse the existing row or
        observe a unique-violation from the DB constraint.
        """
        from datetime import timedelta

        from .models import EscrowPurpose, EscrowState

        defaults = {
            "purpose": EscrowPurpose.ORDER_PAYMENT,
            "state": EscrowState.LOCKED,
            "beneficiary": order_escrow.beneficiary,
            "payer": getattr(order_escrow, "payer", None) or order_escrow.order.buyer,
            "amount": Decimal(order_escrow.amount),
            "commission_amount": Decimal(getattr(order_escrow, "commission_amount", 0) or 0),
            "entity_type": "Order",
            "entity_id": str(order_escrow.order_id),
            "required_conditions": [
                ReleaseCondition.BUYER_CONFIRMED,
                ReleaseCondition.TRANSIT_CONFIRMED,
            ],
            "auto_release_at": timezone.now() + timedelta(days=7),
        }
        hold, _ = EscrowHold.objects.get_or_create(
            idempotency_key=idempotency_key,
            defaults=defaults,
        )
        return hold


escrow_service = EscrowService()
