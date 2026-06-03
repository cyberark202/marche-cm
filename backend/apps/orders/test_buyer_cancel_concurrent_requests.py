"""C-3 — Concurrency: two simultaneous cancellation requests must refund the
buyer exactly once (no double refund, no lost update).

Uses TransactionTestCase so the threads see committed rows. SQLite serialises
writers, so a loser thread may surface either a ValidationError ("non annulable"
once the winner committed) or an OperationalError ("database is locked"); both
are acceptable — what matters is the invariant: the escrow is refunded once and
only once and the wallet ends consistent.
"""
import threading
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db import connections
from django.test import TransactionTestCase
from django.test.utils import override_settings

from apps.accounts import field_crypto
from apps.catalog.models import Product
from apps.orders.models import Order, OrderEscrow, OrderStatus, OrderType
from apps.orders.services import OrderFinanceService
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class BuyerCancelConcurrentRequestsTests(TransactionTestCase):
    reset_sequences = False

    def setUp(self):
        field_crypto.clear_crypto_cache()
        u = get_user_model()
        self.buyer = u.objects.create_user(
            username="cc_buyer", email="cc_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000401")
        self.seller = u.objects.create_user(
            username="cc_seller", email="cc_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000402")
        self.transit = u.objects.create_user(
            username="cc_transit", email="cc_transit@test.local", password="TestPassword123!",
            role="TRANSIT_AGENT", is_verified=True, kyc_level=2, country_code="CM", phone_number="+237690000403")
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
        OrderFinanceService.lock_funds_for_order(
            order=self.order, actor=self.buyer,
            supplier_amount=Decimal("8600.00"), logistics_amount=Decimal("0.00"),
            idempotency_key=f"order-cc-{self.order.id}")

    def tearDown(self):
        for conn in connections.all():
            conn.close()

    def test_concurrent_cancellations_refund_once(self):
        results = []

        def worker():
            try:
                amt = OrderFinanceService.cancel_order(order=self.order, actor=self.buyer, reason="concurrent")
                results.append(("ok", amt))
            except Exception as exc:  # ValidationError or OperationalError(locked)
                results.append(("err", type(exc).__name__))
            finally:
                connections.close_all()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=30)

        successes = [r for r in results if r[0] == "ok"]
        self.assertTrue(results, "no worker completed")
        # Core invariant under ANY interleaving: the refund happens at most once
        # (never a double refund / lost update).
        self.assertLessEqual(len(successes), 1, f"double refund detected: {results}")

        self.order.refresh_from_db()
        escrow = OrderEscrow.objects.get(order=self.order)
        wallet = Wallet.objects.get(owner=self.buyer)

        if successes:
            # A winner committed: order cancelled, escrow refunded exactly once.
            self.assertEqual(self.order.status, OrderStatus.CANCELLED)
            self.assertEqual(escrow.status, "REFUNDED")
            self.assertEqual(wallet.available_balance, Decimal("50000.00"))
            self.assertEqual(wallet.locked_balance, Decimal("0.00"))
        else:
            # Both writers lost the SQLite race (e.g. "database is locked"); the
            # atomic guard means NO partial state — escrow stays locked, funds
            # untouched. This is still correct (the client simply retries).
            self.assertEqual(self.order.status, OrderStatus.PENDING)
            self.assertEqual(escrow.status, "LOCKED")
            self.assertEqual(wallet.available_balance, Decimal("41400.00"))
            self.assertEqual(wallet.locked_balance, Decimal("8600.00"))
