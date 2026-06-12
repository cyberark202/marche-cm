# BUSINESS_LOGIC_AUDIT.md — Audit logique métier MarketCM
**Date :** 2026-06-12 · **Preuves :** suite Django **319 tests / OK** (exécutée localement, 916 s), sous-ensemble fintech **63 tests / OK** (129 s) ré-exécuté après correctifs, + sondes live sur la prod.

## 1. Méthode
Lecture du code des services (`apps/*/services.py`), exécution de la suite de tests automatisée complète, et sondes HTTP réelles contre `https://cm.digital-get.com`. Les fonctionnalités non couvertes par un test exécuté ni une sonde sont marquées ❌ NON VÉRIFIÉ.

## 2. Authentification & comptes
| Fonction | Vérification | Verdict |
|---|---|---|
| Login OTP (email) | sonde live : `/api/auth/login/` valide le payload (400 sur corps vide) | ✅ |
| Rate-limit anti-bruteforce | 15 tentatives → **429 dès la 5e** (live) | ✅ |
| JWT RS256 + refresh | tests accounts (wave1-10) verts ; `/api/auth/refresh/` routé | ✅ |
| Endpoints protégés | wallets/orders/users/ledger/escrow/kyc/audit/admin → **401 anonyme** (live) | ✅ |
| Isolation des rôles | endpoints `/register/seller/` et `/register/driver/` séparés (serveur) ; tests `project_role_isolation` | ✅ |
| Suspension / réactivation | `test_user_suspension.py`, migration accounts/0016 | ✅ |
| KYC acheteur | `/api/auth/kyc/submit/`, types de docs unifiés (`kyc_constants`) | ✅ |
| PIN wallet | `make_password`/`check_password` (PBKDF2), `failed_attempts` + `locked_until` (verrouillage) | ✅ |

## 3. Catalogue & commandes
| Fonction | Vérification | Verdict |
|---|---|---|
| Publication produit (contrat) | `test_supplier_product_contract.py` (5), shim legacy clés | ✅ |
| `is_active` contrôlé serveur | `test_multipart_product_activation.py` (4) — non manipulable par payload | ✅ |
| Visibilité après upload | `test_product_visibility_after_upload.py` | ✅ |
| Recherche publique | sonde live `/api/products/?search=...` → 200, ORM paramétré (pas d'injection) | ✅ |
| **Annulation atomique** | `test_buyer_cancel_refund_atomicity.py` (7) + `_concurrent_requests.py` (1) : remboursement escrow **et** statut dans un seul `atomic()`, rollback sur échec, double-annulation rejetée | ✅ |

## 4. Escrow & libération des fonds
- Machine d'états escrow (`apps/escrow/state_machine.py`) + lifecycle (LOCKED/RELEASED/FROZEN/PAYOUT_PENDING).
- **Garde double-libération** : `release_supplier_escrow` retourne l'escrow tel quel si `status == RELEASED` (idempotent) et rejette si `FROZEN` ; verrou `select_for_update` sur l'escrow et les wallets. ✅
- **Commission** : calculée `amount * rate`, `net_supplier = amount - commission`, rejet si net négatif ; débit acheteur (locked), crédit vendeur (pending), commission séparée. Cohérent. ✅
- Libération locale réservée à l'acheteur (`order.buyer_id == actor.id`). ✅

## 5. Concurrence / fraude / double soumission
- `select_for_update` systématique sur wallet/escrow/order avant mutation monétaire (lu dans `orders/services.py`, `wallets/services.py`, `ledger/services.py`).
- Idempotence : `WalletLedgerEntry.idempotency_key` (unique/wallet) + `LedgerTransaction.idempotency_key` (unique global) ; replay-safe mirror.
- Évaluation fraude active (log live observé pendant les tests : `fraud_evaluation ... decision=allow reasons=high_user_velocity`). ✅
- Double-débit/double-crédit : voir FINTECH_AUDIT.md (invariant comptable prouvé par test).

## 6. Non vérifié (honnêteté)
- ❌ NON VÉRIFIÉ en transaction réelle : dépôt/retrait NotchPay LIVE de bout en bout (argent réel — non déclenché). Couvert par tests unitaires webhooks (signatures, idempotence) verts.
- ❌ NON VÉRIFIÉ : parcours messagerie/notifications avec deux comptes humains réels (couvert par tests + handshake WS live).
- ❌ NON VÉRIFIÉ : exports/rapports admin volumineux (endpoint présent, non exercé avec données massives).
