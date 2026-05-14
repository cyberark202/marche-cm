from rest_framework import serializers

from .models import (
    DeliveryProof,
    Shipment,
    ShipmentDispute,
    ShipmentEvent,
    TransitAgentRating,
    TransportProfile,
    TransportQuote,
)


class TransportProfileSerializer(serializers.ModelSerializer):
    def validate_company_name(self, value):
        value = value.strip()
        if len(value) < 2:
            raise serializers.ValidationError("Le nom de societe est trop court.")
        return value

    def validate_coverage_countries(self, value):
        tokens = [token.strip().upper() for token in value.split(",") if token.strip()]
        if not tokens:
            raise serializers.ValidationError("Renseignez au moins un pays de couverture.")
        return ",".join(tokens)

    def validate_air_price_per_kg(self, value):
        if value <= 0:
            raise serializers.ValidationError("Le prix/kg par avion doit etre superieur a 0.")
        return value

    def validate_sea_price_per_kg(self, value):
        if value <= 0:
            raise serializers.ValidationError("Le prix/kg par bateau doit etre superieur a 0.")
        return value

    class Meta:
        model = TransportProfile
        fields = "__all__"
        read_only_fields = ("user", "rating", "completed_shipments")


class ShipmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Shipment
        fields = "__all__"
        read_only_fields = (
            "buyer",
            "seller",
            "transit_agent",
            "transport_mode",
            "shipping_fee",
            "status",
            "created_at",
            "updated_at",
        )


class TransportQuoteSerializer(serializers.ModelSerializer):
    def validate_fee(self, value):
        if value <= 0:
            raise serializers.ValidationError("Le montant du devis doit etre strictement positif.")
        return value

    def validate_eta_days(self, value):
        if value < 1 or value > 60:
            raise serializers.ValidationError("Le delai doit etre entre 1 et 60 jours.")
        return value

    class Meta:
        model = TransportQuote
        fields = "__all__"
        read_only_fields = ("transit_agent", "status", "created_at")


class ShipmentEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = ShipmentEvent
        fields = "__all__"
        read_only_fields = ("actor", "created_at")


class DeliveryProofSerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        otp = str(attrs.get("otp", "")).strip()
        signed_by = str(attrs.get("signed_by", "")).strip()
        latitude = attrs.get("latitude")
        longitude = attrs.get("longitude")

        if len(otp) != 6 or not otp.isdigit():
            raise serializers.ValidationError({"otp": "OTP invalide: 6 chiffres requis."})
        if not signed_by:
            raise serializers.ValidationError({"signed_by": "Le signataire est requis."})
        if (latitude is None) ^ (longitude is None):
            raise serializers.ValidationError(
                {"detail": "Latitude et longitude doivent etre renseignees ensemble."}
            )
        return attrs

    class Meta:
        model = DeliveryProof
        fields = "__all__"
        read_only_fields = ("validated", "created_at")


class ShipmentDisputeSerializer(serializers.ModelSerializer):
    def validate_reason(self, value):
        value = value.strip()
        if len(value) < 3:
            raise serializers.ValidationError("Le motif du litige est trop court.")
        return value

    def validate_details(self, value):
        value = value.strip()
        if len(value) < 10:
            raise serializers.ValidationError("Ajoutez plus de details sur le litige.")
        return value

    class Meta:
        model = ShipmentDispute
        fields = "__all__"
        read_only_fields = ("opened_by", "created_at", "updated_at", "decided_by", "decided_at")
        extra_kwargs = {
            "shipment": {"required": False},
        }


class TransitAgentRatingSerializer(serializers.ModelSerializer):
    class Meta:
        model = TransitAgentRating
        fields = "__all__"
        read_only_fields = ("transit_agent", "buyer", "created_at")

    def validate_score(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError("Le score doit etre entre 1 et 5.")
        return value
