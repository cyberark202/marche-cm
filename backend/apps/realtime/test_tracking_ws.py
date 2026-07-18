"""Test d'integration du flux de suivi GPS temps reel (TrackingConsumer).

Prouve le flux complet livreur -> backend -> acheteur/vendeur :
  * le livreur ASSIGNE (transit_agent) envoie une position ;
  * l'acheteur ET le vendeur connectes la recoivent en direct ;
  * la position « derniere connue » est persistee sur le Shipment ;
  * un tiers non-participant est refuse (close 4003) ;
  * l'acheteur ne peut PAS spoofer une position (anti-GPS-spoof).

On teste `URLRouter(all_ws_patterns)` directement : le consumer fait sa propre
auth via le sous-protocole `bearer,<jwt>`, donc on n'a pas besoin du
AllowedHostsOriginValidator (qui exigerait un header Origin) ni de
AuthMiddlewareStack (session). Test DB sqlite = FICHIER -> partage entre les
threads de `database_sync_to_async` (d'ou TransactionTestCase, pas TestCase).
"""

from decimal import Decimal

from asgiref.sync import async_to_sync
from channels.db import database_sync_to_async
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.contrib.auth import get_user_model
from django.test import TransactionTestCase, override_settings
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.logistics.models import Shipment, ShipmentStatus, TransportMode
from apps.orders.models import Order, OrderType
from apps.realtime.routing import websocket_urlpatterns


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class TrackingWebSocketFlowTest(TransactionTestCase):
    def setUp(self):
        field_crypto.clear_crypto_cache()
        User = get_user_model()
        self.buyer = User.objects.create_user(
            username="ws_buy", email="ws_buy@t.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM",
        )
        self.seller = User.objects.create_user(
            username="ws_sell", email="ws_sell@t.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CN",
            phone_number="+237690000111",
        )
        self.driver = User.objects.create_user(
            username="ws_drv", email="ws_drv@t.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000222",
        )
        self.outsider = User.objects.create_user(
            username="ws_out", email="ws_out@t.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM",
        )
        self.product = Product.objects.create(
            seller=self.seller, title="Machine", description="t", brand="CMTech",
            min_order_qty=1, max_order_qty=10,
            price_for_min_qty=Decimal("500000.00"), price_for_max_qty=Decimal("480000.00"),
            weight_kg=Decimal("100.00"), is_active=True,
        )
        self.order = Order.objects.create(
            buyer=self.buyer, seller=self.seller, product=self.product, quantity=1,
            unit_price=Decimal("500000.00"), total_price=Decimal("500000.00"),
            logistics_price=Decimal("100000.00"), order_type=OrderType.INTERNATIONAL,
            platform_commission_rate=Decimal("0.05"),
        )
        self.shipment = Shipment.objects.create(
            order=self.order, buyer=self.buyer, seller=self.seller, transit_agent=self.driver,
            pickup_address="Shanghai", dropoff_address="Douala", country_code="CM",
            transport_mode=TransportMode.SEA, shipping_fee=Decimal("100000.00"),
            status=ShipmentStatus.IN_TRANSIT,
        )
        # Les JWT sont generes ICI (contexte SYNC) — `RefreshToken.for_user`
        # touche la DB et ne peut pas etre appele depuis le coroutine de test.
        self.tokens = {u.id: str(RefreshToken.for_user(u).access_token)
                       for u in (self.buyer, self.seller, self.driver, self.outsider)}

    def tearDown(self):
        field_crypto.clear_crypto_cache()

    # ---- helpers -----------------------------------------------------------

    def _app(self):
        return URLRouter(websocket_urlpatterns)

    async def _connect(self, user):
        comm = WebsocketCommunicator(
            self._app(),
            f"/ws/tracking/{self.shipment.id}/",
            subprotocols=["bearer", self.tokens[user.id]],
        )
        connected, _ = await comm.connect()
        return comm, connected

    # ---- tests -------------------------------------------------------------

    def test_driver_position_reaches_buyer_and_seller_and_persists(self):
        async_to_sync(self._flow)()

    async def _flow(self):
        driver_comm, dconn = await self._connect(self.driver)
        buyer_comm, bconn = await self._connect(self.buyer)
        seller_comm, sconn = await self._connect(self.seller)
        try:
            self.assertTrue(dconn, "livreur assigne doit pouvoir se connecter")
            self.assertTrue(bconn, "acheteur doit pouvoir se connecter")
            self.assertTrue(sconn, "vendeur doit pouvoir se connecter")

            await driver_comm.send_json_to({
                "type": "location_update",
                "latitude": 4.05,
                "longitude": 9.70,
                "timestamp": "2026-06-28T10:00:00Z",
            })

            buyer_msg = await buyer_comm.receive_json_from(timeout=5)
            seller_msg = await seller_comm.receive_json_from(timeout=5)

            self.assertEqual(buyer_msg["type"], "location_update")
            self.assertAlmostEqual(buyer_msg["latitude"], 4.05)
            self.assertAlmostEqual(buyer_msg["longitude"], 9.70)
            self.assertEqual(seller_msg["type"], "location_update")
            self.assertAlmostEqual(seller_msg["latitude"], 4.05)

            shipment = await database_sync_to_async(Shipment.objects.get)(pk=self.shipment.id)
            self.assertIsNotNone(shipment.current_latitude)
            self.assertEqual(float(shipment.current_latitude), 4.05)
            self.assertEqual(float(shipment.current_longitude), 9.70)
            self.assertIsNotNone(shipment.location_updated_at)
        finally:
            await driver_comm.disconnect()
            await buyer_comm.disconnect()
            await seller_comm.disconnect()

    def test_non_participant_is_rejected(self):
        async_to_sync(self._outsider)()

    async def _outsider(self):
        comm, connected = await self._connect(self.outsider)
        self.assertFalse(connected, "un tiers non-participant doit etre refuse")
        if connected:
            await comm.disconnect()

    def test_buyer_cannot_spoof_gps(self):
        async_to_sync(self._spoof)()

    async def _spoof(self):
        buyer_comm, bconn = await self._connect(self.buyer)
        driver_comm, dconn = await self._connect(self.driver)
        try:
            self.assertTrue(bconn)
            self.assertTrue(dconn)
            # L'acheteur (autorise a VOIR) tente d'injecter une fausse position.
            await buyer_comm.send_json_to({
                "type": "location_update",
                "latitude": 0.0, "longitude": 0.0, "timestamp": "x",
            })
            # Le spoof est ignore : aucune rediffusion -> le livreur ne recoit rien.
            self.assertTrue(await driver_comm.receive_nothing(timeout=1))
            # Et rien n'a ete persiste.
            shipment = await database_sync_to_async(Shipment.objects.get)(pk=self.shipment.id)
            self.assertIsNone(shipment.current_latitude)
        finally:
            await buyer_comm.disconnect()
            await driver_comm.disconnect()
