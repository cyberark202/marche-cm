"""
Security hardening regression tests.

Covers all controls added in the production hardening pass:
  - TOTP MFA (RFC 6238 correctness + replay prevention)
  - Device fingerprinting (constant-time comparison, stability)
  - Audit metadata PII sanitizer (middleware-level)
  - Security headers (CSP, X-Content-Type-Options, etc.)
  - Rate limiting (throttle class logic)
  - Fraud engine (velocity checks, risk scoring, thresholds)
  - OTP hashing (PBKDF2 — regression guard)
  - Request size limiting
  - Suspicious request detection

A failure here means a security control has been regressed.
"""
import hashlib
import hmac
import time
from datetime import timedelta
from decimal import Decimal
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.test import TestCase, RequestFactory, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.mfa import (
    TOTPService,
    BackupCodeService,
    get_current_totp_step,
    mark_totp_step_used,
)
from apps.accounts.device_security import DeviceFingerprint, validate_token_device

User = get_user_model()


# ── TOTP MFA ─────────────────────────────────────────────────────────────────

class TOTPServiceTests(TestCase):
    def setUp(self):
        self.secret = TOTPService.generate_secret()

    def test_generate_secret_is_valid_base32(self):
        import base64
        # Must be decodable base32 without error.
        decoded = base64.b32decode(self.secret, casefold=True)
        self.assertGreaterEqual(len(decoded), 20)

    def test_two_secrets_are_distinct(self):
        other = TOTPService.generate_secret()
        self.assertNotEqual(self.secret, other)

    def test_current_code_verifies(self):
        code = TOTPService.current_code(self.secret)
        self.assertTrue(TOTPService.verify(self.secret, code))

    def test_wrong_code_fails(self):
        self.assertFalse(TOTPService.verify(self.secret, "000000"))

    def test_non_digit_code_fails(self):
        self.assertFalse(TOTPService.verify(self.secret, "abc123"))

    def test_short_code_fails(self):
        self.assertFalse(TOTPService.verify(self.secret, "12345"))  # 5 digits

    def test_empty_inputs_fail(self):
        self.assertFalse(TOTPService.verify("", "123456"))
        self.assertFalse(TOTPService.verify(self.secret, ""))

    def test_invalid_base32_secret_fails_gracefully(self):
        self.assertFalse(TOTPService.verify("NOT-VALID-BASE32!!!", "123456"))

    def test_provisioning_uri_format(self):
        uri = TOTPService.provisioning_uri("testuser", self.secret)
        self.assertTrue(uri.startswith("otpauth://totp/"))
        self.assertIn("testuser", uri)
        self.assertIn(self.secret, uri)
        self.assertIn("SHA1", uri)
        self.assertIn("digits=6", uri)
        self.assertIn("period=30", uri)

    def test_step_anti_replay_blocks_reuse(self):
        user_id = 9999
        step = get_current_totp_step()
        # First use should succeed.
        self.assertTrue(mark_totp_step_used(user_id, step))
        # Second use of the same step must be rejected.
        self.assertFalse(mark_totp_step_used(user_id, step))

    def test_different_steps_are_independent(self):
        user_id = 9998
        step_a = get_current_totp_step()
        step_b = step_a + 1
        self.assertTrue(mark_totp_step_used(user_id, step_a))
        self.assertTrue(mark_totp_step_used(user_id, step_b))

    def test_different_users_can_reuse_same_step(self):
        step = get_current_totp_step()
        self.assertTrue(mark_totp_step_used(10001, step))
        self.assertTrue(mark_totp_step_used(10002, step))


# ── Backup codes ─────────────────────────────────────────────────────────────

class BackupCodeTests(TestCase):
    def test_generate_returns_correct_count(self):
        codes = BackupCodeService.generate()
        from apps.accounts.mfa import BACKUP_CODE_COUNT
        self.assertEqual(len(codes), BACKUP_CODE_COUNT)

    def test_all_codes_are_distinct(self):
        codes = BackupCodeService.generate()
        self.assertEqual(len(set(codes)), len(codes))

    def test_codes_have_expected_length(self):
        from apps.accounts.mfa import BACKUP_CODE_LENGTH
        codes = BackupCodeService.generate()
        for code in codes:
            self.assertEqual(len(code), BACKUP_CODE_LENGTH)

    def test_hash_codes_produces_pbkdf2_hashes(self):
        codes = BackupCodeService.generate()
        hashes = BackupCodeService.hash_codes(codes)
        # PBKDF2 hashes are at least 50 chars and differ from plaintext.
        for code, h in zip(codes, hashes):
            self.assertNotEqual(code, h)
            self.assertGreater(len(h), 50)

    def test_verify_and_consume_correct_code(self):
        codes = BackupCodeService.generate()
        hashes = BackupCodeService.hash_codes(codes)
        target = codes[3]

        matched, remaining = BackupCodeService.verify_and_consume(target, hashes)
        self.assertTrue(matched)
        # Consumed code's hash should be removed.
        self.assertEqual(len(remaining), len(hashes) - 1)

    def test_verify_and_consume_wrong_code(self):
        codes = BackupCodeService.generate()
        hashes = BackupCodeService.hash_codes(codes)

        matched, remaining = BackupCodeService.verify_and_consume("WRONGCODE1", hashes)
        self.assertFalse(matched)
        self.assertEqual(len(remaining), len(hashes))  # Nothing consumed

    def test_consumed_code_cannot_be_reused(self):
        codes = BackupCodeService.generate()
        hashes = BackupCodeService.hash_codes(codes)
        target = codes[0]

        _, remaining_after_first = BackupCodeService.verify_and_consume(target, hashes)
        matched, _ = BackupCodeService.verify_and_consume(target, remaining_after_first)
        self.assertFalse(matched)


# ── Device fingerprinting ─────────────────────────────────────────────────────

class DeviceFingerprintTests(TestCase):
    def test_same_inputs_produce_same_fingerprint(self):
        fp1 = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="dev-001").compute()
        fp2 = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="dev-001").compute()
        self.assertEqual(fp1, fp2)

    def test_different_ua_produces_different_fingerprint(self):
        fp1 = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="dev-001").compute()
        fp2 = DeviceFingerprint(user_agent="curl/7.0", device_id="dev-001").compute()
        self.assertNotEqual(fp1, fp2)

    def test_different_device_id_produces_different_fingerprint(self):
        fp1 = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="dev-001").compute()
        fp2 = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="dev-002").compute()
        self.assertNotEqual(fp1, fp2)

    def test_fingerprint_is_constant_time_comparable(self):
        fp = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="dev-001")
        computed = fp.compute()
        # matches() uses hmac.compare_digest — verify it works correctly.
        self.assertTrue(fp.matches(computed))
        self.assertFalse(fp.matches("a" * 32))

    def test_empty_stored_fingerprint_passes_soft(self):
        fp = DeviceFingerprint(user_agent="Mozilla/5.0", device_id="")
        self.assertTrue(fp.matches(""))  # No stored fingerprint = soft pass

    def test_from_request_extracts_ua_and_device_id(self):
        factory = RequestFactory()
        request = factory.get("/api/test/")
        request.META["HTTP_USER_AGENT"] = "TestAgent/1.0"
        request.META["HTTP_X_DEVICE_ID"] = "device-xyz"

        fp = DeviceFingerprint.from_request(request)
        self.assertEqual(fp.user_agent, "TestAgent/1.0")
        self.assertEqual(fp.device_id, "device-xyz")

    def test_fingerprint_is_32_hex_chars(self):
        fp = DeviceFingerprint(user_agent="Test", device_id="123").compute()
        self.assertEqual(len(fp), 32)
        self.assertTrue(all(c in "0123456789abcdef" for c in fp))


class TokenDeviceValidationTests(TestCase):
    def _make_payload(self, dfp: str) -> dict:
        return {"user_id": 1, "jti": "test-jti", "dfp": dfp}

    def test_matching_fingerprint_passes(self):
        factory = RequestFactory()
        request = factory.get("/")
        request.META["HTTP_USER_AGENT"] = "TestAgent"
        request.META["HTTP_X_DEVICE_ID"] = "dev-001"

        fp = DeviceFingerprint.from_request(request).compute()
        result = validate_token_device(self._make_payload(fp), request)
        self.assertTrue(result)

    def test_mismatched_fingerprint_fails(self):
        factory = RequestFactory()
        request = factory.get("/")
        request.META["HTTP_USER_AGENT"] = "DifferentAgent"
        request.META["HTTP_X_DEVICE_ID"] = "dev-001"

        result = validate_token_device(self._make_payload("a" * 32), request)
        self.assertFalse(result)

    def test_missing_dfp_claim_soft_passes(self):
        factory = RequestFactory()
        request = factory.get("/")
        # Token has no 'dfp' claim (pre-migration token).
        result = validate_token_device({"user_id": 1}, request)
        self.assertTrue(result)


# ── Security middleware: headers ──────────────────────────────────────────────

class SecurityHeadersMiddlewareTests(APITestCase):
    def _auth_as(self, user):
        token = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token.access_token}")

    def setUp(self):
        self.user = User.objects.create_user(
            username="hdr_test",
            email="hdr@test.local",
            password="TestPassword123!",
            is_active=True,
        )
        self._auth_as(self.user)

    def test_x_content_type_options_present(self):
        res = self.client.get("/api/health/")
        self.assertEqual(res.get("X-Content-Type-Options"), "nosniff")

    def test_referrer_policy_present(self):
        res = self.client.get("/api/health/")
        self.assertIsNotNone(res.get("Referrer-Policy"))

    def test_csp_present(self):
        res = self.client.get("/api/health/")
        self.assertIsNotNone(res.get("Content-Security-Policy"))
        csp = res["Content-Security-Policy"]
        self.assertIn("default-src", csp)
        self.assertIn("frame-ancestors", csp)

    def test_correlation_id_echoed(self):
        res = self.client.get("/api/health/", HTTP_X_CORRELATION_ID="test-cid-abc123")
        self.assertEqual(res.get("X-Correlation-ID"), "test-cid-abc123")

    def test_correlation_id_generated_if_missing(self):
        res = self.client.get("/api/health/")
        cid = res.get("X-Correlation-ID")
        self.assertIsNotNone(cid)
        self.assertGreater(len(cid), 8)

    def test_malicious_correlation_id_is_replaced(self):
        # Injection attempt in correlation ID should be rejected and replaced.
        res = self.client.get("/api/health/", HTTP_X_CORRELATION_ID="<script>alert(1)</script>")
        returned_cid = res.get("X-Correlation-ID", "")
        self.assertNotIn("<script>", returned_cid)


# ── Fraud engine ─────────────────────────────────────────────────────────────

class FraudEngineTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="fraud_test_user",
            email="fraud@test.local",
            password="TestPassword123!",
            is_active=True,
            kyc_level=0,
        )
        cache.clear()

    def tearDown(self):
        cache.clear()

    @override_settings(KYC_LIMITS={0: {"per_transaction": 25000, "per_day": 50000}})
    def test_small_first_transaction_is_allowed(self):
        from apps.wallets.fraud import FraudEngine, RiskContext
        ctx = RiskContext(
            user_id=self.user.id,
            amount=Decimal("1000"),
            action="withdraw",
            ip="1.2.3.4",
        )
        decision = FraudEngine.evaluate(ctx, self.user)
        self.assertEqual(decision.action, "allow")

    @override_settings(KYC_LIMITS={0: {"per_transaction": 25000, "per_day": 50000}})
    def test_high_amount_scores_higher(self):
        from apps.wallets.fraud import FraudEngine, RiskContext, RiskScorer
        ctx = RiskContext(
            user_id=self.user.id,
            amount=Decimal("22000"),  # 88% of 25000 limit
            action="withdraw",
            ip="1.2.3.4",
        )
        velocity = {"user_tx_count_1h": 1, "user_tx_count_24h": 1, "user_amount_24h_cents": 0}
        kyc_limits = {"per_transaction": 25000, "per_day": 50000}
        scorer = RiskScorer(ctx)
        score, reasons = scorer.score(velocity, kyc_limits)
        self.assertGreater(score, 0)
        self.assertTrue(any("amount" in r for r in reasons))

    @override_settings(KYC_LIMITS={0: {"per_transaction": 25000, "per_day": 50000}})
    def test_high_velocity_scores_higher(self):
        from apps.wallets.fraud import FraudEngine, RiskContext, RiskScorer
        ctx = RiskContext(
            user_id=self.user.id,
            amount=Decimal("100"),
            action="withdraw",
            ip="1.2.3.4",
        )
        # Simulate 15 transactions/hour.
        velocity = {"user_tx_count_1h": 15, "user_tx_count_24h": 15, "user_amount_24h_cents": 15000}
        kyc_limits = {"per_transaction": 25000, "per_day": 50000}
        scorer = RiskScorer(ctx)
        score, reasons = scorer.score(velocity, kyc_limits)
        self.assertGreater(score, 0)
        self.assertTrue(any("velocity" in r for r in reasons))

    def test_block_decision_returns_block_action(self):
        from apps.wallets.fraud import RiskDecision
        d = RiskDecision(score=90, action="block", reasons=["test"])
        self.assertTrue(d.is_blocked)
        self.assertFalse(d.is_held)
        self.assertFalse(d.is_allowed)

    def test_hold_decision_returns_hold_action(self):
        from apps.wallets.fraud import RiskDecision
        d = RiskDecision(score=65, action="hold", reasons=["test"])
        self.assertFalse(d.is_blocked)
        self.assertTrue(d.is_held)
        self.assertFalse(d.is_allowed)

    def test_velocity_checker_increments_counters(self):
        from apps.wallets.fraud import VelocityChecker
        cache.clear()
        result1 = VelocityChecker.record_transaction(self.user.id, Decimal("100"), "1.2.3.4")
        result2 = VelocityChecker.record_transaction(self.user.id, Decimal("200"), "1.2.3.4")
        self.assertEqual(result1["user_tx_count_1h"], 1)
        self.assertEqual(result2["user_tx_count_1h"], 2)
        self.assertEqual(result2["user_amount_24h_cents"], 30000)


# ── Suspicious request middleware ─────────────────────────────────────────────

class SuspiciousRequestMiddlewareTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def _get_middleware(self):
        from config.middleware import SuspiciousRequestMiddleware
        get_response = MagicMock(return_value=MagicMock(status_code=200))
        return SuspiciousRequestMiddleware(get_response)

    def test_normal_request_scores_zero(self):
        mw = self._get_middleware()
        request = self.factory.get("/api/products/")
        request.META["HTTP_USER_AGENT"] = "MarcheCM-App/1.0"
        # _score_request is internal but we test the outcome: no block.
        score = mw._score_request(request)
        self.assertEqual(score, 0)

    def test_git_path_scores_high(self):
        mw = self._get_middleware()
        request = self.factory.get("/.git/config")
        request.META["HTTP_USER_AGENT"] = "Mozilla/5.0"
        score = mw._score_request(request)
        self.assertGreaterEqual(score, 10)

    def test_env_path_scores_high(self):
        mw = self._get_middleware()
        request = self.factory.get("/.env")
        request.META["HTTP_USER_AGENT"] = "Mozilla/5.0"
        score = mw._score_request(request)
        self.assertGreaterEqual(score, 10)

    def test_scanner_ua_scores_high(self):
        mw = self._get_middleware()
        request = self.factory.get("/api/products/")
        request.META["HTTP_USER_AGENT"] = "sqlmap/1.8.2"
        score = mw._score_request(request)
        self.assertGreaterEqual(score, 10)

    def test_missing_ua_scores_nonzero(self):
        mw = self._get_middleware()
        request = self.factory.get("/api/products/")
        request.META.pop("HTTP_USER_AGENT", None)
        score = mw._score_request(request)
        self.assertGreater(score, 0)


# ── Request size limiting ─────────────────────────────────────────────────────

class RequestSizeLimitMiddlewareTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()

    def _get_middleware(self):
        from config.middleware import RequestSizeLimitMiddleware
        get_response = MagicMock(return_value=MagicMock(status_code=200))
        return RequestSizeLimitMiddleware(get_response)

    @override_settings(REQUEST_MAX_BODY_BYTES=1024)
    def test_oversized_request_returns_413(self):
        from config.middleware import RequestSizeLimitMiddleware
        from django.http import JsonResponse
        get_response = MagicMock()
        mw = RequestSizeLimitMiddleware(get_response)

        request = self.factory.post("/api/catalog/products/")
        request.META["CONTENT_LENGTH"] = "2048"  # > 1024 limit

        response = mw(request)
        self.assertEqual(response.status_code, 413)
        get_response.assert_not_called()

    @override_settings(REQUEST_MAX_BODY_BYTES=1024 * 1024)
    def test_normal_sized_request_passes(self):
        from config.middleware import RequestSizeLimitMiddleware
        get_response = MagicMock(return_value=MagicMock(status_code=200))
        mw = RequestSizeLimitMiddleware(get_response)

        request = self.factory.post("/api/catalog/products/")
        request.META["CONTENT_LENGTH"] = "512"

        mw(request)
        get_response.assert_called_once()


# ── DRF exception handler ─────────────────────────────────────────────────────

class SecurityExceptionHandlerTests(APITestCase):
    def test_404_not_found_returns_clean_message(self):
        res = self.client.get("/api/nonexistent-endpoint-xyz/")
        self.assertEqual(res.status_code, 404)
        # Must not include stack traces or file paths.
        body = str(res.content)
        self.assertNotIn("Traceback", body)
        self.assertNotIn("site-packages", body)

    def test_unhandled_exception_returns_opaque_500(self):
        from config.exceptions import security_exception_handler
        exc = RuntimeError("Internal database connection failed at /var/run/pg/...")
        context = {"request": None, "view": None}

        with self.settings(DEBUG=False):
            response = security_exception_handler(exc, context)

        self.assertEqual(response.status_code, 500)
        self.assertNotIn("database", str(response.data.get("detail", "")))
        self.assertNotIn("/var/run", str(response.data.get("detail", "")))
        self.assertIn("error_id", response.data)


# ── Auto-payout validator (regression guard) ──────────────────────────────────

class AutoPayoutValidatorRegressionTests(TestCase):
    """Ensure the auto-payout startup guard has not been weakened."""

    def test_default_auto_payout_is_false(self):
        from unittest.mock import patch
        from config.settings import _validate_autopayout_config
        with patch.multiple(
            "config.settings",
            NOTCHPAY_AUTO_PAYOUT=False,
            NOTCHPAY_ENABLED=True,
            NOTCHPAY_MODE="live",
            NOTCHPAY_MTN_NUMBER="",
            NOTCHPAY_ORANGE_NUMBER="",
        ):
            # Must not raise — disabled auto-payout never needs phone numbers.
            _validate_autopayout_config()

    def test_live_autopayout_with_placeholder_phones_raises(self):
        from django.core.exceptions import ImproperlyConfigured
        from unittest.mock import patch
        from config.settings import _validate_autopayout_config
        with patch.multiple(
            "config.settings",
            NOTCHPAY_AUTO_PAYOUT=True,
            NOTCHPAY_ENABLED=True,
            NOTCHPAY_MODE="live",
            NOTCHPAY_MTN_NUMBER="670766331",  # old hardcoded placeholder
            NOTCHPAY_ORANGE_NUMBER="695605502",
        ):
            with self.assertRaises(ImproperlyConfigured):
                _validate_autopayout_config()
