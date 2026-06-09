"""Tests for the in-app NotchPay Direct Charge top-up flow.

Direct Charge initializes a payment then charges it server-side so NotchPay
pushes a USSD/OTP prompt to the buyer's phone — no hosted-page redirect. These
tests mock the NotchPay network layer and assert the wiring in WalletViewSet.topup
and NotchPayCheckoutService.charge.
"""
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import PaymentProvider, TransactionStatus, Wallet, WalletTransaction
from .notchpay_checkout_service import NotchPayCheckoutService


@override_settings(
    NOTCHPAY_ENABLED=True,
    NOTCHPAY_ONLY_MTN=False,
    NOTCHPAY_PUBLIC_KEY="pk_test_x",
    NOTCHPAY_PRIVATE_KEY="sk_test_x",
    SECURE_SSL_REDIRECT=False,
    # Channel layer en mémoire : tests déterministes, sans dépendre d'un Redis
    # local (sinon les diffusions WebSocket timeout pendant le marquage d'échec).
    CHANNEL_LAYERS={"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}},
)
class DirectChargeTopupTests(APITestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(
            username="buyer_dc",
            email="buyer_dc@test.local",
            password="TestPassword123!",
        )
        self.user.set_wallet_pin("0000")
        self.user.save(update_fields=["wallet_pin_hash"])
        self.client.force_authenticate(self.user)

    def _post_topup(self, *, provider, source, key):
        return self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1000",
                "source_phone": source,
                "source_account": source,
                "provider": provider,
                "pin": "0000",
                "idempotency_key": key,
            },
            format="json",
        )

    def test_mobile_money_topup_triggers_direct_charge_mtn(self):
        invoice = {
            "mode": "LIVE",
            "reference": "NP-REF-1",
            "checkout_url": "https://pay.notchpay.co/NP-REF-1",
            "provider_transaction_id": "pay_1",
        }
        charge = {"mode": "LIVE", "status": "processing", "reference": "NP-REF-1"}
        with mock.patch.object(NotchPayCheckoutService, "create_invoice", return_value=invoice), \
             mock.patch.object(NotchPayCheckoutService, "charge", return_value=charge) as charge_mock:
            res = self._post_topup(
                provider=PaymentProvider.MOBILE_MONEY,
                source="+237699111222",
                key="dc-mtn-1",
            )

        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertEqual(res.data["payment_mode"], "direct_charge")
        self.assertIsNone(res.data["checkout_url"])
        self.assertEqual(res.data["status"], TransactionStatus.PENDING)
        # Charge routed to the MTN channel with the normalized phone.
        _, kwargs = charge_mock.call_args
        self.assertEqual(kwargs["channel"], "cm.mtn")
        self.assertEqual(kwargs["phone"], "+237699111222")
        self.assertEqual(kwargs["reference"], "NP-REF-1")
        # Transaction stays PENDING until the webhook confirms.
        tx = WalletTransaction.objects.get(idempotency_key="dc-mtn-1")
        self.assertEqual(tx.status, TransactionStatus.PENDING)
        self.assertEqual(Wallet.objects.get(owner=self.user).balance, Decimal("0.00"))

    def test_orange_money_topup_uses_orange_channel(self):
        invoice = {"mode": "LIVE", "reference": "NP-REF-2", "checkout_url": "https://x"}
        charge = {"mode": "LIVE", "status": "processing", "reference": "NP-REF-2"}
        with mock.patch.object(NotchPayCheckoutService, "create_invoice", return_value=invoice), \
             mock.patch.object(NotchPayCheckoutService, "charge", return_value=charge) as charge_mock:
            res = self._post_topup(
                provider=PaymentProvider.ORANGE_MONEY,
                source="+237699111222",
                key="dc-orange-1",
            )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertEqual(res.data["payment_mode"], "direct_charge")
        _, kwargs = charge_mock.call_args
        self.assertEqual(kwargs["channel"], "cm.orange")

    def test_card_topup_keeps_hosted_redirect(self):
        invoice = {
            "mode": "LIVE",
            "reference": "NP-REF-3",
            "checkout_url": "https://pay.notchpay.co/NP-REF-3",
        }
        with mock.patch.object(NotchPayCheckoutService, "create_invoice", return_value=invoice), \
             mock.patch.object(NotchPayCheckoutService, "charge") as charge_mock:
            res = self._post_topup(
                provider=PaymentProvider.VISA,
                source="4111111111111111",
                key="dc-card-1",
            )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertEqual(res.data["payment_mode"], "redirect")
        self.assertEqual(res.data["checkout_url"], "https://pay.notchpay.co/NP-REF-3")
        # No direct charge for cards.
        charge_mock.assert_not_called()

    def test_direct_charge_failure_marks_transaction_failed(self):
        invoice = {"mode": "LIVE", "reference": "NP-REF-4", "checkout_url": "https://x"}
        charge = {"mode": "LIVE", "error": "NotchPay HTTP 402: insufficient", "reference": "NP-REF-4"}
        with mock.patch.object(NotchPayCheckoutService, "create_invoice", return_value=invoice), \
             mock.patch.object(NotchPayCheckoutService, "charge", return_value=charge):
            res = self._post_topup(
                provider=PaymentProvider.MOBILE_MONEY,
                source="+237699111222",
                key="dc-fail-1",
            )
        self.assertEqual(res.status_code, status.HTTP_502_BAD_GATEWAY)
        # The provider error is never leaked verbatim to the client.
        self.assertNotIn("402", res.data["detail"])
        tx = WalletTransaction.objects.get(idempotency_key="dc-fail-1")
        self.assertEqual(tx.status, TransactionStatus.FAILED)
        self.assertEqual(Wallet.objects.get(owner=self.user).balance, Decimal("0.00"))


@override_settings(
    NOTCHPAY_ENABLED=True,
    NOTCHPAY_PUBLIC_KEY="pk_test_x",
    NOTCHPAY_PRIVATE_KEY="sk_test_x",
    NOTCHPAY_API_BASE="https://api.notchpay.co",
    SECURE_SSL_REDIRECT=False,
)
class ChargeServiceContractTests(APITestCase):
    def test_charge_builds_documented_payload_and_parses_processing(self):
        captured = {}

        def fake_post(url, payload):
            captured["url"] = url
            captured["payload"] = payload
            return {"code": 202, "transaction": {"id": "pay_9", "reference": "REF-9", "status": "processing"}}

        with mock.patch.object(NotchPayCheckoutService, "_post_json", side_effect=fake_post):
            out = NotchPayCheckoutService.charge(
                reference="REF-9",
                channel="cm.mtn",
                phone="+237699111222",
                client_ip="41.202.1.1",
            )

        self.assertTrue(captured["url"].endswith("/payments/REF-9"))
        self.assertEqual(captured["payload"]["channel"], "cm.mtn")
        self.assertEqual(captured["payload"]["data"]["phone"], "+237699111222")
        self.assertEqual(captured["payload"]["client_ip"], "41.202.1.1")
        self.assertEqual(out["status"], "processing")
        self.assertEqual(out["reference"], "REF-9")
        self.assertNotIn("error", out)

    def test_channel_mapping(self):
        self.assertEqual(NotchPayCheckoutService.channel_for_provider("MOBILE_MONEY"), "cm.mtn")
        self.assertEqual(NotchPayCheckoutService.channel_for_provider("ORANGE_MONEY"), "cm.orange")
        self.assertEqual(NotchPayCheckoutService.channel_for_provider("VISA"), "")
        self.assertTrue(NotchPayCheckoutService.supports_direct_charge("MOBILE_MONEY"))
        self.assertFalse(NotchPayCheckoutService.supports_direct_charge("PAYPAL"))
