# FINTECH_AUDIT.md — Audit fintech MarketCM
**Date :** 2026-06-12 · **Preuves exécutées :** `apps.ledger.test_invariants_audit` **4/4 OK** (écrites pour cet audit), suite wallet/escrow/orders/ledger **63/63 OK**, suite complète **319/319 OK**.

## 1. Architecture monétaire (vérifiée par lecture + tests)
Deux registres tenus en cohérence atomique :
- **Registre opérationnel** : `Wallet` à 3 soldes (`available` / `locked` / `pending`) + `WalletLedgerEntry` (mouvements, before/after par solde).
- **Grand livre comptable double entrée** : `LedgerAccount` (plan de comptes), `LedgerTransaction` (entête + clé d'idempotence globale), `LedgerEntry` (lignes DÉBIT/CRÉDIT immuables, `running_balance`).

Tout mouvement wallet est **mirroré** dans le grand livre dans le **même `transaction.atomic()`** (`_mirror_wallet_entry_to_ledger`) : si le miroir échoue, la mutation wallet est annulée → les deux registres ne divergent jamais. Replay-safe (`_ensure_ledger_mirror_present`) sur les chemins rejoués.

## 2. Invariants prouvés par exécution

| Invariant | Test | Résultat |
|---|---|---|
| Conservation par transaction : Σ débits == Σ crédits | `test_each_transaction_balances` | ✅ OK |
| Équilibre comptable global Σ débits == Σ crédits | `_assert_global_balance` (toutes) | ✅ OK |
| Double entrée refusée si déséquilibrée | `test_unbalanced_write_rejected` (lève `ValueError`) | ✅ OK |
| Idempotence — pas de double-crédit au rejeu | `test_idempotent_topup_no_double_credit` | ✅ OK |
| Conservation après cycle topup→lock→refund | `test_balance_conservation_after_full_cycle` (solde net exact) | ✅ OK |

`_post_entries` valide `total_debits == total_credits` **avant** d'écrire, sous `select_for_update` sur tous les comptes impliqués → atomicité + sérialisation.

## 3. Risques fintech examinés

| Risque | Protection vérifiée | Verdict |
|---|---|---|
| Double débit / double crédit | clé d'idempotence unique (wallet + ledger) ; rejeu retourne l'entrée existante | ✅ |
| Solde négatif | `_apply_deltas` lève `InsufficientFundsError` si `available < 0` ; `locked/pending < 0` → `FinancialInvariantError` | ✅ |
| Transaction fantôme | `LedgerEntry` immuable, jamais supprimée ; `on_delete=PROTECT` | ✅ |
| Désynchronisation wallet↔ledger | miroir dans le même atomic + tâche `reconcile_wallet_ledger` (horaire, désormais **active** après correctif INFRA-P0-001) | ✅ |
| Double libération escrow | garde `status == RELEASED` idempotente + `FROZEN` rejeté + verrous | ✅ |
| Double remboursement | clé d'idempotence sur `post_escrow_refund` | ✅ |
| Réutilisation/force PIN | PBKDF2 (`make_password`), compteur d'échecs + `locked_until` | ✅ |
| Race conditions retrait/paiement | `select_for_update` sur wallet avant toute mutation | ✅ |
| Réconciliation provider | `run_daily_reconciliation` (NotchPay float) — tâche **désormais active** | ✅ |

## 4. Commission plateforme
Vérifiée dans `OrderFinanceService` : `commission = amount * rate`, `net_supplier = amount - commission`, rejet si net < 0 ; commission débitée séparément et tracée (`metadata.rate`). Côté grand livre, `post_escrow_release` ventile escrow → wallet vendeur + revenu plateforme en transaction équilibrée. ✅

## 5. Points de vigilance (signalés)
- ℹ️ Le grand livre double entrée est alimenté **uniquement** par le miroir wallet ; certains `entry_type` (commission interne, transferts) n'ont pas encore de mapping double-entrée et retournent `None` (loggé `ledger_mirror_skip`). La tâche de réconciliation horaire est censée les détecter — **désormais réellement exécutée** (avant ce jour, elle ne tournait pas). À surveiller sur les premières 24 h.
- ❌ NON VÉRIFIÉ en argent réel : flux NotchPay LIVE complet (dépôt USSD → webhook → crédit). Couvert par tests unitaires de signature/idempotence webhook, pas par une transaction réelle dans cette phase.
