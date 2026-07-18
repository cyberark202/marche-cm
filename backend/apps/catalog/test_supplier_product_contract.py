"""C-1 — Supplier product creation contract alignment.

The mobile supplier form historically POSTed keys (`category`, `min_qty`,
`max_qty`) that did not match ProductSerializer, so every creation 400'd. We now
accept BOTH the canonical keys and the legacy aliases (backward compatible), and
we reject genuinely inverted prices.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import Product


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class SupplierProductContractTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.supplier = get_user_model().objects.create_user(
            username="c1_sup", email="c1_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000501")
        self.client = APIClient()
        self.client.force_authenticate(user=self.supplier)

    def _canonical(self, **over):
        body = {
            "title": "Huile de palme", "description": "bidon 20L", "brand": "Tropical",
            "category_name": "Agroalimentaire", "weight_kg": "20",
            "available_qty": 100, "unit_price": 5000, "is_active": True,
        }
        body.update(over)
        return body

    def test_canonical_payload_is_accepted(self):
        r = self.client.post("/api/products/", self._canonical(), format="json")
        self.assertEqual(r.status_code, 201, r.content)
        p = Product.objects.get(id=r.data["id"])
        self.assertEqual(p.min_order_qty, 1)
        self.assertEqual(p.max_order_qty, 100)
        self.assertEqual(p.price_for_min_qty, Decimal("5000.00"))
        self.assertEqual(p.price_for_max_qty, Decimal("5000.00"))
        self.assertEqual(p.category.name, "Agroalimentaire")

    def test_category_alias_is_accepted(self):
        """Ancien build : la clé `category` (nom) est acceptée comme alias."""
        body = {
            "title": "Riz parfumé", "description": "sac 25kg", "brand": "Delice",
            "category": "Cereales", "weight_kg": "25",
            "available_qty": 50, "unit_price": 18000,
        }
        r = self.client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 201, r.content)
        p = Product.objects.get(id=r.data["id"])
        self.assertEqual(p.max_order_qty, 50)
        self.assertEqual(p.category.name, "Cereales")

    def test_missing_unit_price_rejected(self):
        body = self._canonical()
        body.pop("unit_price")
        r = self.client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 400, r.content)

    def test_missing_category_rejected(self):
        body = self._canonical()
        body.pop("category_name")
        r = self.client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 400, r.content)

    def test_missing_qty_rejected(self):
        body = self._canonical()
        body.pop("available_qty")
        r = self.client.post("/api/products/", body, format="json")
        self.assertEqual(r.status_code, 400, r.content)
