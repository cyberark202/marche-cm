"""Machine à états + séquestre des locations (doc 14).

Séquestre : à la demande payée, (loyer + caution) sont bloqués sur le wallet du
locataire. À la restitution conforme, le loyer est libéré au propriétaire (net
de commission) et la caution restituée au locataire. Un refus rembourse tout ;
un litige gèle les fonds pour arbitrage admin. Tous les mouvements réutilisent
WalletAccountingService, donc restent tracés et cohérents avec le grand-livre.
"""
from __future__ import annotations

from decimal import Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from apps.accounts.security import write_audit_log
from apps.appconfig.models import get_platform_setting
from apps.wallets.models import LedgerDirection, LedgerEntryType
from apps.wallets.services import (
    InsufficientFundsError,
    WalletAccountingService,
    quantize_money,
)

from .models import RentalBooking, RentalBookingStatus, RentalStateEvent

ZERO = Decimal("0.00")

# Transitions autorisées (doc 22). Une transition hors table est refusée.
BOOKING_TRANSITIONS = {
    RentalBookingStatus.REQUESTED: {RentalBookingStatus.PAID, RentalBookingStatus.CANCELLED},
    RentalBookingStatus.PAID: {RentalBookingStatus.ACCEPTED, RentalBookingStatus.REFUSED, RentalBookingStatus.CANCELLED},
    RentalBookingStatus.ACCEPTED: {RentalBookingStatus.IN_PROGRESS, RentalBookingStatus.CANCELLED, RentalBookingStatus.DISPUTED},
    RentalBookingStatus.IN_PROGRESS: {RentalBookingStatus.RETURNED, RentalBookingStatus.DISPUTED},
    RentalBookingStatus.RETURNED: {RentalBookingStatus.COMPLETED, RentalBookingStatus.DISPUTED},
    RentalBookingStatus.DISPUTED: {RentalBookingStatus.COMPLETED, RentalBookingStatus.REFUNDED},
    RentalBookingStatus.COMPLETED: set(),
    RentalBookingStatus.REFUSED: set(),
    RentalBookingStatus.REFUNDED: set(),
    RentalBookingStatus.CANCELLED: set(),
}


def _rental_commission_rate() -> Decimal:
    try:
        rate = Decimal(str(get_platform_setting("commission.rental_rate")))
    except Exception:  # noqa: BLE001
        rate = Decimal("0.10")
    if rate < ZERO or rate > Decimal("0.50"):
        rate = Decimal("0.10")
    return rate


class RentalService:
    @staticmethod
    def _record_event(booking, *, actor, from_status, to_status, note=""):
        RentalStateEvent.objects.create(
            booking=booking, actor=actor, from_status=from_status, to_status=to_status, note=note[:240]
        )

    @classmethod
    def _transition(cls, booking, target, *, actor, note=""):
        if target not in BOOKING_TRANSITIONS.get(booking.status, set()):
            raise ValidationError(f"Transition location invalide: {booking.status} -> {target}.")
        previous = booking.status
        booking.status = target
        cls._record_event(booking, actor=actor, from_status=previous, to_status=target, note=note)

    @classmethod
    def pay_and_escrow(cls, *, booking: RentalBooking, actor):
        """Bloque (loyer + caution) sur le wallet du locataire (REQUESTED -> PAID)."""
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().get(id=booking.id)
            if booking.renter_id != actor.id:
                raise ValidationError("Paiement reserve au locataire.")
            if booking.status != RentalBookingStatus.REQUESTED:
                raise ValidationError("Reservation deja payee ou cloturee.")
            total = quantize_money(booking.total_escrow)
            if total <= ZERO:
                raise ValidationError("Montant de location invalide.")
            wallet = WalletAccountingService.get_wallet_for_update(user=booking.renter)
            if wallet.available_balance < total:
                raise InsufficientFundsError("Solde wallet insuffisant pour cette location.")
            WalletAccountingService.lock_from_available(
                wallet=wallet,
                amount=total,
                reference=f"rental:{booking.id}:escrow_lock",
                idempotency_key=f"rental:{booking.id}:lock_v1",
                created_by=actor,
                metadata={"rental_amount": str(booking.rental_amount), "deposit": str(booking.deposit_amount)},
            )
            cls._transition(booking, RentalBookingStatus.PAID, actor=actor, note="Fonds sequestres")
            booking.save(update_fields=["status", "updated_at"])
            write_audit_log(
                actor=actor, action="Paiement location sequestre", action_key="rentals.pay",
                metadata={"booking_id": booking.id, "total": str(total)},
            )
        return booking

    @classmethod
    def owner_respond(cls, *, booking: RentalBooking, actor, accept: bool):
        """Le propriétaire accepte (PAID -> ACCEPTED) ou refuse (PAID -> REFUSED
        + remboursement intégral au locataire)."""
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().select_related("renter").get(id=booking.id)
            if booking.owner_id != actor.id:
                raise ValidationError("Reponse reservee au proprietaire.")
            if booking.status != RentalBookingStatus.PAID:
                raise ValidationError("Reservation non en attente de validation.")
            if accept:
                cls._transition(booking, RentalBookingStatus.ACCEPTED, actor=actor, note="Location acceptee")
                booking.accepted_at = timezone.now()
                booking.save(update_fields=["status", "accepted_at", "updated_at"])
            else:
                cls._refund_all(booking, actor=actor, reason="Refus proprietaire")
                cls._transition(booking, RentalBookingStatus.REFUSED, actor=actor, note="Location refusee")
                booking.save(update_fields=["status", "deposit_returned_amount", "updated_at"])
            write_audit_log(
                actor=actor,
                action="Reponse proprietaire location",
                action_key="rentals.owner.respond",
                metadata={"booking_id": booking.id, "accepted": accept},
            )
        return booking

    @classmethod
    def _refund_all(cls, booking, *, actor, reason: str):
        """Débloque l'intégralité du séquestre vers le locataire."""
        total = quantize_money(booking.total_escrow)
        if total <= ZERO:
            return
        wallet = WalletAccountingService.get_wallet_for_update(user=booking.renter)
        if wallet.locked_balance < total:
            raise ValidationError("Solde bloque locataire insuffisant.")
        WalletAccountingService.unlock_to_available(
            wallet=wallet,
            amount=total,
            entry_type=LedgerEntryType.REFUND,
            reference=f"rental:{booking.id}:refund_all",
            idempotency_key=f"rental:{booking.id}:refund_v1",
            created_by=actor,
            metadata={"reason": reason},
        )
        booking.deposit_returned_amount = booking.deposit_amount

    @classmethod
    def confirm_handover(cls, *, booking: RentalBooking, actor):
        """Remise du bien confirmée par OTP (ACCEPTED -> IN_PROGRESS)."""
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().get(id=booking.id)
            cls._transition(booking, RentalBookingStatus.IN_PROGRESS, actor=actor, note="Bien remis")
            booking.handover_confirmed_at = timezone.now()
            booking.save(update_fields=["status", "handover_confirmed_at", "updated_at"])
        return booking

    @classmethod
    def confirm_return(cls, *, booking: RentalBooking, actor):
        """Restitution du bien confirmée par OTP (IN_PROGRESS -> RETURNED)."""
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().get(id=booking.id)
            cls._transition(booking, RentalBookingStatus.RETURNED, actor=actor, note="Bien restitue")
            booking.return_confirmed_at = timezone.now()
            booking.save(update_fields=["status", "return_confirmed_at", "updated_at"])
        return booking

    @classmethod
    def settle_conform(cls, *, booking: RentalBooking, actor):
        """Restitution conforme (RETURNED -> COMPLETED) : loyer libéré au
        propriétaire (net de commission), caution rendue au locataire."""
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().select_related("renter", "owner").get(id=booking.id)
            if booking.owner_id != actor.id:
                raise ValidationError("Cloture reservee au proprietaire.")
            if booking.status != RentalBookingStatus.RETURNED:
                raise ValidationError("Le bien n'a pas encore ete restitue.")
            cls._release_rental_and_deposit(booking, actor=actor, deposit_to_owner=ZERO)
            cls._transition(booking, RentalBookingStatus.COMPLETED, actor=actor, note="Location terminee")
            booking.completed_at = timezone.now()
            booking.save(update_fields=[
                "status", "completed_at", "rental_released_amount",
                "deposit_returned_amount", "deposit_forfeited_amount", "updated_at",
            ])
            write_audit_log(
                actor=actor, action="Cloture location conforme", action_key="rentals.settle",
                metadata={"booking_id": booking.id},
            )
        return booking

    @classmethod
    def open_dispute(cls, *, booking: RentalBooking, actor, reason: str = ""):
        """Ouvre un litige (dégradation/perte/retard, doc 14). Les fonds restent
        gelés dans le séquestre pour arbitrage admin."""
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().get(id=booking.id)
            if actor.id not in {booking.renter_id, booking.owner_id}:
                raise ValidationError("Litige reserve aux parties de la location.")
            cls._transition(booking, RentalBookingStatus.DISPUTED, actor=actor, note=f"Litige: {reason}"[:240])
            booking.save(update_fields=["status", "updated_at"])
            write_audit_log(
                actor=actor, action="Litige location ouvert", action_key="rentals.dispute.open",
                metadata={"booking_id": booking.id, "reason": reason[:200]},
            )
        return booking

    @classmethod
    def admin_resolve_dispute(cls, *, booking: RentalBooking, actor, deposit_forfeit):
        """Arbitrage admin (DISPUTED -> COMPLETED) : une part de la caution
        (0..deposit) est versée au propriétaire, le reste rendu au locataire ;
        le loyer est toujours libéré au propriétaire (net de commission)."""
        deposit_forfeit = quantize_money(deposit_forfeit)
        with transaction.atomic():
            booking = RentalBooking.objects.select_for_update().select_related("renter", "owner").get(id=booking.id)
            if booking.status != RentalBookingStatus.DISPUTED:
                raise ValidationError("Reservation non en litige.")
            if deposit_forfeit < ZERO or deposit_forfeit > booking.deposit_amount:
                raise ValidationError("Part de caution invalide.")
            cls._release_rental_and_deposit(booking, actor=actor, deposit_to_owner=deposit_forfeit)
            cls._transition(booking, RentalBookingStatus.COMPLETED, actor=actor, note="Litige tranche par admin")
            booking.completed_at = timezone.now()
            booking.save(update_fields=[
                "status", "completed_at", "rental_released_amount",
                "deposit_returned_amount", "deposit_forfeited_amount", "updated_at",
            ])
            write_audit_log(
                actor=actor, action="Litige location tranche", action_key="rentals.dispute.resolve",
                metadata={"booking_id": booking.id, "deposit_forfeit": str(deposit_forfeit)},
            )
        return booking

    @classmethod
    def _release_rental_and_deposit(cls, booking, *, actor, deposit_to_owner: Decimal):
        """Libère le loyer (net de commission) au propriétaire et répartit la
        caution : `deposit_to_owner` au propriétaire, le reste au locataire.

        Mêmes primitives que l'escrow commande : le locataire tient les fonds en
        locked_balance ; on débite son locked et on crédite l'available du
        bénéficiaire. La commission est enregistrée sans double débit.
        """
        rental_amount = quantize_money(booking.rental_amount)
        deposit_amount = quantize_money(booking.deposit_amount)
        deposit_to_owner = quantize_money(deposit_to_owner)
        deposit_to_renter = quantize_money(deposit_amount - deposit_to_owner)

        renter_wallet = WalletAccountingService.get_wallet_for_update(user=booking.renter)
        owner_wallet = WalletAccountingService.get_wallet_for_update(user=booking.owner)
        total_locked = quantize_money(rental_amount + deposit_amount)
        if renter_wallet.locked_balance < total_locked:
            raise InsufficientFundsError("Solde bloque locataire insuffisant.")

        commission_rate = _rental_commission_rate()
        commission = quantize_money(rental_amount * commission_rate)
        net_owner_rental = quantize_money(rental_amount - commission)
        owner_credit = quantize_money(net_owner_rental + deposit_to_owner)

        # 1) Retirer loyer + part caution proprietaire du locked du locataire.
        owner_from_locked = quantize_money(rental_amount + deposit_to_owner)
        if owner_from_locked > ZERO:
            WalletAccountingService.mutate_wallet(
                wallet=renter_wallet,
                amount=owner_from_locked,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.DEBIT,
                locked_delta=-owner_from_locked,
                reference=f"rental:{booking.id}:release:renter_lock",
                idempotency_key=f"rental:{booking.id}:release_renter_v1",
                counterparty=booking.owner,
                created_by=actor,
                metadata={"commission": str(commission), "deposit_to_owner": str(deposit_to_owner)},
            )
        # 2) Crediter le proprietaire (loyer net + part caution eventuelle).
        if owner_credit > ZERO:
            WalletAccountingService.mutate_wallet(
                wallet=owner_wallet,
                amount=owner_credit,
                entry_type=LedgerEntryType.ESCROW_RELEASE,
                direction=LedgerDirection.CREDIT,
                available_delta=owner_credit,
                reference=f"rental:{booking.id}:release:owner_credit",
                idempotency_key=f"rental:{booking.id}:release_owner_v1",
                counterparty=booking.renter,
                created_by=actor,
                metadata={"net_rental": str(net_owner_rental), "deposit_to_owner": str(deposit_to_owner)},
            )
        # 3) Commission plateforme (trace comptable, sans double debit).
        if commission > ZERO:
            WalletAccountingService.mutate_wallet(
                wallet=renter_wallet,
                amount=commission,
                entry_type=LedgerEntryType.COMMISSION,
                direction=LedgerDirection.DEBIT,
                reference=f"rental:{booking.id}:commission",
                idempotency_key=f"rental:{booking.id}:commission_v1",
                created_by=actor,
                metadata={"rate": str(commission_rate)},
            )
        # 4) Restituer la part de caution due au locataire (locked -> available).
        if deposit_to_renter > ZERO:
            WalletAccountingService.unlock_to_available(
                wallet=renter_wallet,
                amount=deposit_to_renter,
                entry_type=LedgerEntryType.REFUND,
                reference=f"rental:{booking.id}:deposit_return",
                idempotency_key=f"rental:{booking.id}:deposit_return_v1",
                created_by=actor,
                metadata={"deposit_to_renter": str(deposit_to_renter)},
            )
        booking.rental_released_amount = net_owner_rental
        booking.deposit_returned_amount = deposit_to_renter
        booking.deposit_forfeited_amount = deposit_to_owner
