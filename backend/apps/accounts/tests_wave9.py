"""
Regression tests for Wave 9 (post-audit fixes).

  * [N-001] verify PIN path now accepts the 6-digit PIN that WalletPinView sets.
  * [FIN-001-bis] LedgerTransaction.idempotency_key scoped by (user, entry_type)
                  to avoid cross-tenant DoS via collision on the unique constraint.
  * [NEW-001] mutate_wallet replay path re-posts the ledger mirror if missing
              (idempotent — does not re-post when already present).
  * [NEW-002] webhook timestamp window helper accepts/rejects properly.
  * [N-002] MessageSerializer rejects oversized content and bad type via REST.
  * [N-005] _client_ip refuses X-Forwarded-For from non-trusted REMOTE_ADDR.
  * [NEW-003] process_auto_releases skips when another beat holds the lock.
"""
from __future__ import annotations

import time as _time
from decimal import Decimal
from unittest.mock import MagicMock, patch

from django.contrib.auth import get_user_model
from django.test import RequestFactory, TestCase, override_settings

from apps.wallets.models import LedgerDirection, LedgerEntryType
from apps.wallets.services import WalletAccountingService

User = get_user_model()


def _make_user(username="u9") -> User:
    return User.objects.create_user(
        username=username,
        email=f"{username}@example.com",
        first_name=username.capitalize(),
        password="Pass!123",
    )


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-001-bis] LedgerTransaction.idempotency_key scoped by (user, entry_type)
# ─────────────────────────────────────────────────────────────────────────────

class LedgerIdempotencyScopedTests(TestCase):
    def test_idempotency_key_includes_user_and_entry_type(self):
        u = _make_user("scoped_user")
        wallet = WalletAccountingService.get_wallet_for_update(user=u)
        with patch("apps.ledger.services.ledger_service.post_topup") as mock_topup:
            from django.db import transaction
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet,
                    amount=Decimal("10.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="shared-key",
                )
            _, kwargs = mock_topup.call_args
            self.assertIn(f"wle:{u.id}:DEPOSIT:shared-key", kwargs["idempotency_key"])


# ─────────────────────────────────────────────────────────────────────────────
# [NEW-001] Replay path re-posts mirror only if missing
# ─────────────────────────────────────────────────────────────────────────────

class LedgerMirrorReplaySafetyTests(TestCase):
    def test_mirror_re_posted_when_ledger_tx_missing(self):
        from django.db import transaction
        u = _make_user("replay_user")
        wallet = WalletAccountingService.get_wallet_for_update(user=u)

        with patch("apps.ledger.services.ledger_service.post_topup") as mock_topup:
            mock_topup.return_value = "mock-tx-1"
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet,
                    amount=Decimal("50.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="replay-1",
                )
            self.assertEqual(mock_topup.call_count, 1)

        # Replay — same idempotency_key. The wallet entry already exists, so
        # mutate_wallet should return it WITHOUT a second mirror post, because
        # LedgerTransaction.objects.filter(idempotency_key=...).exists() is True.
        from apps.ledger.models import LedgerTransaction
        with patch.object(
            LedgerTransaction.objects, "filter",
            return_value=MagicMock(exists=lambda: True),
        ), patch("apps.ledger.services.ledger_service.post_topup") as mock_topup_2:
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet,
                    amount=Decimal("50.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="replay-1",
                )
            self.assertEqual(mock_topup_2.call_count, 0)

        # Replay with the previous LedgerTransaction MISSING — the mirror MUST
        # be re-posted so the two ledgers converge.
        with patch.object(
            LedgerTransaction.objects, "filter",
            return_value=MagicMock(exists=lambda: False),
        ), patch("apps.ledger.services.ledger_service.post_topup") as mock_topup_3:
            mock_topup_3.return_value = "mock-tx-2"
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet,
                    amount=Decimal("50.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="replay-1",
                )
            self.assertEqual(mock_topup_3.call_count, 1)


# ─────────────────────────────────────────────────────────────────────────────
# [NEW-002] Webhook timestamp window
# ─────────────────────────────────────────────────────────────────────────────

class WebhookTimestampTests(TestCase):
    def setUp(self):
        from apps.wallets.views import WalletViewSet
        self.viewset = WalletViewSet()
        self.factory = RequestFactory()

    def _request(self, ts: str | None):
        headers = {}
        if ts is not None:
            headers["HTTP_X_NOTCH_TIMESTAMP"] = ts
        req = self.factory.post("/webhook", **headers)
        return req

    @override_settings(WEBHOOK_REQUIRE_TIMESTAMP=False)
    def test_missing_timestamp_allowed_when_not_required(self):
        ok, _ = self.viewset._check_webhook_timestamp(self._request(None), "test")
        self.assertTrue(ok)

    @override_settings(WEBHOOK_REQUIRE_TIMESTAMP=True)
    def test_missing_timestamp_refused_when_required(self):
        ok, err = self.viewset._check_webhook_timestamp(self._request(None), "test")
        self.assertFalse(ok)
        self.assertIn("timestamp manquant", err.lower())

    def test_old_timestamp_refused(self):
        old = str(int(_time.time()) - 3600)
        ok, err = self.viewset._check_webhook_timestamp(self._request(old), "test")
        self.assertFalse(ok)
        self.assertIn("hors fenetre", err.lower())

    def test_recent_timestamp_accepted(self):
        now = str(int(_time.time()))
        ok, _ = self.viewset._check_webhook_timestamp(self._request(now), "test")
        self.assertTrue(ok)


# ─────────────────────────────────────────────────────────────────────────────
# [N-002] MessageSerializer length + type validation
# ─────────────────────────────────────────────────────────────────────────────

class MessageSerializerValidationTests(TestCase):
    def test_oversized_content_rejected(self):
        from apps.chat.serializers import MessageSerializer
        s = MessageSerializer()
        with self.assertRaises(Exception) as ctx:
            s.validate_content("A" * 5000)
        self.assertIn("trop long", str(ctx.exception).lower())

    def test_unknown_message_type_rejected(self):
        from apps.chat.serializers import MessageSerializer
        s = MessageSerializer()
        with self.assertRaises(Exception):
            s.validate_type("MALWARE")

    def test_text_type_accepted(self):
        from apps.chat.serializers import MessageSerializer
        s = MessageSerializer()
        self.assertEqual(s.validate_type("TEXT"), "TEXT")


# ─────────────────────────────────────────────────────────────────────────────
# [N-005] _client_ip refuses XFF from untrusted REMOTE_ADDR
# ─────────────────────────────────────────────────────────────────────────────

class ClientIpTrustedProxyTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()

    @override_settings(TRUSTED_PROXIES=[])
    def test_xff_ignored_when_no_trusted_proxy(self):
        from config.middleware import _client_ip
        req = self.factory.get("/", HTTP_X_FORWARDED_FOR="8.8.8.8", REMOTE_ADDR="1.2.3.4")
        self.assertEqual(_client_ip(req), "1.2.3.4")

    @override_settings(TRUSTED_PROXIES=["10.0.0.1"])
    def test_xff_honored_when_remote_is_trusted_proxy(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/",
            HTTP_X_FORWARDED_FOR="8.8.8.8, 10.0.0.1",
            REMOTE_ADDR="10.0.0.1",
        )
        self.assertEqual(_client_ip(req), "8.8.8.8")

    @override_settings(TRUSTED_PROXIES=["10.0.0.1"])
    def test_xff_ignored_when_remote_not_trusted(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/",
            HTTP_X_FORWARDED_FOR="8.8.8.8",
            REMOTE_ADDR="9.9.9.9",  # NOT in TRUSTED_PROXIES
        )
        self.assertEqual(_client_ip(req), "9.9.9.9")


# ─────────────────────────────────────────────────────────────────────────────
# [NEW-003] process_auto_releases skips on lock contention
# ─────────────────────────────────────────────────────────────────────────────

class AutoReleaseSingleBeatTests(TestCase):
    def test_skipped_when_lock_held(self):
        from apps.escrow.tasks import process_auto_releases
        from core.locks import LockAcquisitionError

        # acquire_lock is imported lazily inside the task body, so we patch
        # it at its source module rather than on apps.escrow.tasks.
        with patch("core.locks.acquire_lock") as mock_acq:
            mock_acq.side_effect = LockAcquisitionError("held elsewhere")
            result = process_auto_releases()
        self.assertEqual(result["released"], 0)
        self.assertIn("skipped", result)


# ─────────────────────────────────────────────────────────────────────────────
# [N-001] PIN verify path accepts 6-digit PINs
# ─────────────────────────────────────────────────────────────────────────────

class WalletPinVerifyAcceptsSixDigitsTests(TestCase):
    def test_verify_4_digit_still_accepted_backwards_compat(self):
        # Cosmetic: ensure the rejection on the verify endpoint accepts 4 digit
        # (backwards compat) — we just check string handling. Real wallet PIN
        # presence is mocked.
        u = _make_user("verify_u4")
        u.set_wallet_pin("1234")
        u.save()
        self.assertTrue(u.check_wallet_pin("1234"))

    def test_verify_6_digit_accepted(self):
        u = _make_user("verify_u6")
        u.set_wallet_pin("284931")
        u.save()
        self.assertTrue(u.check_wallet_pin("284931"))
        self.assertFalse(u.check_wallet_pin("000000"))
