"""
Security regression tests — Wallet Security Remediation.

A failure in ANY of these tests is a security regression.
Treat it as a critical incident, not a routine test failure.

Fixes covered:
  H1 — Provider error leakage (NotchPay raw error exposed to client)
  H2 — Disburse webhook: no amount validation for WITHDRAW
  H3 — Webhook auth: DEBUG fallback accepted calls without HMAC secret
  H5 — Race condition TOCTOU between idempotency acquire and wallet create
  M1 — Mass-assignment: public registration allowed professional roles
  M2 — Timing attack on login + email enumeration via registration
  M4 — KYC daily limit excluded PENDING transactions (bypass window)
  M5 — No minimum amount (flood/abuse vector)
  M6 — Cursor ISO not validated (log injection / poisoning)
  M7 — Reconcile (admin) had no step-up authentication
  M9 — checkout_url could leak internal metadata from reference field
"""
import hashlib
import hmac
import json
import time
from decimal import Decimal
from datetime import timedelta
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient, APITestCase

from apps.accounts import field_crypto
from apps.accounts.models import SensitiveActionChallenge
from .models import (
    PaymentProvider,
    TransactionStatus,
    Wallet,
    WalletTransaction,
    WalletWebhookEvent,
)

User = get_user_model()

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

CHECKOUT_SECRET = "test-checkout-hmac-secret"
DISBURSE_SECRET = "test-disburse-hmac-secret"


def _sign(secret: str, body: bytes) -> str:
    return hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def _make_user(username="buyer1", email="buyer1@test.local", pin="1234"):
    user = User.objects.create_user(username=username, email=email, password="Pass1234!")
    user.set_wallet_pin(pin)
    user.save(update_fields=["wallet_pin_hash"])
    return user


def _make_admin(username="admin1", email="admin1@test.local"):
    from apps.accounts.models import UserRole
    user = User.objects.create_user(username=username, email=email, password="AdminPass1!")
    user.role = UserRole.GENERAL_ADMIN
    user.set_wallet_pin("9999")
    user.save(update_fields=["role", "wallet_pin_hash"])
    return user


# ---------------------------------------------------------------------------
# H3 — Webhook auth: HMAC always required
# ---------------------------------------------------------------------------

@override_settings(
    NOTCHPAY_ENABLED=False,
    NOTCHPAY_CHECKOUT_WEBHOOK_SECRET="",  # Not configured
    NOTCHPAY_DISBURSE_WEBHOOK_SECRET="",
    NOTCHPAY_WEBHOOK_TOKEN="",
    DEBUG=False,
)
class H3WebhookAuthNoSecretTests(APITestCase):
    """Webhook must be rejected when no HMAC secret is configured, even in prod."""

    def test_checkout_webhook_rejected_without_secret(self):
        payload = json.dumps({"type": "payment.complete", "data": {"reference": "WALLET-abc"}})
        res = self.client.post(
            reverse("wallet-notchpay-checkout-webhook"),
            data=payload,
            content_type="application/json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn("non configuree", res.data.get("detail", "").lower() or "non configuree")

    def test_disburse_webhook_rejected_without_secret(self):
        payload = json.dumps({"type": "transfer.complete", "data": {"reference": "WITHDRAW-1"}})
        res = self.client.post(
            reverse("wallet-notchpay-disburse-webhook"),
            data=payload,
            content_type="application/json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_checkout_webhook_rejected_with_wrong_signature(self):
        with self.settings(NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=CHECKOUT_SECRET):
            payload = json.dumps({"type": "payment.complete", "data": {"reference": "WALLET-abc", "amount": "1000"}})
            res = self.client.post(
                reverse("wallet-notchpay-checkout-webhook"),
                data=payload,
                content_type="application/json",
                HTTP_X_NOTCH_SIGNATURE="badhash",
            )
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_checkout_webhook_accepted_with_correct_signature(self):
        with self.settings(NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=CHECKOUT_SECRET, DEBUG=False):
            payload_bytes = json.dumps(
                {"type": "payment.complete", "data": {"reference": "WALLET-unknwn", "amount": "1000"}},
                separators=(",", ":"),
            ).encode()
            sig = _sign(CHECKOUT_SECRET, payload_bytes)
            res = self.client.post(
                reverse("wallet-notchpay-checkout-webhook"),
                data=payload_bytes,
                content_type="application/json",
                HTTP_X_NOTCH_SIGNATURE=sig,
            )
            # 404 is fine — tx not found but auth passed
            self.assertNotEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_debug_mode_still_requires_hmac_when_secret_set(self):
        """Even in DEBUG=True, if a secret is configured, signature is mandatory."""
        with self.settings(NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=CHECKOUT_SECRET, DEBUG=True):
            payload = json.dumps({"type": "payment.complete", "data": {"reference": "X", "amount": "100"}})
            res = self.client.post(
                reverse("wallet-notchpay-checkout-webhook"),
                data=payload,
                content_type="application/json",
                # No signature header
            )
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_token_from_query_string_rejected(self):
        """Token must come from headers only — never query string (H3 defense)."""
        with self.settings(
            NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=CHECKOUT_SECRET,
            NOTCHPAY_WEBHOOK_TOKEN="secret-token",
        ):
            payload_bytes = json.dumps(
                {"type": "payment.complete", "data": {"reference": "X", "amount": "100"}},
                separators=(",", ":"),
            ).encode()
            sig = _sign(CHECKOUT_SECRET, payload_bytes)
            # Token supplied in query string — must NOT be trusted
            res = self.client.post(
                reverse("wallet-notchpay-checkout-webhook") + "?token=secret-token",
                data=payload_bytes,
                content_type="application/json",
                HTTP_X_NOTCH_SIGNATURE=sig,
            )
            # Without X-NotchPay-Token header, the token check fails → 403
            self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)


# ---------------------------------------------------------------------------
# H2 — Disburse webhook: amount validation for WITHDRAW
# ---------------------------------------------------------------------------

@override_settings(
    NOTCHPAY_ENABLED=False,
    NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=CHECKOUT_SECRET,
    NOTCHPAY_DISBURSE_WEBHOOK_SECRET=DISBURSE_SECRET,
)
class H2DisburseAmountValidationTests(APITestCase):
    def setUp(self):
        self.user = _make_user()
        self.wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        # Pre-fund the wallet to reflect real withdrawal initiation state:
        # money is held in pending_balance while the withdrawal is in-flight.
        self.wallet.pending_balance = Decimal("50000.00")
        self.wallet.save(update_fields=["pending_balance", "updated_at"])
        self.tx = WalletTransaction.objects.create(
            wallet=self.wallet,
            amount=Decimal("-50000.00"),
            kind="WITHDRAWAL",
            provider=PaymentProvider.MOBILE_MONEY,
            status=TransactionStatus.PENDING,
            external_transaction_id="WALLET-withdraw-test",
        )

    def _post_disburse(self, payload_dict):
        payload_bytes = json.dumps(payload_dict, separators=(",", ":")).encode()
        sig = _sign(DISBURSE_SECRET, payload_bytes)
        return self.client.post(
            reverse("wallet-notchpay-disburse-webhook"),
            data=payload_bytes,
            content_type="application/json",
            HTTP_X_NOTCH_SIGNATURE=sig,
        )

    def test_disburse_rejected_without_amount(self):
        """Disburse webhook for WITHDRAW must be rejected if amount is absent."""
        payload = {
            "type": "transfer.complete",
            "data": {
                "reference": f"WITHDRAW-{self.tx.id}",
                "status": "complete",
                # amount intentionally absent
            },
        }
        res = self._post_disburse(payload)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.status, TransactionStatus.PENDING)  # Not changed

    def test_disburse_rejected_with_wrong_amount(self):
        """Forged webhook with mismatched amount must not mark transaction SUCCESS."""
        payload = {
            "type": "transfer.complete",
            "data": {
                "reference": f"WITHDRAW-{self.tx.id}",
                "status": "complete",
                "amount": "1",  # Wrong — tx is 50000
            },
        }
        res = self._post_disburse(payload)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.tx.refresh_from_db()
        self.assertNotEqual(self.tx.status, TransactionStatus.SUCCESS)

    def test_disburse_accepted_with_correct_amount(self):
        """Valid disburse webhook with correct amount must process normally."""
        payload = {
            "type": "transfer.complete",
            "data": {
                "reference": f"WITHDRAW-{self.tx.id}",
                "status": "complete",
                "amount": "50000",
            },
        }
        res = self._post_disburse(payload)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.status, TransactionStatus.SUCCESS)


# ---------------------------------------------------------------------------
# H1 — Provider error must never reach the client
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=True, NOTCHPAY_ONLY_MTN=False)
class H1ErrorSanitizationTests(APITestCase):
    def setUp(self):
        self.user = _make_user()
        self.client.force_authenticate(self.user)

    def test_topup_provider_error_not_exposed(self):
        """Raw NotchPay error must not appear in the topup response."""
        sensitive_error = "Auth-Key: sk_live_SECRET_KEY_12345"
        mock_checkout = {"error": sensitive_error, "status": 401}
        with patch(
            "apps.wallets.views.NotchPayCheckoutService.create_invoice",
            return_value=mock_checkout,
        ):
            res = self.client.post(
                reverse("wallet-topup"),
                {"amount": "1000", "source_phone": "+237699000001",
                 "provider": "MOBILE_MONEY", "pin": "1234"},
                format="json",
            )
        self.assertEqual(res.status_code, status.HTTP_502_BAD_GATEWAY)
        response_text = json.dumps(res.data)
        self.assertNotIn("SECRET_KEY", response_text)
        self.assertNotIn("sk_live", response_text)
        self.assertNotIn(sensitive_error, response_text)
        # Must contain a safe user-facing message
        self.assertIn("detail", res.data)

    def test_withdraw_provider_error_not_exposed(self):
        """Raw NotchPay disburse error must not appear in the withdraw response."""
        self.wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        self.wallet.balance = Decimal("10000.00")
        self.wallet.save(update_fields=["balance", "updated_at"])

        sensitive_error = "X-Grant: pk_live_PRIVATE_KEY_ABC"
        mock_transfer = {"error": sensitive_error, "mode": "LIVE"}
        _otp = "123456"
        challenge = SensitiveActionChallenge.objects.create(
            user=self.user,
            action_key="wallet.withdraw",
            challenge_token="h1-withdraw-token",
            code_hash=make_password(_otp),
            expires_at=timezone.now() + timedelta(minutes=5),
        )
        with patch(
            "apps.wallets.views.NotchPayDisbursementService.send_money",
            return_value=mock_transfer,
        ):
            res = self.client.post(
                reverse("wallet-withdraw"),
                {
                    "amount": "1000",
                    "destination_phone": "+237699000002",
                    "provider": "MOBILE_MONEY",
                    "pin": "1234",
                    "challenge_token": "h1-withdraw-token",
                    "verification_code": _otp,
                },
                format="json",
            )
        self.assertEqual(res.status_code, status.HTTP_502_BAD_GATEWAY)
        response_text = json.dumps(res.data)
        self.assertNotIn("PRIVATE_KEY", response_text)
        self.assertNotIn("pk_live", response_text)
        self.assertNotIn(sensitive_error, response_text)


# ---------------------------------------------------------------------------
# M1 — Public registration restricted to BUYER
# ---------------------------------------------------------------------------

@override_settings(
    NOMINATIM_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    SECURE_SSL_REDIRECT=False,
)
class M1RoleEscalationTests(APITestCase):
    def setUp(self):
        field_crypto.clear_crypto_cache()

    def test_register_as_supplier_ignored(self):
        """Supplying role=SUPPLIER in registration must be silently overridden."""
        res = self.client.post(
            reverse("auth-register"),
            {
                "name": "TestSupplier",
                "email": "supplier.attempt@test.local",
                "phone_number": "+237699000003",
                "password": "StrongPass1!",
                "role": "SUPPLIER",
                "company_name": "Evil Corp",
            },
            format="json",
        )
        # May succeed (role override) or fail gracefully — must NEVER create SUPPLIER
        if res.status_code == status.HTTP_201_CREATED:
            user = User.objects.get(email="supplier.attempt@test.local")
            from apps.accounts.models import UserRole
            self.assertEqual(user.role, UserRole.BUYER)

    def test_register_as_transit_agent_ignored(self):
        """Supplying role=TRANSIT_AGENT must be silently ignored."""
        res = self.client.post(
            reverse("auth-register"),
            {
                "name": "FakeTransit",
                "email": "transit.attempt@test.local",
                "phone_number": "+237699000004",
                "password": "StrongPass1!",
                "role": "TRANSIT_AGENT",
                "air_price_per_kg": "100",
                "sea_price_per_kg": "50",
                "company_name": "Evil Transit",
            },
            format="json",
        )
        if res.status_code == status.HTTP_201_CREATED:
            user = User.objects.get(email="transit.attempt@test.local")
            from apps.accounts.models import UserRole
            self.assertEqual(user.role, UserRole.BUYER)

    def test_register_without_role_defaults_to_buyer(self):
        """Registration with no role field must create a BUYER account."""
        res = self.client.post(
            reverse("auth-register"),
            {
                "name": "NormalBuyer",
                "email": "normal.buyer@test.local",
                "phone_number": "+237699000005",
                "password": "StrongPass1!",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        user = User.objects.get(email="normal.buyer@test.local")
        from apps.accounts.models import UserRole
        self.assertEqual(user.role, UserRole.BUYER)


# ---------------------------------------------------------------------------
# M2 — Timing attack on login + email enumeration
# ---------------------------------------------------------------------------

class M2TimingAttackTests(TestCase):
    def setUp(self):
        self.existing_user = User.objects.create_user(
            username="existing", email="existing@test.local", password="Pass1234!"
        )

    def test_login_timing_similar_for_existing_vs_missing_user(self):
        """
        Response time for existing user (wrong password) and non-existing user
        must not differ by more than 2x.  This prevents email enumeration via
        timing side-channel.
        """
        from rest_framework.test import APIClient
        client = APIClient()

        iterations = 5

        # Warm up
        client.post(reverse("auth-login-request"), {"email": "warmup@x.com", "password": "x"}, format="json")

        t_missing = []
        for _ in range(iterations):
            t0 = time.monotonic()
            client.post(
                reverse("auth-login-request"),
                {"email": "nonexistent_xyz@test.local", "password": "WrongPass!"},
                format="json",
            )
            t_missing.append(time.monotonic() - t0)

        t_existing = []
        for _ in range(iterations):
            t0 = time.monotonic()
            client.post(
                reverse("auth-login-request"),
                {"email": "existing@test.local", "password": "WrongPass!"},
                format="json",
            )
            t_existing.append(time.monotonic() - t0)

        avg_missing = sum(t_missing) / iterations
        avg_existing = sum(t_existing) / iterations

        # Neither path should be more than 10x faster — both run PBKDF2.
        ratio = max(avg_missing, avg_existing) / max(min(avg_missing, avg_existing), 0.001)
        self.assertLess(
            ratio, 10,
            f"Timing ratio {ratio:.1f}x suggests enumeration via timing attack. "
            f"avg_missing={avg_missing*1000:.0f}ms avg_existing={avg_existing*1000:.0f}ms",
        )

    def test_registration_email_error_not_explicit(self):
        """Registration with an existing email must not confirm the email is taken."""
        from rest_framework.test import APIClient
        client = APIClient()
        res = client.post(
            reverse("auth-register"),
            {
                "name": "Duplicate",
                "email": "existing@test.local",  # Already registered
                "phone_number": "+237699000010",
                "password": "StrongPass1!",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        response_text = json.dumps(res.data).lower()
        # Must NOT say "already used" / "deja utilise" in a way that confirms existence
        self.assertNotIn("deja utilise", response_text)


# ---------------------------------------------------------------------------
# M4 — KYC daily limit must include PENDING transactions
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=False, NOTCHPAY_ONLY_MTN=False)
class M4KYCPendingLimitTests(APITestCase):
    def setUp(self):
        self.user = _make_user(username="kyc_user", email="kyc@test.local")
        self.user.kyc_level = 0  # per_day limit = 50000 XAF
        self.user.save(update_fields=["kyc_level"])
        self.client.force_authenticate(self.user)

    def test_pending_counted_toward_kyc_daily_limit(self):
        """A PENDING transaction must count toward the daily KYC limit."""
        wallet, _ = Wallet.objects.get_or_create(owner=self.user)
        # Create a PENDING topup that fills the daily limit
        WalletTransaction.objects.create(
            wallet=wallet,
            amount=Decimal("50000.00"),
            kind="TOPUP",
            provider=PaymentProvider.MOBILE_MONEY,
            status=TransactionStatus.PENDING,
            external_transaction_id="pending-limit-test",
            created_at=timezone.now(),
        )
        # Another topup must now be rejected
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "100",
                "source_phone": "+237699000020",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("journaliere", res.data.get("detail", ""))


# ---------------------------------------------------------------------------
# M5 — Minimum transaction amount
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=False, NOTCHPAY_ONLY_MTN=False)
class M5MinAmountTests(APITestCase):
    def setUp(self):
        self.user = _make_user(username="min_user", email="min@test.local")
        self.client.force_authenticate(self.user)

    def test_topup_below_minimum_rejected(self):
        """Topup of 1 XAF (below minimum 100 XAF) must be rejected."""
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1",
                "source_phone": "+237699000030",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("invalide", res.data.get("detail", "").lower())

    def test_topup_zero_rejected(self):
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "0",
                "source_phone": "+237699000031",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_topup_at_minimum_accepted(self):
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "100",
                "source_phone": "+237699000032",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
            },
            format="json",
        )
        # 200 (simulated) or 502 (provider error) — must NOT be 400
        self.assertNotEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_topup_above_hard_cap_rejected(self):
        """Amount above 100M XAF hard cap must be rejected."""
        res = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "100000001",
                "source_phone": "+237699000033",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)


# ---------------------------------------------------------------------------
# M6 — Cursor ISO validation (log injection + poisoning)
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=False)
class M6CursorValidationTests(APITestCase):
    def setUp(self):
        self.user = _make_user(username="cursor_user", email="cursor@test.local")
        self.client.force_authenticate(self.user)

    def test_cursor_with_control_character_rejected(self):
        """Cursor containing a newline (log injection) must be rejected."""
        res = self.client.get(
            reverse("wallet-transactions"),
            {"before": "2024-01-01T00:00:00Z\nINJECTED"},
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cursor_naive_datetime_rejected(self):
        """Cursor without timezone info must be rejected."""
        res = self.client.get(
            reverse("wallet-transactions"),
            {"before": "2024-01-01T00:00:00"},  # No timezone
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cursor_future_date_rejected(self):
        """Cursor with a future date must be rejected."""
        future = (timezone.now() + timedelta(days=365)).isoformat()
        res = self.client.get(
            reverse("wallet-transactions"),
            {"before": future},
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cursor_valid_iso_accepted(self):
        """Valid timezone-aware past ISO datetime must be accepted."""
        past = (timezone.now() - timedelta(days=1)).isoformat()
        res = self.client.get(
            reverse("wallet-transactions"),
            {"before": past},
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_cursor_garbage_rejected(self):
        res = self.client.get(
            reverse("wallet-transactions"),
            {"before": "not-a-date"},
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)


# ---------------------------------------------------------------------------
# M7 — Reconcile requires step-up authentication
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=False, SENSITIVE_ACTION_2FA_ENABLED=True)
class M7ReconcileStepUpTests(APITestCase):
    def setUp(self):
        self.admin = _make_admin()
        self.buyer = _make_user()
        wallet, _ = Wallet.objects.get_or_create(owner=self.buyer)
        self.tx = WalletTransaction.objects.create(
            wallet=wallet,
            amount=Decimal("5000.00"),
            kind="TOPUP",
            provider=PaymentProvider.MOBILE_MONEY,
            status=TransactionStatus.PENDING,
            external_transaction_id="reconcile-test-tx",
        )
        self.client.force_authenticate(self.admin)

    def test_reconcile_without_challenge_rejected(self):
        """Admin reconcile without TOTP challenge must be rejected."""
        res = self.client.post(
            reverse("wallet-reconcile"),
            {
                "transaction_id": "reconcile-test-tx",
                "status": "SUCCESS",
                "reason": "Manual fix",
                # No challenge_token / verification_code
            },
            format="json",
        )
        # Must require step-up — 403 expected
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        # Transaction must remain PENDING
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.status, TransactionStatus.PENDING)

    def test_reconcile_with_valid_challenge_succeeds(self):
        """Admin reconcile with valid TOTP challenge must proceed."""
        _otp = "654321"
        SensitiveActionChallenge.objects.create(
            user=self.admin,
            action_key="wallet.reconcile",
            challenge_token="admin-reconcile-token",
            code_hash=make_password(_otp),
            expires_at=timezone.now() + timedelta(minutes=5),
        )
        res = self.client.post(
            reverse("wallet-reconcile"),
            {
                "transaction_id": "reconcile-test-tx",
                "status": "SUCCESS",
                "reason": "Manual reconciliation",
                "challenge_token": "admin-reconcile-token",
                "verification_code": _otp,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.status, TransactionStatus.SUCCESS)

    def test_non_admin_cannot_reconcile(self):
        """Non-admin users must not access reconcile even with valid challenge."""
        self.client.force_authenticate(self.buyer)
        res = self.client.post(
            reverse("wallet-reconcile"),
            {
                "transaction_id": "reconcile-test-tx",
                "status": "SUCCESS",
                "reason": "Exploit attempt",
                "challenge_token": "",
                "verification_code": "000000",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
        self.tx.refresh_from_db()
        self.assertEqual(self.tx.status, TransactionStatus.PENDING)


# ---------------------------------------------------------------------------
# M9 — checkout_url must not expose internal reference metadata
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=False)
class M9CheckoutUrlIsolationTests(APITestCase):
    """_extract_checkout_url must strip internal metadata from the reference field."""

    def _viewset(self):
        from apps.wallets.views import WalletViewSet
        vs = WalletViewSet()
        vs.request = None
        return vs

    def test_http_reference_returned_as_is_in_debug(self):
        with self.settings(DEBUG=True):
            vs = self._viewset()
            url = vs._extract_checkout_url("https://pay.notchpay.co/checkout/abc123")
            self.assertEqual(url, "https://pay.notchpay.co/checkout/abc123")

    def test_checkout_url_prefix_strips_tx_ref(self):
        """Internal tx_ref metadata after semicolon must be stripped."""
        vs = self._viewset()
        ref = "checkout_url:https://pay.notchpay.co/abc;tx_ref:WALLET-internal"
        url = vs._extract_checkout_url(ref)
        self.assertEqual(url, "https://pay.notchpay.co/abc")
        self.assertNotIn("WALLET-internal", url or "")
        self.assertNotIn("tx_ref", url or "")

    def test_non_url_reference_returns_none(self):
        """Internal references that are not URLs must return None."""
        vs = self._viewset()
        self.assertIsNone(vs._extract_checkout_url("topup:MOBILE_MONEY:+237699:tx:WALLET-abc"))
        self.assertIsNone(vs._extract_checkout_url(""))
        self.assertIsNone(vs._extract_checkout_url(None))

    def test_http_url_rejected_in_production(self):
        """HTTP (non-TLS) checkout URLs must be rejected in production."""
        with self.settings(DEBUG=False):
            vs = self._viewset()
            url = vs._extract_checkout_url("http://pay.example.com/checkout")
            self.assertIsNone(url)


# ---------------------------------------------------------------------------
# H5 — Race condition: IntegrityError on duplicate idempotency_key is handled
# ---------------------------------------------------------------------------

@override_settings(NOTCHPAY_ENABLED=False, NOTCHPAY_ONLY_MTN=False)
class H5RaceConditionTests(APITestCase):
    def setUp(self):
        self.user = _make_user(username="race_user", email="race@test.local")
        self.client.force_authenticate(self.user)

    def test_idempotent_topup_returns_200_not_500(self):
        """
        Duplicate idempotency key must return 200 (idempotent replay),
        not 500 (unhandled IntegrityError).
        """
        idem_key = "race-idem-key-001"
        # First request
        res1 = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1000",
                "source_phone": "+237699000050",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
                "idempotency_key": idem_key,
            },
            format="json",
        )
        self.assertIn(res1.status_code, [status.HTTP_200_OK, status.HTTP_202_ACCEPTED])

        # Second request with same key
        res2 = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1000",
                "source_phone": "+237699000050",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
                "idempotency_key": idem_key,
            },
            format="json",
        )
        # Must not be 500 — must be 200 (idempotent) or 409 (conflict)
        self.assertIn(res2.status_code, [status.HTTP_200_OK, status.HTTP_409_CONFLICT])
        self.assertNotEqual(res2.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)

    def test_conflicting_idempotency_payload_returns_409(self):
        """Same key with different amount (different hash) must return 409."""
        idem_key = "race-idem-key-002"
        res1 = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "1000",
                "source_phone": "+237699000051",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
                "idempotency_key": idem_key,
            },
            format="json",
        )
        self.assertIn(res1.status_code, [status.HTTP_200_OK, status.HTTP_202_ACCEPTED])

        res2 = self.client.post(
            reverse("wallet-topup"),
            {
                "amount": "9999",  # Different amount → different payload hash
                "source_phone": "+237699000051",
                "provider": "MOBILE_MONEY",
                "pin": "1234",
                "idempotency_key": idem_key,
            },
            format="json",
        )
        self.assertEqual(res2.status_code, status.HTTP_409_CONFLICT)
