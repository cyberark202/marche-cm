from rest_framework import serializers

from .models import GroupCampaign, RFQOffer, RequestForQuotation


class GroupCampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = GroupCampaign
        fields = "__all__"
        read_only_fields = ("wholesaler", "current_quantity", "created_at")


class RequestForQuotationSerializer(serializers.ModelSerializer):
    class Meta:
        model = RequestForQuotation
        fields = "__all__"
        read_only_fields = ("buyer", "status", "created_at")


class RFQOfferSerializer(serializers.ModelSerializer):
    class Meta:
        model = RFQOffer
        fields = "__all__"
        read_only_fields = ("seller", "created_at")

