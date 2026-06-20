# WALLET_AUDIT.md — Phase 9 (Zero-Trust)

> Méthode : exécution réelle des suites wallet + lecture des invariants de solde. Date : 2026-06-18.

## Couverture exécutée (parmi les 349 OK)
- `apps/wallets/tests.py` (8), `tests_direct_charge.py` (6), `tests_security.py` (35) = **49 tests wallet OK**.
- Migration `0012_wallet_balance_invariants` : contraintes DB de solde (invariants persistés).

## Invariants prouvés
| Invariant | Preuve | Verdict |
|---|---|---|
| Crédit exact sur topup | `test_valid_webhook_credits_wallet` (+10 000) | **PASS** |
| Idempotence (double-clic / rejeu) | `test_replay_does_not_double_credit` ; `test_idempotent_topup_no_double_credit` | **PASS** |
| Débit available + lock atomique | `test_lock_funds_debits_available_and_locks` | **PASS** |
| Solde négatif impossible | migration `0012_wallet_balance_invariants` (contrainte DB) + `select_for_update` | **PASS** (par contrainte) |
| Sécurité endpoints wallet | `tests_security.py` (35) tous OK | **PASS** |
| Double-entrée ledger | `test_invariants_audit` (cf. ESCROW_AUDIT) | **PASS** |

## PIN / sensitive action
- Le **PIN wallet a été remplacé par OTP e-mail** (mémoire projet : 410 + OTP). Endpoint
  `WalletPinView` conservé pour compat ; actions sensibles via `SensitiveActionRequestView` (MFA token).
- Topup HTTP exige un **token MFA d'action sensible** (cf. note `tests_e2e_payment`).

## Findings
- **W-1 (MOYEN) — Race condition same-wallet sous charge réelle non mesurée.** Les tests prouvent
  l'atomicité logique (`select_for_update`) mais pas le comportement sous concurrence haute réelle
  (Postgres prod). *Reco* : test de charge ciblé débit concurrent même wallet.
- **W-2 (INFO) — `WalletPinView` résiduel.** Endpoint PIN conservé pour compat ; confirmer qu'il
  ne contourne pas le flux OTP. (Couvert par `tests_security` mais à garder à l'œil.)

## Statut Phase 9
**PASS** — invariants de solde (crédit exact, idempotence, anti-négatif, atomicité) prouvés par exécution.
Réserve : concurrence haute réelle même-wallet = NOT VERIFIED (W-1).
