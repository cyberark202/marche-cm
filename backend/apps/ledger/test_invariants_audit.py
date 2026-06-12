"""
Audit fintech 2026-06-12 — preuves d'intégrité comptable du grand livre.

Exécute des transactions réelles via LedgerService et prouve :
  1. Conservation : SUM(débits) == SUM(crédits) pour CHAQUE transaction.
  2. Équilibre global : SUM(tous les débits) == SUM(tous les crédits).
  3. Idempotence : même clé → une seule transaction (pas de double-débit).
  4. Refus d'écriture déséquilibrée.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.ledger.models import EntryDirection, LedgerEntry, LedgerTransaction
from apps.ledger.services import ledger_service

User = get_user_model()


class LedgerInvariantAuditTests(TestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(username="audit_buyer", password="x")
        self.seller = User.objects.create_user(username="audit_seller", password="x")

    def _assert_global_balance(self):
        debits = sum(
            e.amount for e in LedgerEntry.objects.filter(direction=EntryDirection.DEBIT)
        )
        credits = sum(
            e.amount for e in LedgerEntry.objects.filter(direction=EntryDirection.CREDIT)
        )
        self.assertEqual(debits, credits, "déséquilibre global débits/crédits")

    def test_each_transaction_balances(self):
        ledger_service.post_topup(self.buyer, Decimal("10000.00"), "audit-topup-1")
        ledger_service.post_escrow_lock(self.buyer, self.seller, Decimal("4000.00"), "audit-lock-1")
        ledger_service.post_escrow_release(self.seller, Decimal("3600.00"), Decimal("400.00"), "audit-rel-1")
        for tx in LedgerTransaction.objects.all():
            d = sum(e.amount for e in tx.entries.filter(direction=EntryDirection.DEBIT))
            c = sum(e.amount for e in tx.entries.filter(direction=EntryDirection.CREDIT))
            self.assertEqual(d, c, f"transaction {tx.transaction_type} déséquilibrée")
        self._assert_global_balance()

    def test_idempotent_topup_no_double_credit(self):
        ledger_service.post_topup(self.buyer, Decimal("5000.00"), "audit-idem-1")
        before = LedgerTransaction.objects.count()
        # Rejouer la même clé ne doit PAS créer de seconde transaction.
        with self.assertRaises(Exception):
            ledger_service.post_topup(self.buyer, Decimal("5000.00"), "audit-idem-1")
        self.assertEqual(LedgerTransaction.objects.count(), before)
        self._assert_global_balance()

    def test_unbalanced_write_rejected(self):
        acct = ledger_service.get_or_create_user_wallet_account(self.buyer)
        with self.assertRaises(ValueError):
            ledger_service._post_entries(
                transaction_type="ADJUSTMENT",
                idempotency_key="audit-bad-1",
                total_amount=Decimal("100.00"),
                entries=[
                    {"account": acct, "direction": EntryDirection.DEBIT,
                     "amount": Decimal("100.00"), "description": "x"},
                    # crédit manquant → déséquilibre
                ],
            )

    def test_balance_conservation_after_full_cycle(self):
        ledger_service.post_topup(self.buyer, Decimal("8000.00"), "audit-cyc-topup")
        ledger_service.post_escrow_lock(self.buyer, self.seller, Decimal("8000.00"), "audit-cyc-lock")
        ledger_service.post_escrow_refund(self.buyer, self.seller, Decimal("8000.00"), "audit-cyc-refund")
        wallet = ledger_service.get_or_create_user_wallet_account(self.buyer)
        # Topup +8000, lock -8000, refund +8000 → 8000 net disponible.
        self.assertEqual(ledger_service.get_account_balance(wallet), Decimal("8000.00"))
        self._assert_global_balance()
