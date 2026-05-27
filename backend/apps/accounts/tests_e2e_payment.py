"""
End-to-end payment flow regression tests.

Walks the load-bearing pieces of a real Mobile Money transaction:

    1. NotchPayCheckoutService routes `provider="mtn"` → `locked_channel=cm.mtn`
       (audit fix: was hard-coded to channels[0]).
    2. Provider webhook signed with HMAC credits the wallet atomically.
    3. Webhook replay does NOT double-credit.
    4. Webhook with bad signature is refused.
    5. `lock_funds_for_order` debits available and creates the escrow.

The topup HTTP endpoint requires a sensitive-action MFA token — that's an
authentication-flow concern covered elsewhere. Here we test the money path
itself, where the regressions would actually lose XAF.

Run:
    DEBUG=1 SECRET_KEY=test-key-... NOTCHPAY_ENABLED=0 \
        python manage.py test apps.accounts.tests_e2e_payment
"""
from __future__ import annotations

import hashlib
import hmac
import json
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.wallets.models import TransactionStatus, WalletTransaction
from apps.wallets.services import WalletAccountingService

User = get_user_model()


def _make_buyer() -> User:
    user = User.objects.create_user(
        username="e2e_buyer", email="buyer@x", first_name="Buyer",
        password="ABCdef123!", role="BUYER",
    )
    user.is_verified = True
    user.kyc_level = 2
    user.save()
    return user


def _make_seller() -> User:
    return User.objects.create_user(
        username="e2e_seller", email="seller@x", first_name="Seller",
        password="ABCdef123!", role="SUPPLIER",
    )


def _hmac_sig(body: bytes, secret: str) -> str:
    return hmac.new(
        secret.encode("utf-8"), body, digestmod=hashlib.sha256,
    ).hexdigest()


# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — NotchPay channel routing
# ─────────────────────────────────────────────────────────────────────────────

@override_settings(
    NOTCHPAY_ENABLED=True,
    NOTCHPAY_LIVE_PUBLIC_KEY="pk.test",
    NOTCHPAY_LIVE_PRIVATE_KEY="sk.test",
    NOTCHPAY_PUBLIC_KEY="pk.test",
    NOTCHPAY_PRIVATE_KEY="sk.test",
    NOTCHPAY_API_BASE="https://api.notchpay.test",
    NOTCHPAY_CHECKOUT_CHANNELS=["cm.mtn", "cm.orange"],
)
class NotchPayChannelRoutingTests(TestCase):
    def test_mtn_provider_locks_channel_to_mtn(self):
        from apps.wallets.notchpay_checkout_service import NotchPayCheckoutService

        with patch.object(
            NotchPayCheckoutService, "_post_json",
            return_value={"code": "200", "transaction": {"id": "PMT-1", "reference": "X"}},
        ) as mock_post:
            NotchPayCheckoutService.create_invoice(
                amount=1000, description="topup", tx_ref="X", provider="mtn",
            )
        args, _ = mock_post.call_args
        payload = args[1]
        self.assertEqual(payload.get("locked_channel"), "cm.mtn")

    def test_orange_provider_locks_channel_to_orange(self):
        from apps.wallets.notchpay_checkout_service import NotchPayCheckoutService

        with patch.object(
            NotchPayCheckoutService, "_post_json",
            return_value={"code": "200", "transaction": {"id": "PMT-2", "reference": "Y"}},
        ) as mock_post:
            NotchPayCheckoutService.create_invoice(
                amount=1000, description="topup", tx_ref="Y", provider="orange",
            )
        args, _ = mock_post.call_args
        payload = args[1]
        self.assertEqual(payload.get("locked_channel"), "cm.orange")

    def test_unknown_provider_omits_lock_when_multiple_channels(self):
        from apps.wallets.notchpay_checkout_service import NotchPayCheckoutService

        with patch.object(
            NotchPayCheckoutService, "_post_json",
            return_value={"code": "200", "transaction": {"id": "PMT-3", "reference": "Z"}},
        ) as mock_post:
            NotchPayCheckoutService.create_invoice(
                amount=1000, description="topup", tx_ref="Z", provider=None,
            )
        args, _ = mock_post.call_args
        payload = args[1]
        # No lock — NotchPay falls back to its own picker, the safe default.
        self.assertNotIn("locked_channel", payload)


# ─────────────────────────────────────────────────────────────────────────────
# Steps 2-4 — Webhook signature + idempotency
# ─────────────────────────────────────────────────────────────────────────────

@override_settings(
    NOTCHPAY_ENABLED=True,
    NOTCHPAY_CHECKOUT_WEBHOOK_SECRET="test-checkout-secret",
    NOTCHPAY_WEBHOOK_TOKEN="",
    WEBHOOK_REQUIRE_TIMESTAMP=False,
    LEDGER_DOUBLE_ENTRY_ENABLED=False,
)
class WebhookFlowTests(TestCase):
    def setUp(self):
        self.buyer = _make_buyer()
        self.client = APIClient()

    def _seed_pending_topup(self, ref="REF-1", amount=10000) -> WalletTransaction:
        wallet = WalletAccountingService.get_wallet_for_update(user=self.buyer)
        return WalletTransaction.objects.create(
            wallet=wallet,
            kind="TOPUP",
            amount=Decimal(amount),
            status=TransactionStatus.PENDING,
            provider="notchpay",
            external_transaction_id=ref,
            reference=f"topup:mtn:+237600000000:tx:{ref}",
        )

    def _post_webhook(self, ref, amount, secret="test-checkout-secret"):
        body = json.dumps({
            "event": "payment.complete",
            "data": {
                "id": f"PMT-{ref}",
                "reference": ref,
                "status": "complete",
                "amount": amount,
                "currency": "XAF",
            },
        }).encode("utf-8")
        sig = _hmac_sig(body, secret)
        return self.client.post(
            "/api/wallets/notchpay/checkout/webhook/",
            data=body, content_type="application/json",
            HTTP_X_NOTCH_SIGNATURE=sig,
        )

    def test_valid_webhook_credits_wallet(self):
        tx = self._seed_pending_topup(ref="REF-OK", amount=10000)
        wallet = tx.wallet
        before = wallet.available_balance

        resp = self._post_webhook("REF-OK", 10000)
        self.assertEqual(resp.status_code, 200, resp.content)
        wallet.refresh_from_db()
        tx.refresh_from_db()
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)
        self.assertEqual(wallet.available_balance - before, Decimal("10000.00"))

    def test_replay_does_not_double_credit(self):
        tx = self._seed_pending_topup(ref="REF-REPLAY", amount=5000)
        wallet = tx.wallet

        self.assertEqual(self._post_webhook("REF-REPLAY", 5000).status_code, 200)
        wallet.refresh_from_db()
        after_first = wallet.available_balance

        self.assertEqual(self._post_webhook("REF-REPLAY", 5000).status_code, 200)
        wallet.refresh_from_db()
        self.assertEqual(wallet.available_balance, after_first)

    def test_bad_signature_refused(self):
        body = b'{"event":"payment.complete","data":{"reference":"X"}}'
        resp = self.client.post(
            "/api/wallets/notchpay/checkout/webhook/",
            data=body, content_type="application/json",
            HTTP_X_NOTCH_SIGNATURE="deadbeef" * 8,
        )
        # The endpoint enforces HMAC pre-check and rejects with 403 — anything
        # in the 4xx range is the right shape; we tighten on 403 since that's
        # what the audited code path returns for "auth failed at app level".
        self.assertEqual(resp.status_code, 403, resp.content)


# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — lock_funds_for_order is atomic and reduces available balance
# ─────────────────────────────────────────────────────────────────────────────

@override_settings(LEDGER_DOUBLE_ENTRY_ENABLED=False)
class LockFundsForOrderTests(TestCase):
    def test_lock_funds_debits_available_and_locks(self):
        from apps.catalog.models import Product
        from apps.orders.models import Order, OrderStatus
        from apps.orders.services import OrderFinanceService

        buyer = _make_buyer()
        seller = _make_seller()
        wallet = WalletAccountingService.get_wallet_for_update(user=buyer)
        wallet.available_balance = Decimal("20000.00")
        wallet.save(update_fields=["available_balance"])

        product = Product.objects.create(
            seller=seller,
            title="Test product",
            description="x",
            brand="TestBrand",
            price_for_min_qty=Decimal("3000.00"),
            price_for_max_qty=Decimal("3000.00"),
            available_qty=10,
        )
        order = Order.objects.create(
            buyer=buyer, seller=seller, product=product, quantity=1,
            unit_price=Decimal("3000.00"), total_price=Decimal("3000.00"),
            status=OrderStatus.PENDING,
        )

        OrderFinanceService.lock_funds_for_order(
            order=order, actor=buyer,
            supplier_amount=Decimal("3000.00"),
            logistics_amount=Decimal("0.00"),
        )
        wallet.refresh_from_db()
        self.assertEqual(wallet.available_balance, Decimal("17000.00"))
        self.assertEqual(wallet.locked_balance, Decimal("3000.00"))
        self.assertTrue(order.escrows.exists())
