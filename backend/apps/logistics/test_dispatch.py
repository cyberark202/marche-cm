"""Tests du dispatch automatique (docs 03 R6 / 07).

Règles couvertes :
- Aucun livreur n'est sollicité à la création de la commande (R6) ;
- L'acceptation vendeur déclenche une offre au livreur vérifié le plus proche ;
- Un livreur non vérifié ne reçoit jamais d'offre ;
- Un refus fait cascader l'offre au candidat suivant (repli diffusion large).
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient, APIRequestFactory

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.logistics.models import DispatchOffer, DispatchOfferStatus, TransportProfile
from apps.notifications.models import Notification
from apps.orders.serializers import OrderSerializer
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class DriverDispatchTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.buyer = u.objects.create_user(
            username="disp_buyer", email="disp_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000601")
        self.seller = u.objects.create_user(
            username="disp_seller", email="disp_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000602",
            location_latitude=4.05, location_longitude=9.70)
        self.driver = u.objects.create_user(
            username="disp_driver", email="disp_driver@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000603",
            location_latitude=4.06, location_longitude=9.71)
        self.far_driver = u.objects.create_user(
            username="disp_driver_far", email="disp_driver_far@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000605",
            location_latitude=3.87, location_longitude=11.52)
        self.unverified_driver = u.objects.create_user(
            username="disp_driver2", email="disp_driver2@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=False, kyc_level=1, country_code="CM", phone_number="+237690000604")
        for user, name in ((self.driver, "Disp Transit"), (self.far_driver, "Disp Transit Far"),
                           (self.unverified_driver, "Disp Transit 2")):
            TransportProfile.objects.create(
                user=user, company_name=name, coverage_countries="CM",
                air_price_per_kg=Decimal("200.00"), sea_price_per_kg=Decimal("100.00"), is_active=True)
        self.product = Product.objects.create(
            seller=self.seller, title="Disp Carton", description="local", brand="QA",
            min_order_qty=1, max_order_qty=10, price_for_min_qty=Decimal("1000.00"),
            price_for_max_qty=Decimal("900.00"), weight_kg=Decimal("2.00"),
            available_qty=5, is_active=True)
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("50000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])

    def _create_order(self):
        request = APIRequestFactory().post("/api/orders/")
        request.user = self.buyer
        serializer = OrderSerializer(
            data={"product": self.product.id, "quantity": 1},
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        return serializer.save()

    def _accept_as_seller(self, order):
        client = APIClient()
        client.force_authenticate(self.seller)
        return client.post(f"/api/orders/{order.id}/accept/")

    def test_no_driver_solicited_at_order_creation(self):
        """Doc 03 R6 : aucun livreur sollicité tant que le vendeur n'a pas accepté."""
        self._create_order()
        self.assertFalse(DispatchOffer.objects.exists())
        self.assertFalse(
            Notification.objects.filter(user=self.driver, title="Nouvelle mission de livraison").exists()
        )

    def test_seller_accept_dispatches_to_nearest_verified_driver(self):
        order = self._create_order()
        res = self._accept_as_seller(order)
        self.assertEqual(res.status_code, 200)
        offer = DispatchOffer.objects.get()
        self.assertEqual(offer.driver_id, self.driver.id)
        self.assertEqual(offer.status, DispatchOfferStatus.PENDING)
        self.assertTrue(
            Notification.objects.filter(user=self.driver, title="Nouvelle mission de livraison").exists()
        )

    def test_unverified_driver_never_offered(self):
        order = self._create_order()
        self._accept_as_seller(order)
        self.assertFalse(DispatchOffer.objects.filter(driver=self.unverified_driver).exists())
        self.assertFalse(Notification.objects.filter(user=self.unverified_driver).exists())

    def test_refusal_cascades_to_next_driver(self):
        order = self._create_order()
        self._accept_as_seller(order)
        offer = DispatchOffer.objects.get(driver=self.driver)
        client = APIClient()
        client.force_authenticate(self.driver)
        res = client.post(f"/api/dispatch-offers/{offer.id}/refuse/")
        self.assertEqual(res.status_code, 200)
        offer.refresh_from_db()
        self.assertEqual(offer.status, DispatchOfferStatus.REFUSED)
        next_offer = DispatchOffer.objects.get(driver=self.far_driver)
        self.assertEqual(next_offer.status, DispatchOfferStatus.PENDING)

    def test_driver_accept_assigns_shipment_and_cancels_others(self):
        order = self._create_order()
        self._accept_as_seller(order)
        offer = DispatchOffer.objects.get(driver=self.driver)
        client = APIClient()
        client.force_authenticate(self.driver)
        res = client.post(f"/api/dispatch-offers/{offer.id}/accept/")
        self.assertEqual(res.status_code, 200)
        order.refresh_from_db()
        self.assertEqual(order.shipment.transit_agent_id, self.driver.id)
