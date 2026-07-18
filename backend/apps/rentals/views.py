import logging
import secrets
from decimal import Decimal

from django.contrib.auth.hashers import check_password, make_password
from django.utils import timezone
from datetime import timedelta
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.accounts.models import UserRole
from apps.accounts.security import write_audit_log
from apps.notifications.models import NotificationCategory
from apps.notifications.service import create_realtime_notification
from apps.wallets.services import InsufficientFundsError

from .models import (
    RentalBooking,
    RentalBookingStatus,
    RentalListing,
    RentalListingStatus,
)
from .serializers import RentalBookingSerializer, RentalListingSerializer
from .services import RentalService

logger = logging.getLogger(__name__)

# Doc 14 : publier une location exige un KYC niveau 2 minimum.
_RENTAL_PUBLISH_MIN_KYC = 2
# Les OTP de remise / retour du bien sont valables 5 minutes (doc 09).
_RENTAL_OTP_TTL = timedelta(minutes=5)


def _is_admin(user):
    return user.is_superuser or user.role == UserRole.GENERAL_ADMIN


class RentalListingViewSet(viewsets.ModelViewSet):
    serializer_class = RentalListingSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        base = RentalListing.objects.select_related("owner")
        if self.action in {"list", "retrieve"}:
            qs = base.filter(status=RentalListingStatus.PUBLISHED, owner__is_active=True)
            # L'utilisateur voit aussi ses propres annonces non publiées.
            if user.is_authenticated:
                own = base.filter(owner=user)
                return (qs | own).distinct()
            return qs
        if _is_admin(user):
            return base
        return base.filter(owner=user)

    def perform_create(self, serializer):
        user = self.request.user
        if not _is_admin(user):
            if not getattr(user, "is_verified", False) or int(getattr(user, "kyc_level", 0) or 0) < _RENTAL_PUBLISH_MIN_KYC:
                raise PermissionDenied(
                    "Publication de location reservee aux comptes verifies KYC niveau 2 (preuve de propriete requise)."
                )
            if not serializer.validated_data.get("ownership_proof"):
                raise ValidationError("La preuve de propriete est obligatoire pour publier une location.")
        serializer.save(owner=user)

    def perform_update(self, serializer):
        if not _is_admin(self.request.user) and serializer.instance.owner_id != self.request.user.id:
            raise PermissionDenied("Modification reservee au proprietaire.")
        # Doc 14 : interdit de modifier une annonce dont une location est active.
        active = serializer.instance.bookings.filter(
            status__in=[
                RentalBookingStatus.PAID,
                RentalBookingStatus.ACCEPTED,
                RentalBookingStatus.IN_PROGRESS,
            ]
        ).exists()
        if active:
            raise ValidationError("Impossible de modifier une annonce avec une location en cours.")
        serializer.save()


class RentalBookingViewSet(viewsets.ModelViewSet):
    serializer_class = RentalBookingSerializer
    permission_classes = [permissions.IsAuthenticated]
    http_method_names = ["get", "post", "head", "options"]

    def get_queryset(self):
        user = self.request.user
        base = RentalBooking.objects.select_related("listing", "renter", "owner").prefetch_related("events")
        if _is_admin(user):
            return base
        from django.db.models import Q

        return base.filter(Q(renter=user) | Q(owner=user))

    def perform_create(self, serializer):
        listing_id = self.request.data.get("listing")
        listing = RentalListing.objects.filter(id=listing_id).select_related("owner").first()
        if not listing or listing.status != RentalListingStatus.PUBLISHED or not listing.is_available:
            raise ValidationError("Annonce de location indisponible.")
        if listing.owner_id == self.request.user.id:
            raise ValidationError("Vous ne pouvez pas louer votre propre bien.")
        start = serializer.validated_data["start_date"]
        end = serializer.validated_data["end_date"]
        period_count = RentalBookingSerializer.compute_period_count(listing.price_period, start, end)
        rental_amount = (Decimal(listing.price_per_period) * Decimal(period_count)).quantize(Decimal("0.01"))
        serializer.save(
            listing=listing,
            renter=self.request.user,
            owner=listing.owner,
            period_count=period_count,
            rental_amount=rental_amount,
            deposit_amount=listing.deposit_amount,
            status=RentalBookingStatus.REQUESTED,
        )
        try:
            create_realtime_notification(
                user=listing.owner,
                title="Nouvelle demande de location",
                body=f"Demande de location pour « {listing.title} ».",
                payload={"booking_id": serializer.instance.id, "topic": "rentals"},
                category=NotificationCategory.RENTALS,
            )
        except Exception:
            logger.exception("notif_rental_request_failed booking=%s", serializer.instance.id)

    def _get_booking(self):
        return self.get_object()

    @decorators.action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        booking = self._get_booking()
        try:
            booking = RentalService.pay_and_escrow(booking=booking, actor=request.user)
        except InsufficientFundsError as exc:
            return response.Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
        except ValidationError as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response(RentalBookingSerializer(booking).data)

    @decorators.action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        return self._owner_respond(request, accept=True)

    @decorators.action(detail=True, methods=["post"])
    def refuse(self, request, pk=None):
        return self._owner_respond(request, accept=False)

    def _owner_respond(self, request, *, accept):
        booking = self._get_booking()
        try:
            booking = RentalService.owner_respond(booking=booking, actor=request.user, accept=accept)
        except ValidationError as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        try:
            create_realtime_notification(
                user=booking.renter,
                title="Location acceptee" if accept else "Location refusee",
                body=(
                    f"Votre demande de location #{booking.id} a ete acceptee."
                    if accept
                    else f"Votre demande de location #{booking.id} a ete refusee. Vous avez ete rembourse."
                ),
                payload={"booking_id": booking.id, "topic": "rentals"},
                category=NotificationCategory.RENTALS,
            )
        except Exception:
            logger.exception("notif_rental_respond_failed booking=%s", booking.id)
        return response.Response(RentalBookingSerializer(booking).data)

    @decorators.action(detail=True, methods=["post"], url_path="issue-handover-otp")
    def issue_handover_otp(self, request, pk=None):
        return self._issue_otp(request, kind="handover")

    @decorators.action(detail=True, methods=["post"], url_path="confirm-handover")
    def confirm_handover(self, request, pk=None):
        booking = self._get_booking()
        if booking.renter_id != request.user.id:
            return response.Response({"detail": "Confirmation reservee au locataire."}, status=status.HTTP_403_FORBIDDEN)
        err = self._verify_otp(booking, kind="handover", otp=str(request.data.get("otp") or "").strip())
        if err:
            return err
        try:
            booking = RentalService.confirm_handover(booking=booking, actor=request.user)
        except ValidationError as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        booking.handover_otp_hash = ""
        booking.handover_otp_expires_at = None
        booking.save(update_fields=["handover_otp_hash", "handover_otp_expires_at", "updated_at"])
        return response.Response(RentalBookingSerializer(booking).data)

    @decorators.action(detail=True, methods=["post"], url_path="issue-return-otp")
    def issue_return_otp(self, request, pk=None):
        return self._issue_otp(request, kind="return")

    @decorators.action(detail=True, methods=["post"], url_path="confirm-return")
    def confirm_return(self, request, pk=None):
        booking = self._get_booking()
        if booking.owner_id != request.user.id:
            return response.Response({"detail": "Confirmation reservee au proprietaire."}, status=status.HTTP_403_FORBIDDEN)
        err = self._verify_otp(booking, kind="return", otp=str(request.data.get("otp") or "").strip())
        if err:
            return err
        try:
            booking = RentalService.confirm_return(booking=booking, actor=request.user)
        except ValidationError as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        booking.return_otp_hash = ""
        booking.return_otp_expires_at = None
        booking.save(update_fields=["return_otp_hash", "return_otp_expires_at", "updated_at"])
        return response.Response(RentalBookingSerializer(booking).data)

    @decorators.action(detail=True, methods=["post"])
    def settle(self, request, pk=None):
        """Restitution conforme : loyer au proprietaire, caution rendue."""
        booking = self._get_booking()
        try:
            booking = RentalService.settle_conform(booking=booking, actor=request.user)
        except (ValidationError, InsufficientFundsError) as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response(RentalBookingSerializer(booking).data)

    @decorators.action(detail=True, methods=["post"], url_path="open-dispute")
    def open_dispute(self, request, pk=None):
        booking = self._get_booking()
        try:
            booking = RentalService.open_dispute(
                booking=booking, actor=request.user, reason=str(request.data.get("reason") or "")
            )
        except ValidationError as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response(RentalBookingSerializer(booking).data)

    @decorators.action(detail=True, methods=["post"], url_path="resolve-dispute")
    def resolve_dispute(self, request, pk=None):
        if not _is_admin(request.user):
            return response.Response({"detail": "Arbitrage reserve a l'administration."}, status=status.HTTP_403_FORBIDDEN)
        booking = self._get_booking()
        raw = request.data.get("deposit_forfeit")
        try:
            deposit_forfeit = Decimal(str(raw if raw is not None else "0"))
        except Exception:
            return response.Response({"detail": "Montant de caution invalide."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            booking = RentalService.admin_resolve_dispute(
                booking=booking, actor=request.user, deposit_forfeit=deposit_forfeit
            )
        except (ValidationError, InsufficientFundsError) as exc:
            return response.Response({"detail": self._msg(exc)}, status=status.HTTP_400_BAD_REQUEST)
        return response.Response(RentalBookingSerializer(booking).data)

    # ---- helpers OTP remise/retour ----

    def _issue_otp(self, request, *, kind):
        booking = self._get_booking()
        # La remise : le proprietaire declenche, le code va au locataire.
        # Le retour : le locataire declenche, le code va au proprietaire.
        if kind == "handover":
            if booking.owner_id != request.user.id:
                return response.Response({"detail": "Reserve au proprietaire."}, status=status.HTTP_403_FORBIDDEN)
            if booking.status != RentalBookingStatus.ACCEPTED:
                return response.Response({"detail": "La location doit etre acceptee."}, status=status.HTTP_400_BAD_REQUEST)
            recipient = booking.renter
        else:
            if booking.renter_id != request.user.id:
                return response.Response({"detail": "Reserve au locataire."}, status=status.HTTP_403_FORBIDDEN)
            if booking.status != RentalBookingStatus.IN_PROGRESS:
                return response.Response({"detail": "La location doit etre en cours."}, status=status.HTTP_400_BAD_REQUEST)
            recipient = booking.owner
        code = f"{secrets.randbelow(10000):04d}"
        expires = timezone.now() + _RENTAL_OTP_TTL
        if kind == "handover":
            booking.handover_otp_hash = make_password(code)
            booking.handover_otp_expires_at = expires
            booking.save(update_fields=["handover_otp_hash", "handover_otp_expires_at", "updated_at"])
            label = "remise"
        else:
            booking.return_otp_hash = make_password(code)
            booking.return_otp_expires_at = expires
            booking.save(update_fields=["return_otp_hash", "return_otp_expires_at", "updated_at"])
            label = "restitution"
        try:
            create_realtime_notification(
                user=recipient,
                title=f"Code de {label}",
                body=f"Communiquez le code {code} pour confirmer la {label} du bien loue.",
                payload={"booking_id": booking.id, "type": f"rental_{kind}_otp"},
                category=NotificationCategory.RENTALS,
            )
        except Exception:
            logger.exception("notif_rental_otp_failed booking=%s kind=%s", booking.id, kind)
        write_audit_log(
            actor=request.user,
            action=f"Emission OTP {label} location",
            action_key=f"rentals.{kind}.otp.issue",
            metadata={"booking_id": booking.id},
        )
        return response.Response({"detail": f"Code de {label} envoye."})

    def _verify_otp(self, booking, *, kind, otp):
        if not otp:
            return response.Response({"detail": "Code requis."}, status=status.HTTP_400_BAD_REQUEST)
        otp_hash = booking.handover_otp_hash if kind == "handover" else booking.return_otp_hash
        expires = booking.handover_otp_expires_at if kind == "handover" else booking.return_otp_expires_at
        if not otp_hash or not expires:
            return response.Response({"detail": "Aucun code actif. Demandez l'envoi du code."}, status=status.HTTP_400_BAD_REQUEST)
        if timezone.now() > expires:
            return response.Response({"detail": "Code expire. Demandez un nouveau code."}, status=status.HTTP_400_BAD_REQUEST)
        if not check_password(otp, otp_hash):
            return response.Response({"detail": "Code invalide."}, status=status.HTTP_400_BAD_REQUEST)
        return None

    @staticmethod
    def _msg(exc):
        detail = getattr(exc, "detail", None)
        if isinstance(detail, (list, tuple)) and detail:
            return str(detail[0])
        return str(detail if detail is not None else exc)
