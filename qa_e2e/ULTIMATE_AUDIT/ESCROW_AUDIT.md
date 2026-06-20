# ESCROW_AUDIT.md — Phase 8 (Zero-Trust fintech)

> Méthode : exécution réelle des invariants comptables + lecture du moteur ledger.
> Date : 2026-06-18. Modèle : marketplace intermédiaire à séquestre (Acheteur → Escrow → Vendeur).

## Architecture prouvée
- **Double-entrée** : `apps/ledger/` — `LedgerTransaction` (entête) + `LedgerEntry` (lignes débit/crédit).
  Le service `apps/ledger/services.py:152-156` **valide `total_debits == total_credits` et lève**
  `Ledger imbalance: debits=… != credits=…` sinon → écriture déséquilibrée **impossible**.
- Comptes : ASSET (wallet/escrow holds), LIABILITY (dû provider), REVENUE (commission), EXPENSE.
- Postings dédiés : `post_topup`, `post_withdrawal`, `post_escrow_lock`, `post_escrow_release`,
  `post_escrow_refund`, `post_dispute_freeze`.
- Verrouillage fonds : `OrderFinanceService.lock_funds_for_order` (escrow par commande).

## Preuves d'exécution
### `apps.ledger.test_invariants_audit` — `Ran 4 tests … OK`
| Test | Résultat | Invariant prouvé |
|---|---|---|
| `test_balance_conservation_after_full_cycle` | **ok** | **Aucun argent créé ni perdu** sur un cycle complet (topup→lock→release) |
| `test_each_transaction_balances` | **ok** | **Σ débits = Σ crédits** pour CHAQUE transaction |
| `test_idempotent_topup_no_double_credit` | **ok** | Rejeu topup → pas de double crédit |
| `test_unbalanced_write_rejected` | **ok** | Écriture déséquilibrée **refusée** par le moteur |

### `apps.accounts.tests_e2e_payment` (dans les 349) — chemin de l'argent
| Test | Résultat | Preuve |
|---|---|---|
| `test_valid_webhook_credits_wallet` | **ok** | webhook signé crédite **exactement** +10 000 XAF |
| `test_replay_does_not_double_credit` | **ok** | rejeu webhook → solde inchangé (idempotent) |
| `test_bad_signature_refused` | **ok** | signature invalide → **403** |
| `test_lock_funds_debits_available_and_locks` | **ok** | 20 000 → available 17 000 + locked 3 000 + escrow créé (atomique) |

### Refund / concurrence (orders) — exécutés
| Test | Résultat |
|---|---|
| `apps.orders.test_buyer_cancel_refund_atomicity` | **ok** (refund atomique) |
| `apps.orders.test_buyer_cancel_concurrent_requests` | **ok** (annulations concurrentes maîtrisées) |

## Interdiction Acheteur → Vendeur (direct)
- Les fonds transitent par `lock_funds_for_order` (escrow), pas de crédit vendeur direct ;
  release/refund passent par `post_escrow_release`/`post_escrow_refund` (postings équilibrés). **PASS**.

## Findings
- **E-1 (MOYEN) — Double-entrée pilotée par flag.** `tests_e2e_payment` tourne avec
  `LEDGER_DOUBLE_ENTRY_ENABLED=False`. L'invariant n'est prouvé **que** par
  `test_invariants_audit` (flag ON). *Reco* : confirmer en prod (SSM) que `LEDGER_DOUBLE_ENTRY_ENABLED=True`,
  sinon les écritures comptables ne sont pas postées (risque de réconciliation non garantie).
  **À VÉRIFIER PROD** (pas de creds ici → NOT VERIFIED côté env déployé).
- **E-2 (BAS) — Pas de test de paiement concurrent sur le MÊME escrow** (deux releases parallèles).
  Couvert indirectement par les locks `select_for_update` mais pas par un test dédié.

## Statut Phase 8
**PASS (logique escrow + invariants comptables prouvés par exécution)**.
Réserve : état du flag double-entrée **en prod** = NOT VERIFIED (finding E-1).
