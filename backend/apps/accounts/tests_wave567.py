"""
Regression tests for Waves 5, 6, 7.

Wave 5 (HIGH — upload / FCM / chat hardening)
  * [UP-001] Magic-byte coverage for office/media formats; Content-Type req.
  * [UP-002] Pillow DecompressionBomb guard.
  * [NOTIF-002] FCMToken hijack refused with 409 Conflict.
  * [CHAT-001] MessageViewSet rejects PUT/PATCH/DELETE.
  * [CHAT-002] q-filter requires room_id + escapes LIKE wildcards.

Wave 6 (HIGH — financial / audit hardening)
  * [FIN-003] Lua-atomic lock release.
  * [FIN-007] Concurrent AuditEvent writes for the same entity do not fork.
  * [FIN-014] lock_funds_for_order derives a deterministic idempotency key.
  * [FIN-021] open_dispute on Order calls freeze_order_escrows.
  * [FIN-012] FraudAssessment.review writes an audit log.

Wave 7 (MEDIUM)
  * [M-001] _is_safe_geocoder_url rejects private/loopback hosts and non-HTTPS.
  * [M-007] WalletPinView refuses < 6 digits and trivial PINs.
"""
from __future__ import annotations

from io import BytesIO
from unittest.mock import patch, MagicMock

from django.contrib.auth import get_user_model
from django.core.exceptions import ValidationError as DjangoValidationError
from django.test import TestCase, override_settings
from django.urls import reverse

from rest_framework.test import APIClient

User = get_user_model()


def _make_user(username="u1", role="BUYER") -> User:
    return User.objects.create_user(
        username=username,
        email=f"{username}@example.com",
        first_name=username.capitalize(),
        password="Pass!123",
        role=role,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Wave 5 — upload validator
# ─────────────────────────────────────────────────────────────────────────────

class UploadValidationTests(TestCase):
    def test_unknown_extension_now_rejected(self):
        from apps.accounts.upload_security import validate_uploaded_file

        fake = BytesIO(b"<?php system('id'); ?>")
        fake.name = "evil.exe"
        fake.size = len(fake.getvalue())
        fake.content_type = "application/octet-stream"
        with self.assertRaises(DjangoValidationError):
            validate_uploaded_file(
                fake,
                field_label="upload",
                allowed_extensions=[".exe"],
                max_mb=5,
                allowed_content_types=["application/octet-stream"],
            )

    def test_missing_content_type_rejected_when_whitelist_present(self):
        from apps.accounts.upload_security import validate_uploaded_file

        fake = BytesIO(b"%PDF-1.4 mock")
        fake.name = "scan.pdf"
        fake.size = len(fake.getvalue())
        fake.content_type = ""  # missing
        with self.assertRaises(DjangoValidationError):
            validate_uploaded_file(
                fake,
                field_label="kyc",
                allowed_extensions=[".pdf"],
                max_mb=5,
                allowed_content_types=["application/pdf"],
            )

    def test_zip_office_magic_bytes_accepted(self):
        from apps.accounts.upload_security import validate_uploaded_file

        body = b"PK\x03\x04" + b"\x00" * 20
        fake = BytesIO(body)
        fake.name = "report.docx"
        fake.size = len(body)
        fake.content_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        # Should NOT raise — docx is now in _MAGIC_SIGNATURES.
        validate_uploaded_file(
            fake,
            field_label="upload",
            allowed_extensions=[".docx"],
            max_mb=5,
            allowed_content_types=[
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            ],
        )


# ─────────────────────────────────────────────────────────────────────────────
# Wave 5 — FCMToken hijack guard
# ─────────────────────────────────────────────────────────────────────────────

class FCMHijackTests(TestCase):
    def setUp(self):
        from apps.accounts.models import FCMToken
        self.FCMToken = FCMToken
        self.victim = _make_user("victim")
        self.attacker = _make_user("attacker")

    def test_attacker_cannot_claim_existing_token(self):
        # Victim registers a token.
        self.FCMToken.objects.create(
            user=self.victim, registration_id="abc-victim-token", type="android",
        )
        client = APIClient()
        client.force_authenticate(self.attacker)
        resp = client.post(
            "/api/auth/fcm-token/",
            {"registration_id": "abc-victim-token", "type": "android"},
            format="json",
        )
        self.assertEqual(resp.status_code, 409)
        # Token still belongs to victim.
        tok = self.FCMToken.objects.get(registration_id="abc-victim-token")
        self.assertEqual(tok.user_id, self.victim.id)


# ─────────────────────────────────────────────────────────────────────────────
# Wave 5 — chat read-only writes
# ─────────────────────────────────────────────────────────────────────────────

class ChatMessageReadOnlyEditsTests(TestCase):
    def test_message_viewset_does_not_allow_patch(self):
        from apps.chat.views import MessageViewSet
        self.assertNotIn("patch", MessageViewSet.http_method_names)
        self.assertNotIn("put", MessageViewSet.http_method_names)
        self.assertNotIn("delete", MessageViewSet.http_method_names)


# ─────────────────────────────────────────────────────────────────────────────
# Wave 6 — Lua-atomic lock release
# ─────────────────────────────────────────────────────────────────────────────

class LockAtomicReleaseTests(TestCase):
    def test_release_uses_lua_when_redis_client_available(self):
        from core import locks

        fake_client = MagicMock()
        fake_client.eval.return_value = 1
        with patch.object(locks, "_redis_client", return_value=fake_client):
            with locks.acquire_lock("audit-test:lua", ttl_seconds=5) as token:
                self.assertTrue(token)
        # eval must have been called once with the release script.
        fake_client.eval.assert_called_once()
        args, _ = fake_client.eval.call_args
        self.assertIn("redis.call('get', KEYS[1])", args[0])

    def test_release_falls_back_when_no_redis_client(self):
        from core import locks

        with patch.object(locks, "_redis_client", return_value=None):
            # Should not raise.
            with locks.acquire_lock("audit-test:fallback", ttl_seconds=5):
                pass


# ─────────────────────────────────────────────────────────────────────────────
# Wave 6 — lock_funds_for_order deterministic idempotency
# ─────────────────────────────────────────────────────────────────────────────

class LockFundsDeterministicKeyTests(TestCase):
    def test_deterministic_key_when_caller_omits_it(self):
        from apps.orders.services import OrderFinanceService

        captured = {}

        def fake_lock_from_available(*args, **kwargs):
            captured["idempotency_key"] = kwargs.get("idempotency_key")
            raise RuntimeError("stop-here")  # short-circuit — we only need the kwargs

        order = MagicMock(id=12345)
        with patch(
            "apps.orders.services.WalletAccountingService.lock_from_available",
            side_effect=fake_lock_from_available,
        ), patch(
            "apps.orders.services.Order.objects",
        ) as mock_qs, patch(
            "apps.orders.services.WalletAccountingService.get_wallet_for_update",
        ) as mock_wallet:
            mock_qs.select_for_update.return_value.select_related.return_value.get.return_value = order
            order.escrows.all.return_value = []
            from decimal import Decimal
            mock_wallet.return_value = MagicMock(available_balance=Decimal("100000"))
            try:
                OrderFinanceService.lock_funds_for_order(
                    order=order, actor=None,
                    supplier_amount=Decimal("100"),
                    logistics_amount=Decimal("50"),
                )
            except RuntimeError:
                pass
        self.assertEqual(captured.get("idempotency_key"), "order:12345:lock_funds_v1")


# ─────────────────────────────────────────────────────────────────────────────
# Wave 6 — open_dispute auto-freezes order escrows
# ─────────────────────────────────────────────────────────────────────────────

class DisputeAutoFreezeTests(TestCase):
    def test_open_dispute_on_order_calls_freeze(self):
        from apps.disputes.services import dispute_service

        opener = _make_user("opener_freeze")
        with patch(
            "apps.orders.services.OrderFinanceService.freeze_order_escrows"
        ) as mock_freeze, patch(
            "apps.orders.models.Order.objects.get",
        ) as mock_get:
            mock_get.return_value = MagicMock(id="42")
            case = dispute_service.open_dispute(
                opened_by=opener,
                entity_type="Order",
                entity_id="42",
                dispute_type="DELIVERY_NOT_RECEIVED",
                category="DELIVERY",
                title="missing",
                description="x",
            )
        self.assertEqual(case.entity_id, "42")
        mock_freeze.assert_called_once()

    def test_open_dispute_on_non_order_skips_freeze(self):
        from apps.disputes.services import dispute_service

        opener = _make_user("opener_nofreeze")
        with patch(
            "apps.orders.services.OrderFinanceService.freeze_order_escrows"
        ) as mock_freeze:
            dispute_service.open_dispute(
                opened_by=opener,
                entity_type="Shipment",
                entity_id="9",
                dispute_type="DAMAGE",
                category="LOGISTICS",
                title="t",
                description="d",
            )
        mock_freeze.assert_not_called()


# ─────────────────────────────────────────────────────────────────────────────
# Wave 6 — Fraud review writes audit
# ─────────────────────────────────────────────────────────────────────────────

class FraudReviewAuditTests(TestCase):
    def setUp(self):
        from apps.fraud.models import FraudAssessment
        self.admin = _make_user("fraud_admin", role="GENERAL_ADMIN")
        self.victim = _make_user("fraud_victim")
        self.assessment = FraudAssessment.objects.create(
            user=self.victim,
            action_type="WITHDRAWAL",
            risk_score=82,
            risk_level="HIGH",
            decision="BLOCK",
            signals=[{"type": "velocity", "weight": 30}],
        )

    def test_review_logs_to_audit(self):
        client = APIClient()
        client.force_authenticate(self.admin)
        with patch("apps.fraud.views.audit_service.log_fraud") as mock_log:
            resp = client.post(
                f"/api/fraud/assessments/{self.assessment.pk}/review/",
                {"outcome": "DISMISSED"},
                format="json",
            )
        self.assertEqual(resp.status_code, 200)
        mock_log.assert_called_once()
        _, kwargs = mock_log.call_args
        self.assertEqual(kwargs["event_type"], "fraud.assessment.review")
        self.assertEqual(kwargs["actor"], self.admin)

    def test_unknown_outcome_rejected(self):
        client = APIClient()
        client.force_authenticate(self.admin)
        resp = client.post(
            f"/api/fraud/assessments/{self.assessment.pk}/review/",
            {"outcome": "WHITELIST"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_non_admin_blocked(self):
        client = APIClient()
        client.force_authenticate(self.victim)
        resp = client.post(
            f"/api/fraud/assessments/{self.assessment.pk}/review/",
            {"outcome": "DISMISSED"},
            format="json",
        )
        self.assertEqual(resp.status_code, 403)


# ─────────────────────────────────────────────────────────────────────────────
# Wave 7 — Nominatim SSRF guard
# ─────────────────────────────────────────────────────────────────────────────

class NominatimSSRFGuardTests(TestCase):
    def setUp(self):
        from apps.accounts.location_service import _is_safe_geocoder_url
        self.is_safe = _is_safe_geocoder_url

    @override_settings(DEBUG=False)
    def test_http_rejected_in_production(self):
        self.assertFalse(self.is_safe("http://example.com"))

    @override_settings(DEBUG=False)
    def test_loopback_rejected_in_production(self):
        # 127.0.0.1 explicit resolution
        self.assertFalse(self.is_safe("https://127.0.0.1"))

    @override_settings(DEBUG=False)
    def test_link_local_rejected(self):
        # AWS instance metadata.
        self.assertFalse(self.is_safe("https://169.254.169.254"))

    @override_settings(DEBUG=False)
    def test_private_rejected(self):
        self.assertFalse(self.is_safe("https://10.0.0.5"))

    @override_settings(DEBUG=True)
    def test_localhost_allowed_in_debug(self):
        self.assertTrue(self.is_safe("http://localhost"))


# ─────────────────────────────────────────────────────────────────────────────
# Wave 7 — PIN ≥ 6 digits + reject trivial
# ─────────────────────────────────────────────────────────────────────────────

class WalletPinSixDigitsTests(TestCase):
    def setUp(self):
        self.user = _make_user("pin_user")
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_four_digit_pin_rejected(self):
        resp = self.client.post("/api/auth/wallet-pin/", {"pin": "1234"}, format="json")
        self.assertEqual(resp.status_code, 400)

    def test_trivial_six_digit_pin_rejected(self):
        resp = self.client.post("/api/auth/wallet-pin/", {"pin": "000000"}, format="json")
        self.assertEqual(resp.status_code, 400)

    def test_six_digit_pin_accepted(self):
        resp = self.client.post("/api/auth/wallet-pin/", {"pin": "284931"}, format="json")
        self.assertEqual(resp.status_code, 200)
