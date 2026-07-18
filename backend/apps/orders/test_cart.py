"""Tests du panier serveur (Lot 2) : upsert idempotent + checkout groupe.

Le checkout reutilise OrderSerializer : on verifie qu'il cree bien une Order
par article, vide le panier, decremente le stock, et roll-back tout si un
article echoue (fonds insuffisants) — sans jamais toucher au moteur escrow.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.orders.models import CartItem, Order
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class CartServerTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.buyer = u.objects.create_user(
            username="cart_buyer", email="cart_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000501")
        self.seller = u.objects.create_user(
            username="cart_seller", email="cart_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000502")
        self.product_a = Product.objects.create(
            seller=self.seller, title="Cart Sac", description="local", brand="QA",
            min_order_qty=1, max_order_qty=10, price_for_min_qty=Decimal("1000.00"),
            price_for_max_qty=Decimal("900.00"), weight_kg=Decimal("2.00"),
            available_qty=5, is_active=True)
        self.product_b = Product.objects.create(
            seller=self.seller, title="Cart Boite", description="local", brand="QA",
            min_order_qty=1, max_order_qty=10, price_for_min_qty=Decimal("500.00"),
            price_for_max_qty=Decimal("450.00"), weight_kg=Decimal("1.00"),
            available_qty=8, is_active=True)
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("50000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])
        self.client = APIClient()
        self.client.force_authenticate(self.buyer)

    @staticmethod
    def _rows(response):
        data = response.json()
        return data["results"] if isinstance(data, dict) and "results" in data else data

    def test_add_to_cart_is_idempotent_upsert(self):
        r1 = self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 2}, format="json")
        self.assertEqual(r1.status_code, 201)
        # Meme produit : met a jour la quantite, ne cree pas de doublon.
        r2 = self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 3}, format="json")
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(CartItem.objects.filter(buyer=self.buyer).count(), 1)
        self.assertEqual(CartItem.objects.get(buyer=self.buyer, product=self.product_a).quantity, 3)

    def test_list_returns_live_price_and_availability(self):
        self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 2}, format="json")
        rows = self._rows(self.client.get("/api/cart/"))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["unit_price"], "1000.00")
        self.assertEqual(rows[0]["line_total"], "2000.00")
        self.assertTrue(rows[0]["is_available"])

    def test_checkout_creates_one_order_per_item_and_clears_cart(self):
        self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 2}, format="json")
        self.client.post("/api/cart/", {"product": self.product_b.id, "quantity": 1}, format="json")
        resp = self.client.post("/api/cart/checkout/")
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertEqual(resp.json()["count"], 2)
        self.assertEqual(Order.objects.filter(buyer=self.buyer).count(), 2)
        # Panier vide apres checkout.
        self.assertEqual(CartItem.objects.filter(buyer=self.buyer).count(), 0)
        # Stock decremente.
        self.product_a.refresh_from_db()
        self.assertEqual(self.product_a.available_qty, 3)

    def test_checkout_empty_cart_rejected(self):
        resp = self.client.post("/api/cart/checkout/")
        self.assertEqual(resp.status_code, 400)

    def test_checkout_rolls_back_when_funds_insufficient(self):
        wallet = Wallet.objects.get(owner=self.buyer)
        wallet.available_balance = Decimal("100.00")  # trop peu pour 2000 + livraison
        wallet.save(update_fields=["available_balance"])
        self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 2}, format="json")
        resp = self.client.post("/api/cart/checkout/")
        self.assertEqual(resp.status_code, 400)
        # Rien cree, panier intact, stock intact.
        self.assertEqual(Order.objects.filter(buyer=self.buyer).count(), 0)
        self.assertEqual(CartItem.objects.filter(buyer=self.buyer).count(), 1)
        self.product_a.refresh_from_db()
        self.assertEqual(self.product_a.available_qty, 5)

    def test_remove_deletes_by_product(self):
        self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 2}, format="json")
        self.client.post("/api/cart/", {"product": self.product_b.id, "quantity": 1}, format="json")
        resp = self.client.post("/api/cart/remove/", {"product": self.product_a.id}, format="json")
        self.assertEqual(resp.status_code, 204)
        remaining = CartItem.objects.filter(buyer=self.buyer)
        self.assertEqual(remaining.count(), 1)
        self.assertEqual(remaining.first().product_id, self.product_b.id)

    def test_clear_empties_cart(self):
        self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 2}, format="json")
        self.client.post("/api/cart/", {"product": self.product_b.id, "quantity": 1}, format="json")
        resp = self.client.post("/api/cart/clear/")
        self.assertEqual(resp.status_code, 204)
        self.assertEqual(CartItem.objects.filter(buyer=self.buyer).count(), 0)

    def test_cart_is_private_to_owner(self):
        self.client.post("/api/cart/", {"product": self.product_a.id, "quantity": 1}, format="json")
        other = get_user_model().objects.create_user(
            username="cart_intruder", email="cart_intruder@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000503")
        intruder = APIClient()
        intruder.force_authenticate(other)
        self.assertEqual(len(self._rows(intruder.get("/api/cart/"))), 0)
