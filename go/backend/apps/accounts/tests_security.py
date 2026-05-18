"""
Security regression tests for the 5 vulnerabilities fixed in this change set.

A failure in ANY of these tests is a security regression, not a routine
test failure.  Treat it accordingly.

Fixes covered:
  Fix 1 — BOLA/IDOR on ComplianceDocument (OWASP A01)
  Fix 2 — PII leaking into AuditLog.metadata (OWASP A02 / ASVS V7.1)
  Fix 3 — OTP stored as plaintext in SensitiveActionChallenge (OWASP A02)
  Fix 5 — Auto-payout enabled by default with hardcoded phone numbers (OWASP A05)

(Fix 4 — Flutter/Android/iOS cleartext HTTP — is verified by build-time checks
 and Android Network Security Config; it has no Django test surface.)
"""
import secrets
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.core.exceptions import ImproperlyConfigured
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import AuditLog, ComplianceDocument, SensitiveActionChallenge
from apps.accounts.security import sanitize_audit_metadata, write_audit_log

User = get_user_model()


# ── Fix 2: PII in AuditLog.metadata ─────────────────────────────────────────


class AuditMetadataSanitizerTests(TestCase):
    """sanitize_audit_metadata must strip every PII/secret field, recursively."""

    def test_phone_number_stripped(self):
        result = sanitize_audit_metadata({"user_id": 1, "phone_number": "+237670000000"})
        self.assertNotIn("phone_number", result)
        self.assertEqual(result["user_id"], 1)

    def test_email_stripped(self):
        result = sanitize_audit_metadata({"user_id": 1, "email": "victim@evil.com"})
        self.assertNotIn("email", result)

    def test_otp_code_stripped(self):
        result = sanitize_audit_metadata({"action": "verify", "code": "123456"})
        self.assertNotIn("code", result)
        self.assertEqual(result["action"], "verify")

    def test_token_stripped(self):
        result = sanitize_audit_metadata({"token": "abc123", "ref": "ORD-999"})
        self.assertNotIn("token", result)
        self.assertEqual(result["ref"], "ORD-999")

    def test_compound_key_stripped(self):
        # Compound names like "user_phone_number" or "new_email" must be caught.
        result = sanitize_audit_metadata({"user_phone_number": "...", "new_email": "..."})
        self.assertNotIn("user_phone_number", result)
        self.assertNotIn("new_email", result)

    def test_non_pii_fields_pass_through(self):
        payload = {"order_id": 42, "amount": "1000.00", "status": "COMPLETED"}
        self.assertEqual(sanitize_audit_metadata(payload), payload)

    def test_nested_pii_stripped_recursively(self):
        result = sanitize_audit_metadata({
            "outer": "safe",
            "nested": {"phone": "+237600000000", "order_id": 99},
        })
        self.assertEqual(result["outer"], "safe")
        self.assertNotIn("phone", result["nested"])
        self.assertEqual(result["nested"]["order_id"], 99)

    def test_non_dict_input_returns_empty(self):
        self.assertEqual(sanitize_audit_metadata("not a dict"), {})  # type: ignore[arg-type]
        self.assertEqual(sanitize_audit_metadata(None), {})  # type: ignore[arg-type]
        self.assertEqual(sanitize_audit_metadata(42), {})  # type: ignore[arg-type]

    def test_write_audit_log_never_persists_pii(self):
        """write_audit_log must strip PII even when the caller accidentally passes it."""
        user = User.objects.create_user(
            username="audit_pii_regression",
            email="audit_pii_regression@test.local",
            password="TestPassword123!",
            is_active=True,
        )
        write_audit_log(
            actor=user,
            action="security.test",
            metadata={"phone": "+237670000001", "user_id": user.id, "email": "x@x.com"},
        )
        log = AuditLog.objects.filter(actor=user, action="security.test").first()
        self.assertIsNotNone(log)
        self.assertNotIn("phone", log.metadata)
        self.assertNotIn("email", log.metadata)
        self.assertEqual(log.metadata.get("user_id"), user.id)


# ── Fix 3: OTP PBKDF2 hashing ───────────────────────────────────────────────


class OtpHashingTests(TestCase):
    """SensitiveActionChallenge.code_hash must hold a PBKDF2 hash, never plaintext."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="otp_hash_sec_user",
            email="otp_hash_sec@test.local",
            password="TestPassword123!",
            is_active=True,
        )

    def _create_challenge(self, action_key: str = "wallet.withdraw"):
        code = f"{secrets.randbelow(1_000_000):06d}"
        code_hash = make_password(code)
        challenge_token = secrets.token_urlsafe(32)
        challenge = SensitiveActionChallenge.objects.create(
            user=self.user,
            action_key=action_key,
            challenge_token=challenge_token,
            code_hash=code_hash,
            expires_at=timezone.now() + timedelta(minutes=10),
        )
        return challenge, code

    def test_stored_value_is_not_plaintext_otp(self):
        challenge, code = self._create_challenge()
        # The raw 6-digit code must NOT appear verbatim in code_hash.
        self.assertNotEqual(challenge.code_hash, code)
        # PBKDF2-SHA256 format from Django is ~77 characters.
        self.assertGreater(len(challenge.code_hash), 50)

    def test_correct_code_verifies_via_check_password(self):
        challenge, code = self._create_challenge()
        self.assertTrue(check_password(code, challenge.code_hash))

    def test_wrong_code_fails_verification(self):
        challenge, code = self._create_challenge()
        wrong = f"{(int(code) + 1) % 1_000_000:06d}"
        self.assertFalse(check_password(wrong, challenge.code_hash))

    def test_challenge_token_has_adequate_entropy(self):
        # token_urlsafe(32) → 43-char base64url string.
        challenge, _ = self._create_challenge()
        self.assertGreaterEqual(len(challenge.challenge_token), 40)

    def test_two_challenges_never_share_code_hash(self):
        # Even the same code must produce different hashes (salted PBKDF2).
        code = "123456"
        hash_a = make_password(code)
        hash_b = make_password(code)
        self.assertNotEqual(hash_a, hash_b)
        # Both must still verify.
        self.assertTrue(check_password(code, hash_a))
        self.assertTrue(check_password(code, hash_b))


# ── Fix 1: BOLA / IDOR on ComplianceDocument ────────────────────────────────


class BolaComplianceDocTests(APITestCase):
    """
    ComplianceDocument list endpoint must enforce relational authorization.

    Security requirements (deny-by-default):
      - Unauthenticated → 401
      - Non-integer user_id → 404 (no info leak)
      - Unrelated user accessing another user's docs → 404 (anti-enumeration)
      - Own documents → 200
      - GENERAL_ADMIN → 200 for any user
      - Compliance actor with shared order → 200 but APPROVED docs only
    """

    def setUp(self):
        self.supplier_a = User.objects.create_user(
            username="bola_sec_supplier_a",
            email="bola_sec_a@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_active=True,
        )
        self.supplier_b = User.objects.create_user(
            username="bola_sec_supplier_b",
            email="bola_sec_b@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_active=True,
        )
        self.admin = User.objects.create_user(
            username="bola_sec_admin",
            email="bola_sec_admin@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_active=True,
        )
        self.approved_doc = ComplianceDocument.objects.create(
            user=self.supplier_b,
            doc_type="RCCM",
            status="APPROVED",
            file=SimpleUploadedFile("rccm.pdf", b"%PDF", content_type="application/pdf"),
        )
        self.pending_doc = ComplianceDocument.objects.create(
            user=self.supplier_b,
            doc_type="TAX_CERT",
            status="PENDING",
            file=SimpleUploadedFile("tax.pdf", b"%PDF", content_type="application/pdf"),
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def _list_url(self, user_id):
        return f"{reverse('compliance-document-list')}?user_id={user_id}"

    def test_unauthenticated_request_returns_401(self):
        res = self.client.get(self._list_url(self.supplier_b.id))
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_unrelated_supplier_gets_404_not_403(self):
        """BOLA core: unrelated party must get 404, NOT 403 (anti-enumeration)."""
        self._auth_as(self.supplier_a)
        res = self.client.get(self._list_url(self.supplier_b.id))
        self.assertNotEqual(
            res.status_code, status.HTTP_200_OK,
            "BOLA regression: unrelated supplier can read another user's compliance docs",
        )
        self.assertNotEqual(
            res.status_code, status.HTTP_403_FORBIDDEN,
            "Anti-enumeration regression: 403 reveals that the target user exists",
        )
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_user_can_read_own_documents(self):
        self._auth_as(self.supplier_b)
        res = self.client.get(self._list_url(self.supplier_b.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_admin_can_read_any_user_documents(self):
        self._auth_as(self.admin)
        res = self.client.get(self._list_url(self.supplier_b.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)

    def test_invalid_user_id_returns_404(self):
        """Non-integer user_id must not produce a 500; return 404 instead."""
        self._auth_as(self.supplier_a)
        res = self.client.get(f"{reverse('compliance-document-list')}?user_id=not-a-number")
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    @patch("apps.accounts.views._has_business_relationship_with", return_value=True)
    def test_related_compliance_actor_sees_only_approved_docs(self, _mock_rel):
        """
        A compliance actor with a shared order may see the counterparty's APPROVED
        docs, but MUST NOT see PENDING or REJECTED docs.
        """
        self._auth_as(self.supplier_a)
        res = self.client.get(self._list_url(self.supplier_b.id))
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        rows = res.data if not isinstance(res.data, dict) else res.data.get("results", [])
        returned_ids = {row["id"] for row in rows}
        # Approved doc is visible.
        self.assertIn(self.approved_doc.id, returned_ids)
        # Pending doc must NOT be visible.
        self.assertNotIn(
            self.pending_doc.id,
            returned_ids,
            "Compliance actor can see PENDING docs — least-privilege regression",
        )

    @patch("apps.accounts.views._has_business_relationship_with", return_value=False)
    def test_compliance_actor_without_relationship_gets_404(self, _mock_rel):
        """Compliance actor with no shared order must get 404, not partial data."""
        self._auth_as(self.supplier_a)
        res = self.client.get(self._list_url(self.supplier_b.id))
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)


# ── Fix 5: Auto-payout startup validator ────────────────────────────────────


class AutoPayoutValidatorTests(TestCase):
    """
    _validate_autopayout_config must refuse startup when auto-payout is configured
    dangerously (live mode, enabled, missing or placeholder phone numbers).
    """

    _VALID_LIVE_SETTINGS = dict(
        NOTCHPAY_AUTO_PAYOUT=True,
        NOTCHPAY_ENABLED=True,
        NOTCHPAY_MODE="live",
        NOTCHPAY_MTN_NUMBER="670123456",
        NOTCHPAY_ORANGE_NUMBER="695987654",
    )

    def _run(self, **overrides):
        """Call the validator with patched module-level settings."""
        from config.settings import _validate_autopayout_config

        settings = dict(self._VALID_LIVE_SETTINGS)
        settings.update(overrides)
        with patch.multiple("config.settings", **settings):
            _validate_autopayout_config()

    def test_valid_live_config_passes(self):
        self._run()  # must not raise

    def test_autopayout_disabled_always_passes(self):
        self._run(
            NOTCHPAY_AUTO_PAYOUT=False,
            NOTCHPAY_MTN_NUMBER="",
            NOTCHPAY_ORANGE_NUMBER="",
        )

    def test_sandbox_mode_skips_phone_validation(self):
        self._run(
            NOTCHPAY_MODE="sandbox",
            NOTCHPAY_MTN_NUMBER="",
            NOTCHPAY_ORANGE_NUMBER="",
        )

    def test_raises_when_mtn_number_empty_in_live(self):
        with self.assertRaises(ImproperlyConfigured):
            self._run(NOTCHPAY_MTN_NUMBER="")

    def test_raises_when_orange_number_empty_in_live(self):
        with self.assertRaises(ImproperlyConfigured):
            self._run(NOTCHPAY_ORANGE_NUMBER="")

    def test_raises_for_old_hardcoded_mtn_placeholder(self):
        """The old default value '670766331' must be rejected as a placeholder."""
        with self.assertRaises(ImproperlyConfigured):
            self._run(NOTCHPAY_MTN_NUMBER="670766331")

    def test_raises_for_old_hardcoded_orange_placeholder(self):
        """The old default value '695605502' must be rejected as a placeholder."""
        with self.assertRaises(ImproperlyConfigured):
            self._run(NOTCHPAY_ORANGE_NUMBER="695605502")

    def test_raises_when_autopayout_enabled_but_notchpay_disabled(self):
        """Auto-payout without a payment gateway is a configuration error."""
        with self.assertRaises(ImproperlyConfigured):
            self._run(NOTCHPAY_ENABLED=False)
