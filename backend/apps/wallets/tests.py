import hashlib
import hmac
import json
from io import StringIO
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core.management import CommandError, call_command
from django.utils import timezone
from django.test import TestCase, override_settings
from django.urls import reverse
from datetime import timedelta
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import SensitiveActionChallenge
from .models import PaymentProvider, TransactionStatus, Wallet, WalletTransaction


@override_settings(NOTCHPAY_ENABLED=False, NOTCHPAY_ONLY_MTN=False)
class WalletFlowTests(APITestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(
            username="buyer1",
            email="buyer1@test.local",
            password="TestPassword123!",
        )
        self.user.set_wallet_pin("0000")
        self.user.save(update_fields=["wallet_pin_hash"])
        self.client.force_authenticate(self.user)

    def test_topup_simulated_sets_success(self):
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1000",
                "source_phone": "+237699111222",
                "provider": PaymentProvider.MOBILE_MONEY,
                "pin": "0000",
                "idempotency_key": "idem-topup-1",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        tx = WalletTransaction.objects.get(idempotency_key="idem-topup-1")
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)
        wallet = Wallet.objects.get(owner=self.user)
        self.assertEqual(wallet.balance, Decimal("1000.00"))

    def test_topup_paypal_accepts_email_source(self):
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1500",
                "source_account": "client.paypal@test.local",
                "provider": PaymentProvider.PAYPAL,
                "pin": "0000",
                "idempotency_key": "idem-topup-paypal-1",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        tx = WalletTransaction.objects.get(idempotency_key="idem-topup-paypal-1")
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)
        wallet = Wallet.objects.get(owner=self.user)
        self.assertEqual(wallet.balance, Decimal("1500.00"))

    def test_withdraw_paypal_accepts_email_destination(self):
        wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        wallet.balance = Decimal("5000.00")
        wallet.blocked_balance = Decimal("0.00")
        wallet.save(update_fields=["balance", "blocked_balance", "updated_at"])
        _otp_code = "123456"
        challenge = SensitiveActionChallenge.objects.create(
            user=self.user,
            action_key="wallet.withdraw",
            challenge_token="withdraw-test-token",
            code_hash=make_password(_otp_code),
            expires_at=timezone.now() + timedelta(minutes=5),
        )

        res = self.client.post(
            reverse("wallet-withdraw"),
            {
                "amount": "1000",
                "destination_account": "seller.paypal@test.local",
                "provider": PaymentProvider.PAYPAL,
                "pin": "0000",
                "challenge_token": challenge.challenge_token,
                "verification_code": _otp_code,
                "idempotency_key": "idem-withdraw-paypal-1",
            },
            format="json",
        )

        self.assertEqual(res.status_code, status.HTTP_200_OK)
        tx = WalletTransaction.objects.get(idempotency_key="idem-withdraw-paypal-1")
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)
        wallet.refresh_from_db()
        self.assertEqual(wallet.balance, Decimal("4000.00"))
        self.assertEqual(wallet.blocked_balance, Decimal("0.00"))

    @override_settings(WALLET_PIN_MAX_ATTEMPTS=2, WALLET_PIN_LOCK_MINUTES=5)
    def test_wallet_pin_lockout_after_invalid_attempts(self):
        payload = {
            "amount": "1000",
            "source_phone": "+237699111222",
            "provider": PaymentProvider.MOBILE_MONEY,
            "pin": "1111",
        }
        first = self.client.post(reverse("wallet-topup"), payload, format="json")
        second = self.client.post(reverse("wallet-topup"), payload, format="json")

        self.assertEqual(first.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(second.status_code, status.HTTP_423_LOCKED)

        self.user.refresh_from_db()
        self.assertIsNotNone(self.user.wallet_pin_locked_until)

        self.user.wallet_pin_locked_until = timezone.now() - timedelta(minutes=1)
        self.user.wallet_pin_failed_attempts = 0
        self.user.save(update_fields=["wallet_pin_locked_until", "wallet_pin_failed_attempts"])

        ok = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1000",
                "source_phone": "+237699111222",
                "provider": PaymentProvider.MOBILE_MONEY,
                "pin": "0000",
            },
            format="json",
        )
        self.assertEqual(ok.status_code, status.HTTP_200_OK)

    @override_settings(NOTCHPAY_WEBHOOK_TOKEN="test-webhook-token")
    def test_disburse_webhook_idempotence(self):
        wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        tx = wallet.transactions.create(
            amount=Decimal("2000.00"),
            kind="TOPUP",
            provider=PaymentProvider.MOBILE_MONEY,
            status=TransactionStatus.PENDING,
            external_transaction_id="WALLET-IDEMPOTENT-1",
        )

        payload = {
            "event_id": "evt-1",
            "disburse_id": tx.external_transaction_id,
            "response_code": "00",
        }
        first = self.client.post(
            reverse("wallet-notchpay-disburse-webhook"),
            payload,
            format="json",
            HTTP_X_NOTCHPAY_TOKEN="test-webhook-token",
        )
        second = self.client.post(
            reverse("wallet-notchpay-disburse-webhook"),
            payload,
            format="json",
            HTTP_X_NOTCHPAY_TOKEN="test-webhook-token",
        )

        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        tx.refresh_from_db()
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)

    @override_settings(NOTCHPAY_WEBHOOK_TOKEN="test-webhook-token")
    def test_checkout_webhook_does_not_downgrade_success_transaction(self):
        wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        tx = wallet.transactions.create(
            amount=Decimal("1200.00"),
            kind="TOPUP",
            provider=PaymentProvider.MOBILE_MONEY,
            status=TransactionStatus.SUCCESS,
            external_transaction_id="WALLET-CHECKOUT-ALREADY-SUCCESS",
        )
        payload = {
            "data": {
                "event_id": "evt-checkout-failed-after-success",
                "status": "failed",
                "invoice": {"token": tx.external_transaction_id},
            }
        }
        res = self.client.post(
            reverse("wallet-notchpay-checkout-webhook"),
            payload,
            format="json",
            HTTP_X_NOTCHPAY_TOKEN="test-webhook-token",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        tx.refresh_from_db()
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)

    @override_settings(
        NOTCHPAY_WEBHOOK_TOKEN="test-webhook-token",
        NOTCHPAY_DISBURSE_WEBHOOK_SECRET="super-secret-key",
    )
    def test_disburse_webhook_rejects_invalid_signature(self):
        wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        tx = wallet.transactions.create(
            amount=Decimal("2000.00"),
            kind="TOPUP",
            provider=PaymentProvider.MOBILE_MONEY,
            status=TransactionStatus.PENDING,
            external_transaction_id="WALLET-SIGNATURE-1",
        )
        payload = {
            "event_id": "evt-signature-1",
            "disburse_id": tx.external_transaction_id,
            "response_code": "00",
        }
        body = json.dumps(payload).encode("utf-8")
        bad = self.client.generic(
            "POST",
            reverse("wallet-notchpay-disburse-webhook"),
            data=body,
            content_type="application/json",
            HTTP_X_NOTCHPAY_TOKEN="test-webhook-token",
            HTTP_X_NOTCH_SIGNATURE="invalid",
        )
        self.assertEqual(bad.status_code, status.HTTP_403_FORBIDDEN)
        tx.refresh_from_db()
        self.assertEqual(tx.status, TransactionStatus.PENDING)

        signature = hmac.new(b"super-secret-key", body, hashlib.sha256).hexdigest()
        ok = self.client.generic(
            "POST",
            reverse("wallet-notchpay-disburse-webhook"),
            data=body,
            content_type="application/json",
            HTTP_X_NOTCHPAY_TOKEN="test-webhook-token",
            HTTP_X_NOTCH_SIGNATURE=signature,
        )
        self.assertEqual(ok.status_code, status.HTTP_200_OK)
        tx.refresh_from_db()
        self.assertEqual(tx.status, TransactionStatus.SUCCESS)


@override_settings(RECONCILIATION_REQUIRE_PROVIDER_BALANCE=False, FINOPS_PROVIDER_REAL_BALANCE="0")
class FinOpsCommandTests(TestCase):
    def test_run_financial_ops_outputs_summary(self):
        out = StringIO()
        call_command("run_financial_ops", "--skip-retries", "--no-send-alerts", stdout=out)
        payload = json.loads(out.getvalue().strip().splitlines()[-1])
        self.assertIn("reconciliation", payload)
        self.assertEqual(payload["provider_balance_source"], "env_static")
        self.assertIn(payload["reconciliation"]["status"], {"OK", "ALERT", "FAILED"})

    @override_settings(
        RECONCILIATION_REQUIRE_PROVIDER_BALANCE=True,
        FINOPS_PROVIDER_REAL_BALANCE="",
        FINOPS_PROVIDER_BALANCE_URL="",
    )
    def test_run_financial_ops_strict_requires_provider_balance(self):
        out = StringIO()
        with self.assertRaises(CommandError):
            call_command(
                "run_financial_ops",
                "--skip-retries",
                "--strict-provider-balance",
                "--no-send-alerts",
                stdout=out,
            )
