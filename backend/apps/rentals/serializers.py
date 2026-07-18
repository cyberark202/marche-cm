from datetime import date
from decimal import Decimal

from rest_framework import serializers

from .models import RentalBooking, RentalListing, RentalPeriod, RentalStateEvent


class RentalListingSerializer(serializers.ModelSerializer):
    owner_username = serializers.CharField(source="owner.username", read_only=True)
    owner_reference_code = serializers.CharField(source="owner.reference_code", read_only=True)

    class Meta:
        model = RentalListing
        fields = "__all__"
        read_only_fields = ("owner", "reference_code", "status", "created_at", "updated_at")

    def validate_deposit_amount(self, value):
        if value < 0:
            raise serializers.ValidationError("La caution ne peut etre negative.")
        return value


class RentalStateEventSerializer(serializers.ModelSerializer):
    actor_username = serializers.CharField(source="actor.username", read_only=True)

    class Meta:
        model = RentalStateEvent
        fields = ("id", "from_status", "to_status", "note", "photo", "actor_username", "created_at")
        read_only_fields = fields


class RentalBookingSerializer(serializers.ModelSerializer):
    listing_title = serializers.CharField(source="listing.title", read_only=True)
    events = RentalStateEventSerializer(many=True, read_only=True)

    class Meta:
        model = RentalBooking
        fields = "__all__"
        read_only_fields = (
            "renter",
            "owner",
            "period_count",
            "rental_amount",
            "deposit_amount",
            "status",
            "rental_released_amount",
            "deposit_returned_amount",
            "deposit_forfeited_amount",
            "handover_confirmed_at",
            "return_confirmed_at",
            "accepted_at",
            "completed_at",
            "created_at",
            "updated_at",
        )

    def validate(self, attrs):
        start = attrs.get("start_date")
        end = attrs.get("end_date")
        if start and end and end < start:
            raise serializers.ValidationError("La date de fin doit etre posterieure a la date de debut.")
        if start and start < date.today():
            raise serializers.ValidationError("La date de debut ne peut etre dans le passe.")
        return attrs

    @staticmethod
    def compute_period_count(period: str, start, end) -> int:
        days = (end - start).days + 1
        if period == RentalPeriod.HOUR:
            return max(1, days * 24)
        if period == RentalPeriod.DAY:
            return max(1, days)
        if period == RentalPeriod.WEEK:
            return max(1, -(-days // 7))
        if period == RentalPeriod.MONTH:
            return max(1, -(-days // 30))
        return max(1, days)
