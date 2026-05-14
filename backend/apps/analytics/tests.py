from decimal import Decimal

from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.analytics.models import GroupCampaign
from apps.catalog.models import Product


class GroupCampaignAccessTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.wholesaler = User.objects.create_user(
            username="wholesaler_1",
            email="wholesaler_1@test.local",
            password="TestPassword123!",
            role="WHOLESALER",
            is_active=True,
        )
        self.buyer = User.objects.create_user(
            username="buyer_1",
            email="buyer_1@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )
        self.supplier = User.objects.create_user(
            username="supplier_1",
            email="supplier_1@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_active=True,
        )
        self.admin = User.objects.create_user(
            username="admin_1",
            email="admin_1@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_active=True,
        )
        product = Product.objects.create(
            seller=self.wholesaler,
            title="Produit test",
            description="Description",
            brand="Brand",
            min_order_qty=1,
            max_order_qty=10,
            price_for_min_qty=Decimal("1000.00"),
            price_for_max_qty=Decimal("900.00"),
            is_active=True,
        )
        self.campaign = GroupCampaign.objects.create(
            wholesaler=self.wholesaler,
            product=product,
            target_quantity=500,
            current_quantity=10,
            is_open=True,
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def _rows(self, payload):
        if isinstance(payload, dict) and "results" in payload:
            return payload["results"]
        return payload

    def test_wholesaler_can_list_own_campaigns(self):
        self._auth_as(self.wholesaler)
        res = self.client.get(reverse("campaign-list"))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        rows = self._rows(res.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.campaign.id)

    def test_buyer_cannot_access_campaigns(self):
        self._auth_as(self.buyer)
        res = self.client.get(reverse("campaign-list"))
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_supplier_cannot_access_campaigns(self):
        self._auth_as(self.supplier)
        res = self.client.get(reverse("campaign-list"))
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_cannot_access_campaigns(self):
        self._auth_as(self.admin)
        res = self.client.get(reverse("campaign-list"))
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
