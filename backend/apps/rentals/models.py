from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class RentalPeriod(models.TextChoices):
    HOUR = "HOUR", "Heure"
    DAY = "DAY", "Jour"
    WEEK = "WEEK", "Semaine"
    MONTH = "MONTH", "Mois"


class RentalListingStatus(models.TextChoices):
    DRAFT = "DRAFT", "Brouillon"
    PUBLISHED = "PUBLISHED", "Publie"
    SUSPENDED = "SUSPENDED", "Suspendu"
    ARCHIVED = "ARCHIVED", "Archive"


class RentalListing(models.Model):
    """Annonce de location (doc 14).

    Publication réservée au KYC niveau 2+ (vérifié via la vue). La preuve de
    propriété est obligatoire — stockée hors racine publique comme les autres
    documents sensibles.
    """

    REF_PREFIX = "RNT"

    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rental_listings")
    reference_code = models.CharField(max_length=24, unique=True, blank=True, null=True, db_index=True)
    title = models.CharField(max_length=200)
    description = models.TextField()
    category = models.CharField(max_length=120, blank=True)
    price_period = models.CharField(max_length=8, choices=RentalPeriod.choices, default=RentalPeriod.DAY)
    price_per_period = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    # Caution séquestrée pendant la location, restituée au retour conforme.
    deposit_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    image = models.ImageField(upload_to="rentals/images/", blank=True, null=True)
    # Preuve de propriété (doc 14) — obligatoire à la publication.
    ownership_proof = models.FileField(upload_to="rentals/ownership/", blank=True, null=True)
    city = models.CharField(max_length=120, blank=True)
    is_available = models.BooleanField(default=True)
    status = models.CharField(max_length=12, choices=RentalListingStatus.choices, default=RentalListingStatus.PUBLISHED)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.title

    def save(self, *args, **kwargs):
        if not self.reference_code:
            import random
            import string

            alphabet = string.ascii_uppercase + string.digits
            for _ in range(50):
                candidate = f"{self.REF_PREFIX}-{''.join(random.choice(alphabet) for _ in range(10))}"
                if not RentalListing.objects.filter(reference_code=candidate).exists():
                    self.reference_code = candidate
                    break
        super().save(*args, **kwargs)


class RentalBookingStatus(models.TextChoices):
    # État séquentiel principal (doc 22).
    REQUESTED = "REQUESTED", "Demandee"
    PAID = "PAID", "Payee (sequestre)"
    ACCEPTED = "ACCEPTED", "Acceptee"
    IN_PROGRESS = "IN_PROGRESS", "En cours"
    RETURNED = "RETURNED", "Restituee"
    COMPLETED = "COMPLETED", "Terminee"
    # Transitions exceptionnelles.
    REFUSED = "REFUSED", "Refusee"
    DISPUTED = "DISPUTED", "En litige"
    REFUNDED = "REFUNDED", "Remboursee"
    CANCELLED = "CANCELLED", "Annulee"


class RentalBooking(models.Model):
    """Réservation de location avec séquestre du loyer et de la caution (doc 14).

    Les fonds (loyer + caution) sont bloqués dès la demande payée. À la
    restitution conforme, le loyer est libéré au propriétaire et la caution
    restituée au locataire. Un litige gèle les fonds pour arbitrage admin.
    """

    listing = models.ForeignKey(RentalListing, on_delete=models.CASCADE, related_name="bookings")
    renter = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rental_bookings")
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="rental_owner_bookings")
    start_date = models.DateField()
    end_date = models.DateField()
    period_count = models.PositiveIntegerField(default=1)
    rental_amount = models.DecimalField(max_digits=12, decimal_places=2)
    deposit_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    status = models.CharField(max_length=12, choices=RentalBookingStatus.choices, default=RentalBookingStatus.REQUESTED)

    # OTP de remise du bien au locataire (doc 14). Hash salé uniquement.
    handover_otp_hash = models.CharField(max_length=128, blank=True)
    handover_otp_expires_at = models.DateTimeField(null=True, blank=True)
    handover_confirmed_at = models.DateTimeField(null=True, blank=True)
    # OTP de restitution du bien au propriétaire.
    return_otp_hash = models.CharField(max_length=128, blank=True)
    return_otp_expires_at = models.DateTimeField(null=True, blank=True)
    return_confirmed_at = models.DateTimeField(null=True, blank=True)

    # Fonds effectivement libérés / remboursés (pour une compta exacte).
    rental_released_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    deposit_returned_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    deposit_forfeited_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    accepted_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    @property
    def total_escrow(self) -> Decimal:
        return self.rental_amount + self.deposit_amount


class RentalStateEvent(models.Model):
    """Historique immuable des transitions d'état d'une réservation (doc 14)."""

    booking = models.ForeignKey(RentalBooking, on_delete=models.CASCADE, related_name="events")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="rental_events"
    )
    from_status = models.CharField(max_length=12, blank=True)
    to_status = models.CharField(max_length=12)
    note = models.CharField(max_length=240, blank=True)
    # État des lieux (photo) à la remise ou au retour.
    photo = models.ImageField(upload_to="rentals/condition/", blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
