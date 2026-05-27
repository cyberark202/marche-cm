"""
Regression tests for Wave 3 (CRITICAL fintech remediation):
  * [FIN-001] WalletAccountingService.mutate_wallet mirrors every entry to
    the double-entry LedgerService.
  * [FIN-002] Wallet.save() no longer "infers" modern balances from legacy
    fields — legacy fields are strictly derived from modern ones.
  * [FIN-002] Database constraints reject inconsistent balance rows.
"""
from __future__ import annotations

from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase, override_settings

from apps.wallets.models import (
    LedgerDirection,
    LedgerEntryType,
    Wallet,
)
from apps.wallets.services import (
    InsufficientFundsError,
    WalletAccountingService,
    quantize_money,
)

User = get_user_model()


def _make_user(username: str = "u1") -> User:
    return User.objects.create_user(
        username=username,
        email=f"{username}@example.com",
        first_name=username.capitalize(),
        password="Pass!123",
    )


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-002] Wallet.save() no longer corrupts modern balances.
# ─────────────────────────────────────────────────────────────────────────────

class WalletSaveNoLegacyCorruptionTests(TestCase):
    def test_legacy_assignment_does_not_overwrite_modern_fields(self):
        user = _make_user("legacy_user")
        wallet = WalletAccountingService.get_wallet_for_update(user=user)
        # Seed the modern fields directly (simulates a real mutation result).
        wallet.available_balance = Decimal("200000.00")
        wallet.locked_balance = Decimal("50000.00")
        wallet.pending_balance = Decimal("100000.00")
        wallet.save()

        # An admin script tries the dangerous legacy assignment pattern.
        wallet.balance = Decimal("0.00")
        wallet.blocked_balance = Decimal("0.00")
        wallet.save()
        wallet.refresh_from_db()

        # Modern fields must survive untouched; legacy must be re-derived.
        self.assertEqual(wallet.available_balance, Decimal("200000.00"))
        self.assertEqual(wallet.locked_balance, Decimal("50000.00"))
        self.assertEqual(wallet.pending_balance, Decimal("100000.00"))
        self.assertEqual(wallet.balance, Decimal("350000.00"))
        self.assertEqual(wallet.blocked_balance, Decimal("50000.00"))

    def test_partial_save_keeps_legacy_in_sync(self):
        user = _make_user("partial_user")
        wallet = WalletAccountingService.get_wallet_for_update(user=user)
        wallet.available_balance = Decimal("1000.00")
        wallet.save(update_fields=["available_balance"])
        wallet.refresh_from_db()
        # The mirror must follow even on partial saves.
        self.assertEqual(wallet.balance, Decimal("1000.00"))
        self.assertEqual(wallet.blocked_balance, Decimal("0.00"))


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-002] DB-level CheckConstraint rejects inconsistent rows.
# ─────────────────────────────────────────────────────────────────────────────

class WalletBalanceInvariantConstraintTests(TestCase):
    def test_constraint_blocks_drift_between_balance_and_components(self):
        user = _make_user("drift_user")
        wallet = WalletAccountingService.get_wallet_for_update(user=user)
        wallet.available_balance = Decimal("100.00")
        wallet.save()
        # Bypass save() to simulate a raw SQL drift attempt.
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Wallet.objects.filter(pk=wallet.pk).update(balance=Decimal("999.00"))


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-001] mutate_wallet mirrors to the double-entry ledger.
# ─────────────────────────────────────────────────────────────────────────────

class LedgerMirrorTests(TestCase):
    def setUp(self):
        self.user = _make_user("ledger_user")
        self.peer = _make_user("ledger_peer")

    def _wallet(self, user):
        return WalletAccountingService.get_wallet_for_update(user=user)

    def test_deposit_posts_topup(self):
        with patch("apps.ledger.services.ledger_service.post_topup") as mock_topup:
            mock_topup.return_value = "mock-tx"
            wallet = self._wallet(self.user)
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet,
                    amount=Decimal("500.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    reference="topup-ref",
                    idempotency_key="idem-topup-1",
                )
            mock_topup.assert_called_once()
            _, kwargs = mock_topup.call_args
            self.assertEqual(kwargs["user"], self.user)
            self.assertEqual(quantize_money(kwargs["amount"]), Decimal("500.00"))
            # Audit ref: [FIN-001-bis] idempotency_key is scoped by user+entry_type
            # to avoid cross-tenant collisions on the global ledger constraint.
            self.assertEqual(
                kwargs["idempotency_key"],
                f"wle:{self.user.id}:DEPOSIT:idem-topup-1",
            )

    def test_withdrawal_posts_withdrawal(self):
        with patch("apps.ledger.services.ledger_service.post_topup"), \
             patch("apps.ledger.services.ledger_service.post_withdrawal") as mock_w:
            mock_w.return_value = "mock-tx"
            wallet = self._wallet(self.user)
            # Pre-fund (mirrored to topup mock above).
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet, amount=Decimal("100.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="seed-1",
                )
            with transaction.atomic():
                WalletAccountingService.debit_available(
                    wallet=wallet, amount=Decimal("40.00"),
                    entry_type=LedgerEntryType.WITHDRAWAL,
                    reference="w-1", idempotency_key="idem-w-1",
                )
            mock_w.assert_called_once()
            _, kwargs = mock_w.call_args
            self.assertEqual(quantize_money(kwargs["amount"]), Decimal("40.00"))

    def test_escrow_lock_with_counterparty_posts_escrow_lock(self):
        with patch("apps.ledger.services.ledger_service.post_topup"), \
             patch("apps.ledger.services.ledger_service.post_escrow_lock") as mock_lock:
            mock_lock.return_value = "mock-tx"
            wallet = self._wallet(self.user)
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet, amount=Decimal("1000.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="seed-2",
                )
            with transaction.atomic():
                WalletAccountingService.lock_from_available(
                    wallet=wallet, amount=Decimal("250.00"),
                    reference="order-7",
                    counterparty=self.peer,
                    idempotency_key="idem-lock-1",
                )
            mock_lock.assert_called_once()
            _, kwargs = mock_lock.call_args
            self.assertEqual(kwargs["buyer"], self.user)
            self.assertEqual(kwargs["seller"], self.peer)
            self.assertEqual(quantize_money(kwargs["amount"]), Decimal("250.00"))

    def test_ledger_mirror_rolls_back_wallet_on_failure(self):
        # A ledger error inside the atomic block must rollback the wallet
        # mutation — no orphan wallet write without a matching ledger entry.
        wallet = self._wallet(self.user)
        initial = wallet.available_balance
        with patch(
            "apps.ledger.services.ledger_service.post_topup",
            side_effect=RuntimeError("ledger down"),
        ):
            with self.assertRaises(RuntimeError):
                with transaction.atomic():
                    WalletAccountingService.credit_available(
                        wallet=wallet, amount=Decimal("999.00"),
                        entry_type=LedgerEntryType.DEPOSIT,
                        idempotency_key="rollback-test",
                    )
        wallet.refresh_from_db()
        self.assertEqual(wallet.available_balance, initial)

    @override_settings(LEDGER_DOUBLE_ENTRY_ENABLED=False)
    def test_feature_flag_disables_mirror(self):
        with patch("apps.ledger.services.ledger_service.post_topup") as mock_topup:
            wallet = self._wallet(self.user)
            with transaction.atomic():
                WalletAccountingService.credit_available(
                    wallet=wallet, amount=Decimal("10.00"),
                    entry_type=LedgerEntryType.DEPOSIT,
                    idempotency_key="ff-1",
                )
            mock_topup.assert_not_called()
