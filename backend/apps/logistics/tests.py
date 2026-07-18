"""Driver-flow regression tests for the D-01/D-02/D-03 fixes.

Audit ref: [D-04] the logistics app previously shipped with zero tests. These
cover the three corrections applied after the 2026-06-18 Zero-Trust audit:

* D-01 — delivery OTP is real (issued to the buyer, verified driver-side) and
  the driver endpoint is reachable (no longer the buyer-only 403 trap).
* D-02 — an un-KYC'd transit agent cannot quote / take a mission.
* D-03 — the logistics escrow pays the agent who actually carried the parcel
  (``shipment.transit_agent``), not a stale ``preferred_transit_agent``.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.logistics.models import DeliveryProof, Shipment, ShipmentStatus, TransportMode
from apps.orders.models import EscrowType, Order, OrderType
from apps.orders.services import OrderFinanceService
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class DriverFixesTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    @classmethod
    def tearDownClass(cls):
        field_crypto.clear_crypto_cache()
        super().tearDownClass()

    def setUp(self):
        User = get_user_model()
        self.admin = User.objects.create_user(
            username="adm_d", email="adm_d@test.local", password="TestPassword123!",
            role="GENERAL_ADMIN", is_verified=True, kyc_level=2, trust_score=Decimal("5.00"),
        )
        self.buyer = User.objects.create_user(
            username="buy_d", email="buy_d@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, trust_score=Decimal("4.00"), country_code="CM",
        )
        self.seller = User.objects.create_user(
            username="sell_d", email="sell_d@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, trust_score=Decimal("4.20"),
            country_code="CN", phone_number="+237690000111",
        )
        # The agent who actually carries the parcel (assigned via accepted quote).
        self.transit = User.objects.create_user(
            username="tr_d", email="tr_d@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, trust_score=Decimal("3.40"),
            country_code="CM", phone_number="+237690000222",
        )
        # A different, stale "preferred" agent picked at order creation time.
        self.decoy = User.objects.create_user(
            username="dec_d", email="dec_d@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, trust_score=Decimal("3.10"),
            country_code="CM", phone_number="+237690000333",
        )
        self.product = Product.objects.create(
            seller=self.seller, title="Machine", description="t", brand="CMTech",
            min_order_qty=1, max_order_qty=10,
            price_for_min_qty=Decimal("500000.00"), price_for_max_qty=Decimal("480000.00"),
            weight_kg=Decimal("100.00"), is_active=True,
        )

    def _make_international_order(self, *, preferred, assigned, status=ShipmentStatus.IN_TRANSIT):
        order = Order.objects.create(
            buyer=self.buyer, seller=self.seller, product=self.product, quantity=1,
            preferred_transit_agent=preferred,
            unit_price=Decimal("500000.00"), total_price=Decimal("500000.00"),
            logistics_price=Decimal("100000.00"), order_type=OrderType.INTERNATIONAL,
            platform_commission_rate=Decimal("0.05"),
        )
        shipment = Shipment.objects.create(
            order=order, buyer=self.buyer, seller=self.seller, transit_agent=assigned,
            pickup_address="Shanghai", dropoff_address="Douala", country_code="CM",
            transport_mode=TransportMode.SEA, shipping_fee=Decimal("100000.00"), status=status,
        )
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("700000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])
        return order, shipment

    def _drive_to_shipping(self, order):
        """Lock funds and release the supplier escrow so the order is SHIPPING."""
        OrderFinanceService.lock_funds_for_order(
            order=order, actor=self.buyer,
            supplier_amount=Decimal("500000.00"), logistics_amount=Decimal("100000.00"),
            idempotency_key=f"order-{order.id}-lock",
        )
        OrderFinanceService.register_supplier_confirmation(order=order, actor=order.shipment.transit_agent)
        proof = SimpleUploadedFile("invoice.pdf", b"%PDF-1.4 fake", content_type="application/pdf")
        OrderFinanceService.register_supplier_purchase_proof(
            order=order, actor=order.shipment.transit_agent, proof_file=proof
        )
        OrderFinanceService.admin_validate_supplier(order=order, actor=self.admin, approve=True, note="OK")
        order.refresh_from_db()

    # ── D-02 ────────────────────────────────────────────────────────────────
    def test_unverified_driver_cannot_quote(self):
        unverified = get_user_model().objects.create_user(
            username="nokyc", email="nokyc@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=False, kyc_level=0, country_code="CM",
        )
        order, shipment = self._make_international_order(
            preferred=self.transit, assigned=None, status=ShipmentStatus.PICKUP_PENDING
        )
        payload = {"shipment": shipment.id, "fee": "90000", "eta_days": 3}
        client = APIClient()
        client.force_authenticate(user=unverified)
        resp = client.post(f"/api/shipments/{shipment.id}/post_quote/", payload)
        self.assertEqual(resp.status_code, 403)

        client.force_authenticate(user=self.transit)
        ok = client.post(f"/api/shipments/{shipment.id}/post_quote/", payload)
        self.assertEqual(ok.status_code, 201)

    # ── D-01 ────────────────────────────────────────────────────────────────
    def test_delivery_otp_is_real_and_driver_can_confirm(self):
        order, shipment = self._make_international_order(preferred=self.transit, assigned=self.transit)
        self._drive_to_shipping(order)
        client = APIClient()
        client.force_authenticate(user=self.transit)

        # Issue: the buyer receives a code; only its hash is stored.
        issued = client.post(f"/api/shipments/{shipment.id}/issue_delivery_otp/")
        self.assertEqual(issued.status_code, 200)
        shipment.refresh_from_db()
        self.assertTrue(shipment.delivery_otp_hash)
        self.assertIsNotNone(shipment.delivery_otp_expires_at)

        # The plaintext code is never returned to the driver — recover it for the
        # test from the buyer's notification (where it is legitimately delivered).
        import re
        from apps.notifications.models import Notification
        note = Notification.objects.filter(user=self.buyer, title="Code de livraison").latest("created_at")
        code = re.search(r"\b(\d{4})\b", note.body).group(1)
        self.assertTrue(check_password(code, shipment.delivery_otp_hash))

        # Wrong code is rejected (OTP is enforced, not cosmetic).
        bad = client.post(f"/api/shipments/{shipment.id}/confirm_delivery/", {"otp": "0000" if code != "0000" else "1111"})
        self.assertEqual(bad.status_code, 400)

        # Correct code but no photo proof yet → blocked.
        no_proof = client.post(f"/api/shipments/{shipment.id}/confirm_delivery/", {"otp": code})
        self.assertEqual(no_proof.status_code, 400)

        # Add proof, then confirm with the correct code → DELIVERED + payout.
        DeliveryProof.objects.create(shipment=shipment, signed_by="Client", validated=False)
        good = client.post(f"/api/shipments/{shipment.id}/confirm_delivery/", {"otp": code})
        self.assertEqual(good.status_code, 200)
        shipment.refresh_from_db()
        self.assertEqual(shipment.status, ShipmentStatus.DELIVERED)
        self.assertEqual(shipment.delivery_otp_hash, "")  # single-use, burned

        transit_wallet = Wallet.objects.get(owner=self.transit)
        payout = transit_wallet.transactions.filter(kind="PAYOUT_LOGISTICS").first()
        self.assertIsNotNone(payout)
        # Commission plateforme de 10% sur le payout livreur : 100000 -> 90000 net.
        self.assertEqual(abs(payout.amount), Decimal("90000.00"))

    def test_driver_confirm_is_not_a_buyer_only_403(self):
        # Regression for the old trap: the driver hitting the delivery endpoint
        # must not get an authorization 403 (it used to call validate_delivery).
        order, shipment = self._make_international_order(preferred=self.transit, assigned=self.transit)
        client = APIClient()
        client.force_authenticate(user=self.transit)
        resp = client.post(f"/api/shipments/{shipment.id}/confirm_delivery/", {"otp": "1234"})
        self.assertNotEqual(resp.status_code, 403)
        self.assertEqual(resp.status_code, 400)  # no active OTP → business 400, not auth 403

    # ── D-03 ────────────────────────────────────────────────────────────────
    def test_release_pays_actual_carrier_not_stale_preferred(self):
        # preferred (decoy) != assigned (transit) — money must follow the carrier.
        order, shipment = self._make_international_order(preferred=self.decoy, assigned=self.transit)
        self._drive_to_shipping(order)
        OrderFinanceService.release_logistics_escrow_after_buyer_confirmation(order=order, actor=self.buyer)

        carrier_payout = Wallet.objects.get(owner=self.transit).transactions.filter(kind="PAYOUT_LOGISTICS").first()
        self.assertIsNotNone(carrier_payout)
        # Commission plateforme de 10% sur le payout livreur : 100000 -> 90000 net.
        self.assertEqual(abs(carrier_payout.amount), Decimal("90000.00"))

        decoy_wallet = Wallet.objects.filter(owner=self.decoy).first()
        if decoy_wallet:
            self.assertFalse(decoy_wallet.transactions.filter(kind="PAYOUT_LOGISTICS").exists())
        order.refresh_from_db()
        self.assertEqual(order.escrows.get(escrow_type=EscrowType.LOGISTICS).beneficiary_id, self.decoy.id)
