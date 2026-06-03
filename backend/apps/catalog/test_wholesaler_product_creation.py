"""M-4 — Wholesaler product creation with server-derived prices.

A wholesaler only provides `available_qty` + `unit_price`; the serializer derives
price_for_min_qty / price_for_max_qty (= unit_price) and min/max order qty
server-side. Previously this 400'd because those price fields were required at
the field level, before validate() could fill them.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import Product


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class WholesalerProductCreationTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.wholesaler = u.objects.create_user(
            username="m4_wh", email="m4_wh@test.local", password="TestPassword123!",
            role="WHOLESALER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690001001")
        self.supplier = u.objects.create_user(
            username="m4_sup", email="m4_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690001002")

    def test_wholesaler_creates_with_only_qty_and_unit_price(self):
        client = APIClient()
        client.force_authenticate(user=self.wholesaler)
        body = {
            "title": "Carton de savon", "description": "lot 48", "brand": "Azur",
            "category_name": "Hygiene", "weight_kg": "12",
            "available_qty": 50, "unit_price": 3000,
        }
        r = client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        p = Product.objects.get(id=r.data["id"])
        self.assertEqual(p.unit_price, Decimal("3000.00"))
        self.assertEqual(p.available_qty, 50)
        self.assertEqual(p.price_for_min_qty, Decimal("3000.00"))
        self.assertEqual(p.price_for_max_qty, Decimal("3000.00"))
        self.assertEqual(p.min_order_qty, 1)
        self.assertEqual(p.max_order_qty, 50)
        self.assertTrue(p.is_active)

    def test_wholesaler_missing_unit_price_rejected(self):
        client = APIClient()
        client.force_authenticate(user=self.wholesaler)
        body = {
            "title": "Carton incomplet", "description": "lot", "brand": "Azur",
            "category_name": "Hygiene", "weight_kg": "12", "available_qty": 50,
        }
        r = client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 400, r.content)

    def test_supplier_still_must_provide_prices(self):
        """No regression: a supplier omitting prices is still rejected."""
        client = APIClient()
        client.force_authenticate(user=self.supplier)
        body = {
            "title": "Sans prix", "description": "x", "brand": "QA",
            "category_name": "Divers", "weight_kg": "2",
            "min_order_qty": 10, "max_order_qty": 100,
        }
        r = client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 400, r.content)
