"""Modération produit (docs 12/22) : filtre statut réservé admin + action moderate."""
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto

from .models import Product, ProductStatus


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class ProductModerationTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.seller = u.objects.create_user(
            username="mod_sup", email="mod_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, phone_number="+237690000901")
        self.admin = u.objects.create_user(
            username="mod_adm", email="mod_adm@test.local", password="TestPassword123!",
            role="GENERAL_ADMIN", is_verified=True, is_staff=True, phone_number="+237690000902")
        self.published = Product.objects.create(
            seller=self.seller, title="Visible", description="d",
            weight_kg=1, available_qty=5, unit_price=1000,
            min_order_qty=1, max_order_qty=5, price_for_min_qty=1000, price_for_max_qty=1000,
            status=ProductStatus.PUBLISHED,
            is_active=True)
        self.suspended = Product.objects.create(
            seller=self.seller, title="Suspendu", description="d",
            weight_kg=1, available_qty=5, unit_price=1000,
            min_order_qty=1, max_order_qty=5, price_for_min_qty=1000, price_for_max_qty=1000,
            status=ProductStatus.SUSPENDED,
            is_active=False)

    def _ids(self, response):
        rows = response.data["results"] if "results" in response.data else response.data
        return [row["id"] for row in rows]

    def test_admin_can_list_by_status(self):
        client = APIClient()
        client.force_authenticate(self.admin)
        res = client.get("/api/products/", {"status": "SUSPENDED"})
        self.assertEqual(res.status_code, 200)
        self.assertIn(self.suspended.id, self._ids(res))
        self.assertNotIn(self.published.id, self._ids(res))

    def test_non_admin_status_param_ignored(self):
        client = APIClient()
        client.force_authenticate(self.seller)
        res = client.get("/api/products/", {"status": "SUSPENDED"})
        self.assertEqual(res.status_code, 200)
        self.assertNotIn(self.suspended.id, self._ids(res))
        self.assertIn(self.published.id, self._ids(res))

    def test_moderate_suspend_then_restore(self):
        client = APIClient()
        client.force_authenticate(self.admin)
        res = client.post(f"/api/products/{self.published.id}/moderate/",
                          {"action": "suspend", "reason": "signalement"}, format="json")
        self.assertEqual(res.status_code, 200, res.content)
        self.published.refresh_from_db()
        self.assertEqual(self.published.status, ProductStatus.SUSPENDED)
        res = client.post(f"/api/products/{self.published.id}/moderate/",
                          {"action": "restore"}, format="json")
        self.assertEqual(res.status_code, 200, res.content)
        self.published.refresh_from_db()
        self.assertEqual(self.published.status, ProductStatus.PUBLISHED)

    def test_moderate_forbidden_for_seller(self):
        client = APIClient()
        client.force_authenticate(self.seller)
        res = client.post(f"/api/products/{self.published.id}/moderate/",
                          {"action": "suspend"}, format="json")
        self.assertEqual(res.status_code, 403)
