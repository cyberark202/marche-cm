"""Regression tests for the Buyer-app audit fixes (2026-06-18).

Covers:
  * BUG-01 — registration rejects weak passwords (AUTH_PASSWORD_VALIDATORS now
    actually run on the public API).
  * BUG-02 — order creation enforces and decrements stock, and cancellation
    restores it.
  * BUG-03 — orders on inactive products / suspended sellers are rejected.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework import serializers as drf_serializers
from rest_framework.test import APIRequestFactory

from apps.accounts import field_crypto
from apps.accounts.serializers import RegisterSerializer
from apps.catalog.models import Product
from apps.logistics.models import TransportProfile
from apps.orders.models import Order, OrderStatus
from apps.orders.serializers import OrderSerializer
from apps.orders.services import OrderFinanceService
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class BuyerAuditFixTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.buyer = u.objects.create_user(
            username="bx_buyer", email="bx_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000401")
        self.seller = u.objects.create_user(
            username="bx_seller", email="bx_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000402")
        self.transit = u.objects.create_user(
            username="bx_transit", email="bx_transit@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000403")
        TransportProfile.objects.create(
            user=self.transit, company_name="BX Transit", coverage_countries="CM",
            air_price_per_kg=Decimal("200.00"), sea_price_per_kg=Decimal("100.00"), is_active=True)
        self.product = Product.objects.create(
            seller=self.seller, title="Carton", description="local", brand="QA",
            min_order_qty=1, max_order_qty=10, price_for_min_qty=Decimal("1000.00"),
            price_for_max_qty=Decimal("900.00"), weight_kg=Decimal("2.00"),
            available_qty=5, is_active=True)
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("50000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])

    def _create_order(self, quantity):
        request = APIRequestFactory().post("/api/orders/")
        request.user = self.buyer
        serializer = OrderSerializer(
            data={
                "product": self.product.id,
                "quantity": quantity,
                "preferred_transit_agent": self.transit.id,
                "transport_mode": "SEA",
            },
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        return serializer.save()

    def test_register_rejects_weak_password(self):
        serializer = RegisterSerializer(data={
            "name": "Faible", "phone_number": "+237690000999",
            "email": "weak@test.local", "password": "password", "country_code": "CM"})
        self.assertFalse(serializer.is_valid())
        self.assertIn("password", serializer.errors)

    def test_register_rejects_numeric_password(self):
        serializer = RegisterSerializer(data={
            "name": "Numerique", "phone_number": "+237690000998",
            "email": "num@test.local", "password": "12345678", "country_code": "CM"})
        self.assertFalse(serializer.is_valid())
        self.assertIn("password", serializer.errors)

    def test_register_accepts_strong_password(self):
        serializer = RegisterSerializer(data={
            "name": "Solide", "phone_number": "+237690000997",
            "email": "strong@test.local", "password": "Sup3r!Secret2026", "country_code": "CM"})
        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_order_decrements_stock(self):
        self._create_order(2)
        self.product.refresh_from_db()
        self.assertEqual(self.product.available_qty, 3)

    def test_order_rejects_oversell(self):
        with self.assertRaises(drf_serializers.ValidationError):
            self._create_order(8)
        self.product.refresh_from_db()
        self.assertEqual(self.product.available_qty, 5)

    def test_cancel_restores_stock(self):
        order = self._create_order(2)
        self.product.refresh_from_db()
        self.assertEqual(self.product.available_qty, 3)
        OrderFinanceService.cancel_order(order=order, actor=self.buyer, reason="QA")
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CANCELLED)
        self.product.refresh_from_db()
        self.assertEqual(self.product.available_qty, 5)

    def test_order_rejected_for_suspended_seller(self):
        self.seller.is_active = False
        self.seller.save(update_fields=["is_active"])
        with self.assertRaises(drf_serializers.ValidationError):
            self._create_order(1)
        self.assertFalse(Order.objects.filter(buyer=self.buyer).exists())

    def test_order_rejected_for_inactive_product(self):
        self.product.is_active = False
        self.product.save(update_fields=["is_active"])
        with self.assertRaises(drf_serializers.ValidationError):
            self._create_order(1)
