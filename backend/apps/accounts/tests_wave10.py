"""
Regression tests for Wave 10 — operational jobs + proxy trust alternatives.

  * migrate_wallet_pin clears legacy hashes and notifies users.
  * verify_audit_chain_integrity reports forks vs clean chains.
  * reconcile_wallet_ledger flags drift between wallet and ledger.
  * _client_ip honours CIDR / Cloudflare CF-Connecting-IP / PSK header /
    TRUST_PRIVATE_PROXIES — the four alternatives to listing exact LB IPs.
"""
from __future__ import annotations

from decimal import Decimal
from io import StringIO
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import RequestFactory, TestCase, override_settings

User = get_user_model()


# ─────────────────────────────────────────────────────────────────────────────
# migrate_wallet_pin
# ─────────────────────────────────────────────────────────────────────────────

class MigrateWalletPinTests(TestCase):
    def test_dry_run_does_not_modify(self):
        u = User.objects.create_user(
            username="pin1", email="p1@x", first_name="P", password="x",
        )
        u.set_wallet_pin("1234")
        u.save()
        buf = StringIO()
        call_command("migrate_wallet_pin", "--dry-run", stdout=buf)
        u.refresh_from_db()
        self.assertTrue(u.wallet_pin_hash)

    def test_execute_clears_hash(self):
        u = User.objects.create_user(
            username="pin2", email="p2@x", first_name="P", password="x",
        )
        u.set_wallet_pin("1234")
        u.save()
        call_command("migrate_wallet_pin", "--execute", stdout=StringIO())
        u.refresh_from_db()
        self.assertEqual(u.wallet_pin_hash, "")
        self.assertEqual(u.wallet_pin_failed_attempts, 0)


# ─────────────────────────────────────────────────────────────────────────────
# verify_audit_chain_integrity
# ─────────────────────────────────────────────────────────────────────────────

class VerifyAuditChainTests(TestCase):
    def test_clean_chain_reports_no_fork(self):
        from apps.audit.models import AuditEvent
        AuditEvent.objects.create(
            category="AUTH", event_type="x", entity_type="Test", entity_id="1",
            payload={"a": 1},
        )
        AuditEvent.objects.create(
            category="AUTH", event_type="y", entity_type="Test", entity_id="1",
            payload={"b": 2},
        )
        from apps.audit.tasks import verify_audit_chain_integrity
        summary = verify_audit_chain_integrity()
        self.assertEqual(summary["forks_detected"], 0)

    def test_tampered_event_is_detected(self):
        from apps.audit.models import AuditEvent
        AuditEvent.objects.create(
            category="AUTH", event_type="x", entity_type="Tamper", entity_id="1",
            payload={"a": 1},
        )
        # Corrupt the chain — direct UPDATE bypasses save().
        AuditEvent.objects.filter(entity_type="Tamper").update(
            chain_hash="deadbeef" * 8,
        )
        from apps.audit.tasks import verify_audit_chain_integrity
        summary = verify_audit_chain_integrity()
        self.assertGreaterEqual(summary["forks_detected"], 1)


# ─────────────────────────────────────────────────────────────────────────────
# reconcile_wallet_ledger
# ─────────────────────────────────────────────────────────────────────────────

class ReconcileWalletLedgerTests(TestCase):
    def test_empty_wallet_no_ledger_account_is_skipped(self):
        User.objects.create_user(
            username="recon0", email="r0@x", first_name="R", password="x",
        )
        # No wallet at all => no entry in the iteration => no drift.
        from apps.ledger.tasks import reconcile_wallet_ledger
        summary = reconcile_wallet_ledger()
        self.assertEqual(summary["drift_count"], 0)

    def test_wallet_without_ledger_entry_but_nonzero_is_flagged(self):
        from apps.wallets.services import WalletAccountingService

        u = User.objects.create_user(
            username="recon1", email="r1@x", first_name="R", password="x",
        )
        wallet = WalletAccountingService.get_wallet_for_update(user=u)
        # Force a non-zero available without going through the ledger mirror.
        wallet.available_balance = Decimal("50.00")
        wallet.save(update_fields=["available_balance"])

        # Create the ledger account, but no entries — that simulates the
        # "wallet has money but ledger empty" drift case.
        from apps.ledger.models import (
            AccountSubType, AccountType, LedgerAccount,
        )
        LedgerAccount.objects.create(
            sub_type=AccountSubType.USER_WALLET,
            owner=u,
            account_type=AccountType.ASSET,
            currency="XAF",
        )

        from apps.ledger.tasks import reconcile_wallet_ledger
        summary = reconcile_wallet_ledger()
        self.assertGreaterEqual(summary["missing_ledger_entry"], 1)
        self.assertGreaterEqual(summary["drift_count"], 1)


# ─────────────────────────────────────────────────────────────────────────────
# _client_ip — alternatives to exact-IP TRUSTED_PROXIES
# ─────────────────────────────────────────────────────────────────────────────

class ClientIpAlternativesTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()

    @override_settings(TRUSTED_PROXIES=["10.0.0.0/8"])
    def test_cidr_range_trusts_xff(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/", HTTP_X_FORWARDED_FOR="8.8.8.8", REMOTE_ADDR="10.42.7.5",
        )
        self.assertEqual(_client_ip(req), "8.8.8.8")

    @override_settings(TRUSTED_PROXIES=["10.0.0.0/8"])
    def test_cloudflare_header_preferred_when_present(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/",
            HTTP_CF_CONNECTING_IP="8.8.4.4",
            HTTP_X_FORWARDED_FOR="9.9.9.9, 10.0.0.1",
            REMOTE_ADDR="10.0.0.1",
        )
        self.assertEqual(_client_ip(req), "8.8.4.4")

    @override_settings(TRUSTED_PROXIES=[], TRUST_PRIVATE_PROXIES=True)
    def test_private_network_auto_trust(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/", HTTP_X_FORWARDED_FOR="8.8.8.8", REMOTE_ADDR="172.16.0.5",
        )
        self.assertEqual(_client_ip(req), "8.8.8.8")

    @override_settings(TRUSTED_PROXIES=[], TRUST_PRIVATE_PROXIES=False)
    def test_private_network_NOT_trusted_when_flag_off(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/", HTTP_X_FORWARDED_FOR="8.8.8.8", REMOTE_ADDR="172.16.0.5",
        )
        # Without the opt-in, even a private REMOTE_ADDR is not auto-trusted.
        self.assertEqual(_client_ip(req), "172.16.0.5")

    @override_settings(
        TRUSTED_PROXIES=[],
        TRUST_PRIVATE_PROXIES=False,
        TRUSTED_PROXY_SECRET="psk-abc",
    )
    def test_psk_header_grants_trust_on_any_remote(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/",
            HTTP_X_FORWARDED_FOR="8.8.8.8",
            HTTP_X_INTERNAL_PROXY_SECRET="psk-abc",
            REMOTE_ADDR="203.0.113.42",  # arbitrary public IP
        )
        self.assertEqual(_client_ip(req), "8.8.8.8")

    @override_settings(
        TRUSTED_PROXIES=[],
        TRUST_PRIVATE_PROXIES=False,
        TRUSTED_PROXY_SECRET="psk-abc",
    )
    def test_psk_mismatch_falls_back_to_remote(self):
        from config.middleware import _client_ip
        req = self.factory.get(
            "/",
            HTTP_X_FORWARDED_FOR="8.8.8.8",
            HTTP_X_INTERNAL_PROXY_SECRET="wrong-secret",
            REMOTE_ADDR="203.0.113.42",
        )
        self.assertEqual(_client_ip(req), "203.0.113.42")
