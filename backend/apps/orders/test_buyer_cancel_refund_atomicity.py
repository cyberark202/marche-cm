"""C-3 — Buyer/seller order cancellation must be ATOMIC.

Guarantees verified here:
  * cancelling refunds the still-locked escrow back to the buyer and flips the
    order to CANCELLED in a single commit;
  * if the refund step fails, NOTHING persists — it is impossible to observe an
    order in CANCELLED with its escrow still LOCKED (the original bug);
  * a buyer cancelling their own order is authorized (was previously rejected by
    refund_order_locked_funds, which left funds stuck);
  * double cancellation refunds exactly once;
  * terminal orders cannot be cancelled.
"""
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.exceptions import ValidationError

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.orders.models import EscrowStatus, Order, OrderStatus, OrderType
from apps.orders.models import OrderEscrow
from apps.orders.services import OrderFinanceService
from apps.wallets.models import Wallet
from apps.wallets.services import WalletAccountingService


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class BuyerCancelRefundAtomicityTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.buyer = u.objects.create_user(
            username="c3_buyer", email="c3_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000301")
        self.seller = u.objects.create_user(
            username="c3_seller", email="c3_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000302")
        self.transit = u.objects.create_user(
            username="c3_transit", email="c3_transit@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000303")
        self.outsider = u.objects.create_user(
            username="c3_out", email="c3_out@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000304")
        self.product = Product.objects.create(
            seller=self.seller, title="Sac de riz", description="local", brand="QA",
            min_order_qty=1, max_order_qty=10, price_for_min_qty=Decimal("5000.00"),
            price_for_max_qty=Decimal("4500.00"), weight_kg=Decimal("2.00"), is_active=True)
        self.order = Order.objects.create(
            buyer=self.buyer, seller=self.seller, product=self.product, quantity=1,
            preferred_transit_agent=self.transit, unit_price=Decimal("5000.00"),
            total_price=Decimal("5000.00"), logistics_price=Decimal("3600.00"),
            order_type=OrderType.LOCAL, platform_commission_rate=Decimal("0.05"))
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        wallet.available_balance = Decimal("50000.00")
        wallet.locked_balance = Decimal("0.00")
        wallet.pending_balance = Decimal("0.00")
        wallet.save(update_fields=["available_balance", "locked_balance", "pending_balance"])
        # Fund the escrow (LOCAL => single escrow of total+shipping = 8600).
        OrderFinanceService.lock_funds_for_order(
            order=self.order, actor=self.buyer,
            supplier_amount=Decimal("8600.00"), logistics_amount=Decimal("0.00"),
            idempotency_key=f"order-c3-{self.order.id}")

    def _wallet(self):
        return Wallet.objects.get(owner=self.buyer)

    def test_escrow_is_locked_before_cancel(self):
        w = self._wallet()
        self.assertEqual(w.available_balance, Decimal("41400.00"))
        self.assertEqual(w.locked_balance, Decimal("8600.00"))
        self.assertEqual(OrderEscrow.objects.get(order=self.order).status, "LOCKED")

    def test_buyer_cancellation_refunds_and_sets_cancelled(self):
        refunded = OrderFinanceService.cancel_order(order=self.order, actor=self.buyer, reason="QA")
        self.assertEqual(refunded, Decimal("8600.00"))
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, OrderStatus.CANCELLED)
        self.assertEqual(self.order.escrow_status, EscrowStatus.REFUNDED)
        self.assertEqual(OrderEscrow.objects.get(order=self.order).status, "REFUNDED")
        w = self._wallet()
        self.assertEqual(w.available_balance, Decimal("50000.00"))
        self.assertEqual(w.locked_balance, Decimal("0.00"))

    def test_seller_can_also_cancel(self):
        OrderFinanceService.cancel_order(order=self.order, actor=self.seller, reason="QA seller")
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, OrderStatus.CANCELLED)
        self.assertEqual(self._wallet().available_balance, Decimal("50000.00"))

    def test_outsider_cannot_cancel(self):
        with self.assertRaises(ValidationError):
            OrderFinanceService.cancel_order(order=self.order, actor=self.outsider, reason="hack")
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, OrderStatus.PENDING)
        self.assertEqual(OrderEscrow.objects.get(order=self.order).status, "LOCKED")

    def test_refund_failure_rolls_back_everything(self):
        """The core C-3 guarantee: a failure during refund must leave NO partial
        state — never CANCELLED-with-LOCKED-escrow."""
        with mock.patch.object(
            WalletAccountingService, "unlock_to_available",
            side_effect=RuntimeError("boom"),
        ):
            with self.assertRaises(RuntimeError):
                OrderFinanceService.cancel_order(order=self.order, actor=self.buyer, reason="QA")
        self.order.refresh_from_db()
        # Nothing changed.
        self.assertEqual(self.order.status, OrderStatus.PENDING)
        self.assertEqual(OrderEscrow.objects.get(order=self.order).status, "LOCKED")
        w = self._wallet()
        self.assertEqual(w.available_balance, Decimal("41400.00"))
        self.assertEqual(w.locked_balance, Decimal("8600.00"))

    def test_double_cancellation_refunds_once(self):
        OrderFinanceService.cancel_order(order=self.order, actor=self.buyer, reason="first")
        with self.assertRaises(ValidationError):
            OrderFinanceService.cancel_order(order=self.order, actor=self.buyer, reason="second")
        w = self._wallet()
        self.assertEqual(w.available_balance, Decimal("50000.00"))  # not 58600 — no double refund
        self.assertEqual(w.locked_balance, Decimal("0.00"))

    def test_terminal_order_not_cancellable(self):
        Order.objects.filter(id=self.order.id).update(status=OrderStatus.COMPLETED)
        with self.assertRaises(ValidationError):
            OrderFinanceService.cancel_order(order=self.order, actor=self.buyer, reason="late")
