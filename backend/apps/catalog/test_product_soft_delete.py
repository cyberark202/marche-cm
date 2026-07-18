"""R-01 — La suppression d'un produit est un SOFT delete.

`Order.product` étant on_delete=CASCADE, un hard delete détruirait les
commandes (y compris payées/escrow). On prouve que DELETE /api/products/{id}/
désactive le produit (is_active=False), le conserve en base, préserve la
commande liée, et le retire du catalogue public — pour l'admin ET le vendeur.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.accounts.models import UserRole
from apps.catalog.models import Product
from apps.orders.models import Order

User = get_user_model()


@override_settings(
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class ProductSoftDeleteTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.admin = User.objects.create_user(
            username="sd_admin", email="sd_admin@test.local", password="x",
            role=UserRole.GENERAL_ADMIN, is_superuser=True, country_code="CM",
            phone_number="+237690007001")
        self.seller = User.objects.create_user(
            username="sd_seller", email="sd_seller@test.local", password="x",
            role=UserRole.SUPPLIER, country_code="CM", phone_number="+237690007002")
        self.buyer = User.objects.create_user(
            username="sd_buyer", email="sd_buyer@test.local", password="x",
            role=UserRole.BUYER, country_code="CM", phone_number="+237690007003")
        self.product = Product.objects.create(
            seller=self.seller, title="Sac cuir", description="desc", brand="ACME",
            price_for_min_qty=Decimal("5000.00"), price_for_max_qty=Decimal("4500.00"))
        self.order = Order.objects.create(
            buyer=self.buyer, seller=self.seller, product=self.product, quantity=1,
            unit_price=Decimal("5000.00"), total_price=Decimal("5000.00"))

    def _delete(self, user):
        api = APIClient(); api.force_authenticate(user=user)
        return api.delete(f"/api/products/{self.product.id}/")

    def test_admin_delete_is_soft_and_preserves_order(self):
        resp = self._delete(self.admin)
        self.assertIn(resp.status_code, (200, 204), resp.content)
        self.product.refresh_from_db()
        self.assertFalse(self.product.is_active)
        self.assertTrue(Product.objects.filter(id=self.product.id).exists())
        self.assertTrue(Order.objects.filter(id=self.order.id).exists())

    def test_seller_delete_is_soft(self):
        resp = self._delete(self.seller)
        self.assertIn(resp.status_code, (200, 204), resp.content)
        self.product.refresh_from_db()
        self.assertFalse(self.product.is_active)
        self.assertTrue(Order.objects.filter(id=self.order.id).exists())

    def test_deactivated_product_absent_from_public_catalogue(self):
        self._delete(self.admin)
        anon = APIClient()
        resp = anon.get("/api/products/")
        self.assertEqual(resp.status_code, 200, resp.content)
        body = resp.json()
        rows = body["results"] if isinstance(body, dict) and "results" in body else body
        ids = {row["id"] for row in rows}
        self.assertNotIn(self.product.id, ids)

    def test_non_owner_non_admin_cannot_delete(self):
        other = User.objects.create_user(
            username="sd_other", email="sd_other@test.local", password="x",
            role=UserRole.SUPPLIER, country_code="CM", phone_number="+237690007004")
        resp = self._delete(other)
        self.assertIn(resp.status_code, (403, 404), resp.content)
        self.product.refresh_from_db()
        self.assertTrue(self.product.is_active)
