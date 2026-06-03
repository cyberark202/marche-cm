"""C-1 — End-to-end supplier product creation through the real API stack.

Drives the canonical payload a corrected mobile client sends and asserts the
product is created, active, correctly priced, and visible publicly + under
/products/mine/.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class SupplierProductCreationE2ETests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.supplier = get_user_model().objects.create_user(
            username="c1e2e_sup", email="c1e2e_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000601")
        self.buyer = get_user_model().objects.create_user(
            username="c1e2e_buy", email="c1e2e_buy@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=1, country_code="CM",
            phone_number="+237690000602")

    def test_full_supplier_creation_flow(self):
        sup = APIClient()
        sup.force_authenticate(user=self.supplier)
        payload = {
            "title": "Savon de Marseille", "description": "carton 48 pains", "brand": "Azur",
            "category_name": "Hygiene", "weight_kg": "12",
            "min_order_qty": 2, "max_order_qty": 40,
            "price_for_min_qty": 22000, "price_for_max_qty": 20000, "is_active": True,
        }
        created = sup.post("/api/products/", payload, format="json")
        self.assertEqual(created.status_code, 201, created.content)
        pid = created.data["id"]
        self.assertTrue(created.data["is_active"])
        self.assertEqual(Decimal(str(created.data["price_for_min_qty"])), Decimal("22000.00"))
        self.assertEqual(Decimal(str(created.data["price_for_max_qty"])), Decimal("20000.00"))

        # Visible in the public (anonymous) catalogue.
        anon = APIClient()
        public = anon.get("/api/products/")
        self.assertEqual(public.status_code, 200)
        ids = [row["id"] for row in public.data["results"]]
        self.assertIn(pid, ids)

        # Visible under the supplier's own listing.
        mine = sup.get("/api/products/mine/")
        self.assertEqual(mine.status_code, 200)
        self.assertIn(pid, [row["id"] for row in mine.data])

        # A buyer still cannot create a product (role guard intact).
        buy = APIClient()
        buy.force_authenticate(user=self.buyer)
        denied = buy.post("/api/products/", payload, format="json")
        self.assertEqual(denied.status_code, 403, denied.content)
