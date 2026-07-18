from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings

from apps.accounts import field_crypto

from apps.catalog.models import Product
from apps.logistics.models import Shipment, TransportMode
from apps.orders.models import EscrowType, Order, OrderType
from apps.orders.services import FraudRiskError, OrderFinanceService
from apps.wallets.models import Wallet


class SplitEscrowServiceTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls._enc_override = override_settings(
            NOTCHPAY_ENABLED=False,
            DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
        )
        cls._enc_override.enable()
        field_crypto.clear_crypto_cache()

    @classmethod
    def tearDownClass(cls):
        cls._enc_override.disable()
        field_crypto.clear_crypto_cache()
        super().tearDownClass()

    def setUp(self):
        user_model = get_user_model()
        self.admin = user_model.objects.create_user(
            username="admin_split",
            email="admin_split@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_verified=True,
            kyc_level=2,
            trust_score=Decimal("5.00"),
        )
        self.buyer = user_model.objects.create_user(
            username="buyer_split",
            email="buyer_split@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_verified=True,
            kyc_level=2,
            trust_score=Decimal("4.00"),
            country_code="CM",
        )
        self.seller = user_model.objects.create_user(
            username="seller_split",
            email="seller_split@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_verified=True,
            kyc_level=2,
            trust_score=Decimal("4.20"),
            country_code="CN",
            phone_number="+237690000111",
        )
        self.transit = user_model.objects.create_user(
            username="transit_split",
            email="transit_split@test.local",
            password="TestPassword123!",
            role="TRANSIT_AGENT",
            is_verified=True,
            kyc_level=2,
            trust_score=Decimal("3.40"),
            country_code="CM",
            phone_number="+237690000222",
        )
        self.product = Product.objects.create(
            seller=self.seller,
            title="Machine industrielle",
            description="Produit test split escrow",
            brand="CMTech",
            min_order_qty=1,
            max_order_qty=10,
            price_for_min_qty=Decimal("500000.00"),
            price_for_max_qty=Decimal("480000.00"),
            weight_kg=Decimal("100.00"),
            is_active=True,
        )
        self.order = Order.objects.create(
            buyer=self.buyer,
            seller=self.seller,
            product=self.product,
            quantity=1,
            preferred_transit_agent=self.transit,
            unit_price=Decimal("500000.00"),
            total_price=Decimal("500000.00"),
            logistics_price=Decimal("100000.00"),
            order_type=OrderType.INTERNATIONAL,
            platform_commission_rate=Decimal("0.05"),
        )
        self.shipment = Shipment.objects.create(
            order=self.order,
            buyer=self.buyer,
            seller=self.seller,
            transit_agent=self.transit,
            pickup_address="Shanghai",
            dropoff_address="Douala",
            country_code="CM",
            transport_mode=TransportMode.SEA,
            shipping_fee=Decimal("100000.00"),
            status="IN_TRANSIT",
        )
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("700000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])

    def test_split_escrow_full_release_flow(self):
        escrows = OrderFinanceService.lock_funds_for_order(
            order=self.order,
            actor=self.buyer,
            supplier_amount=Decimal("500000.00"),
            logistics_amount=Decimal("100000.00"),
            idempotency_key="order-split-1",
        )
        self.assertEqual(len(escrows), 2)
        self.assertEqual({esc.escrow_type for esc in escrows}, {EscrowType.SUPPLIER, EscrowType.LOGISTICS})

        buyer_wallet = Wallet.objects.get(owner=self.buyer)
        self.assertEqual(buyer_wallet.available_balance, Decimal("100000.00"))
        self.assertEqual(buyer_wallet.locked_balance, Decimal("600000.00"))

        OrderFinanceService.register_supplier_confirmation(order=self.order, actor=self.transit)
        proof = SimpleUploadedFile("invoice.pdf", b"%PDF-1.4 fake-content", content_type="application/pdf")
        OrderFinanceService.register_supplier_purchase_proof(order=self.order, actor=self.transit, proof_file=proof)
        OrderFinanceService.admin_validate_supplier(order=self.order, actor=self.admin, approve=True, note="OK")

        supplier_wallet = Wallet.objects.get(owner=self.seller)
        # Payout exits the platform via mobile money (SIMULATED) so pending_balance
        # is consumed; verify the payout transaction succeeded with the correct amount.
        supplier_payout = supplier_wallet.transactions.filter(kind="PAYOUT_SUPPLIER").first()
        self.assertIsNotNone(supplier_payout)
        self.assertEqual(supplier_payout.status, "SUCCESS")
        self.assertEqual(abs(supplier_payout.amount), Decimal("475000.00"))
        self.order.refresh_from_db()
        supplier_escrow = self.order.escrows.get(escrow_type=EscrowType.SUPPLIER)
        self.assertEqual(supplier_escrow.status, "RELEASED")
        self.assertEqual(self.order.status, "SHIPPING")

        OrderFinanceService.release_logistics_escrow_after_buyer_confirmation(order=self.order, actor=self.buyer)
        transit_wallet = Wallet.objects.get(owner=self.transit)
        transit_payout = transit_wallet.transactions.filter(kind="PAYOUT_LOGISTICS").first()
        self.assertIsNotNone(transit_payout)
        self.assertEqual(transit_payout.status, "SUCCESS")
        # Commission plateforme de 10% prelevee sur le payout livreur :
        # 100000 - 10% = 90000 net au livreur, 10000 a la plateforme.
        self.assertEqual(abs(transit_payout.amount), Decimal("90000.00"))
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "COMPLETED")
        self.assertEqual(self.order.escrow_status, "RELEASED")

    def test_shipping_fee_is_distance_based_with_fallback(self):
        from apps.orders.shipping import compute_shipping_fee

        # Douala (4.05, 9.70) -> Yaounde (3.87, 11.52) ~ 200 km.
        self.seller.location_latitude = 4.05
        self.seller.location_longitude = 9.70
        self.buyer.location_latitude = 3.87
        self.buyer.location_longitude = 11.52
        fee = compute_shipping_fee(self.seller, self.buyer)
        # ~200 km * 150 FCFA/km ~ 30000 FCFA (tolerance large).
        self.assertGreater(fee, Decimal("25000"))
        self.assertLess(fee, Decimal("35000"))

        # Coordonnees manquantes -> distance de repli (5 km) * 150 = 750 FCFA.
        self.seller.location_latitude = None
        self.assertEqual(compute_shipping_fee(self.seller, self.buyer), Decimal("750.00"))

    def test_local_order_splits_product_and_logistics_escrow(self):
        local_order = Order.objects.create(
            buyer=self.buyer,
            seller=self.seller,
            product=self.product,
            quantity=1,
            unit_price=Decimal("500000.00"),
            total_price=Decimal("500000.00"),
            logistics_price=Decimal("3000.00"),
            order_type=OrderType.LOCAL,
            platform_commission_rate=Decimal("0.05"),
        )
        escrows = OrderFinanceService.lock_funds_for_order(
            order=local_order,
            actor=self.buyer,
            supplier_amount=Decimal("500000.00"),
            logistics_amount=Decimal("3000.00"),
            idempotency_key="order-local-split-1",
        )
        self.assertEqual(
            {esc.escrow_type for esc in escrows},
            {EscrowType.LOCAL, EscrowType.LOGISTICS},
        )
        local_e = local_order.escrows.get(escrow_type=EscrowType.LOCAL)
        logi_e = local_order.escrows.get(escrow_type=EscrowType.LOGISTICS)
        self.assertEqual(local_e.amount, Decimal("500000.00"))
        self.assertEqual(local_e.beneficiary_id, self.seller.id)
        self.assertEqual(logi_e.amount, Decimal("3000.00"))
        # Le livreur n'est pas encore assigne a la commande.
        self.assertIsNone(logi_e.beneficiary_id)

    def test_purchase_proof_reuse_is_blocked(self):
        OrderFinanceService.lock_funds_for_order(
            order=self.order,
            actor=self.buyer,
            supplier_amount=Decimal("500000.00"),
            logistics_amount=Decimal("100000.00"),
            idempotency_key="order-split-2",
        )
        OrderFinanceService.register_supplier_confirmation(order=self.order, actor=self.transit)
        proof = SimpleUploadedFile("invoice.pdf", b"%PDF-1.4 same-proof", content_type="application/pdf")
        OrderFinanceService.register_supplier_purchase_proof(order=self.order, actor=self.transit, proof_file=proof)

        second_order = Order.objects.create(
            buyer=self.buyer,
            seller=self.seller,
            product=self.product,
            quantity=1,
            preferred_transit_agent=self.transit,
            unit_price=Decimal("500000.00"),
            total_price=Decimal("500000.00"),
            logistics_price=Decimal("100000.00"),
            order_type=OrderType.INTERNATIONAL,
            platform_commission_rate=Decimal("0.05"),
        )
        Shipment.objects.create(
            order=second_order,
            buyer=self.buyer,
            seller=self.seller,
            transit_agent=self.transit,
            pickup_address="Shenzhen",
            dropoff_address="Douala",
            country_code="CM",
            transport_mode=TransportMode.SEA,
            shipping_fee=Decimal("100000.00"),
            status="IN_TRANSIT",
        )
        buyer_wallet = Wallet.objects.get(owner=self.buyer)
        buyer_wallet.available_balance = Decimal("700000.00")
        buyer_wallet.save(update_fields=["available_balance"])
        OrderFinanceService.lock_funds_for_order(
            order=second_order,
            actor=self.buyer,
            supplier_amount=Decimal("500000.00"),
            logistics_amount=Decimal("100000.00"),
            idempotency_key="order-split-3",
        )
        OrderFinanceService.register_supplier_confirmation(order=second_order, actor=self.transit)
        duplicate_proof = SimpleUploadedFile("duplicate.pdf", b"%PDF-1.4 same-proof", content_type="application/pdf")
        with self.assertRaises(FraudRiskError):
            OrderFinanceService.register_supplier_purchase_proof(
                order=second_order,
                actor=self.transit,
                proof_file=duplicate_proof,
            )
