"""Tests avis produits (Lot 4) : reponse vendeur + agregat produit.

Couvre l'ajout du droit de reponse du vendeur et l'exposition photo/reponse
dans l'agregat /api/products/{id}/reviews/.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient, APIRequestFactory

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.orders.models import Order, OrderStatus
from apps.orders.serializers import OrderSerializer
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class ProductReviewTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.buyer = u.objects.create_user(
            username="rev_buyer", email="rev_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000701")
        self.seller = u.objects.create_user(
            username="rev_seller", email="rev_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000702")
        self.product = Product.objects.create(
            seller=self.seller, title="Rev Carton", description="local", brand="QA",
            min_order_qty=1, max_order_qty=10, price_for_min_qty=Decimal("1000.00"),
            price_for_max_qty=Decimal("900.00"), weight_kg=Decimal("2.00"),
            available_qty=5, is_active=True)
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("50000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])
        self.order = self._completed_order()

    def _completed_order(self):
        request = APIRequestFactory().post("/api/orders/")
        request.user = self.buyer
        serializer = OrderSerializer(
            data={"product": self.product.id, "quantity": 1},
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        order = serializer.save()
        Order.objects.filter(pk=order.pk).update(status=OrderStatus.COMPLETED)
        order.refresh_from_db()
        return order

    def test_buyer_reviews_then_seller_replies_and_aggregate_exposes_both(self):
        buyer_c = APIClient()
        buyer_c.force_authenticate(self.buyer)
        r = buyer_c.post(
            f"/api/orders/{self.order.id}/review/",
            {"rating": 5, "comment": "Excellent produit"}, format="json")
        self.assertEqual(r.status_code, 201, r.content)

        seller_c = APIClient()
        seller_c.force_authenticate(self.seller)
        reply = seller_c.post(
            f"/api/orders/{self.order.id}/review-reply/",
            {"reply": "Merci pour votre confiance !"}, format="json")
        self.assertEqual(reply.status_code, 200, reply.content)
        self.assertEqual(reply.json()["seller_reply"], "Merci pour votre confiance !")

        agg = buyer_c.get(f"/api/products/{self.product.id}/reviews/").json()
        self.assertEqual(agg["reviews_count"], 1)
        self.assertEqual(agg["average_rating"], 5.0)
        self.assertEqual(agg["reviews"][0]["seller_reply"], "Merci pour votre confiance !")

    def test_non_seller_cannot_reply(self):
        buyer_c = APIClient()
        buyer_c.force_authenticate(self.buyer)
        buyer_c.post(
            f"/api/orders/{self.order.id}/review/",
            {"rating": 4, "comment": "Bien"}, format="json")
        resp = buyer_c.post(
            f"/api/orders/{self.order.id}/review-reply/",
            {"reply": "auto-reponse"}, format="json")
        self.assertEqual(resp.status_code, 403)

    def test_reply_requires_existing_review(self):
        seller_c = APIClient()
        seller_c.force_authenticate(self.seller)
        resp = seller_c.post(
            f"/api/orders/{self.order.id}/review-reply/",
            {"reply": "reponse sans avis"}, format="json")
        self.assertEqual(resp.status_code, 404)
