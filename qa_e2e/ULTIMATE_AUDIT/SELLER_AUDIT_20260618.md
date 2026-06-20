# AUDIT ZERO TRUST — SYSTÈME VENDEUR (SUPPLIER / WHOLESALER)
Date : 2026-06-18 · Branche : `aws-infra` · Politique : ZERO TRUST (aucune affirmation sans preuve)

Légende : **VALIDÉ** (prouvé) · **ECHEC** (cassé) · **NON PROUVÉ** (non vérifiable dans cette session)

> Contrainte d'environnement majeure : le disque **C: est saturé à 100 % (0 octet libre)**.
> Conséquences réelles : la capture stdout du shell échoue par intermittence (ENOSPC), et les
> **builds Flutter Android/iOS/Web ainsi que `runserver` live n'ont pas pu être exécutés**.
> Contournement appliqué : TEMP redirigé vers `E:\tmp`, logs de tests vers `E:`, lecture via outils dédiés.

---

## 1. SELLER_SYSTEM_MAP

Rôles (preuve : `backend/apps/accounts/models.py:13-18`) :
`GENERAL_ADMIN, SUPPLIER (Fournisseur), WHOLESALER (Grossiste), TRANSIT_AGENT (Livreur), BUYER`.
**« Vendeur » = SUPPLIER + WHOLESALER.**

Chaîne réelle :

```
Flutter app vendeur (frontend/app)
   ↓ REST /api + WS
DRF ViewSets / APIView          products, orders, wallets, chat, disputes, compliance-documents
   ↓
Services métier                 OrderFinanceService, WalletAccountingService, DisputeStateMachine
   ↓
DB (invariants CheckConstraint) Wallet, WalletLedgerEntry (double-entrée), Order, OrderEscrow, Product
   ↓
Notification                    broadcast_event (WS) + create_realtime_notification + FCMToken
   ↓
Wallet/Escrow                   available / locked / pending + escrow LOCAL/SUPPLIER/LOGISTICS
   ↓
Audit Log                       AuditLog (accounts), WalletTransactionStateLog, DisputeEvent (event-sourced)
```

Surface de routes vendeur confirmée (`backend/config/urls.py`) : `products`, `orders`, `wallets`,
`chat/rooms`, `chat/messages`, `disputes`, `compliance-documents`, `campaigns`, `rfqs`, `shipments`,
`/api/auth/register/seller/`, `/api/auth/register/driver/`.

---

## 2. SELLER_BUSINESS_AUDIT

### Phase 2 — Compte vendeur
| Élément | Verdict | Preuve |
|---|---|---|
| Inscription vendeur isolée | **VALIDÉ** | `SellerRegisterView` + `SellerRegisterSerializer.role = ChoiceField(SUPPLIER, WHOLESALER)` (`serializers.py:486-554`) → impossible de viser admin/livreur |
| Anti-escalade (mass assignment) | **VALIDÉ** | `RegisterSerializer.role = HiddenField(BUYER)` (`serializers.py:406`) ; rôle client ignoré |
| Connexion 2FA (challenge OTP) | **VALIDÉ** (code) | `LoginRequestView` + `LoginVerifyView` (`views.py:651-694`) |
| Refresh token / logout | **VALIDÉ** (code) | `CustomTokenRefreshView`, `LogoutView` (`views.py:695-858`) |
| Suspension / réactivation | **VALIDÉ** (code) | `User.suspend()` blackliste les refresh tokens + `is_active=False` (`models.py:63-103`) |
| OTP / mot de passe oublié | **VALIDÉ** (code) | `PasswordResetChallenge` (hash PBKDF2, anti-énumération) `models.py:230-252` |
| Tests live serveur | **NON PROUVÉ** | `runserver` non lancé (C: plein) ; preuve par tests unitaires (219 tests accounts) |

### Phase 3 — Profil & KYC
- KYC modèle `ComplianceDocument` (RCCM, ID_CARD, TAX_CERT, INSURANCE) + signature + consentement horodaté (`accounts/models.py:165-188`). **VALIDÉ (code)**.
- Autorisation **relationnelle** (pas seulement par rôle) sur `ComplianceDocumentViewSet` (`views.py:395-406`). **VALIDÉ (code)**.
- Impact KYC sur permissions : `seller_is_verified` calculé sur documents APPROVED (`catalog/serializers.py:56-60`) ; contrôles fraude exigent `kyc_level>=1` côté fournisseur (`orders/services.py:185`). **VALIDÉ (code)**.

### Phase 4 — Publication produits  — **VALIDÉ** (suite `apps.catalog` = **14 tests OK**)
- Permissions : création réservée SUPPLIER/WHOLESALER (`catalog/views.py:50-52`) ; édition/suppression réservées au vendeur propriétaire (`views.py:60-70`). **VALIDÉ — anti-IDOR**.
- `is_active` **read-only serveur** (`serializers.py:30`), `seller` read-only (`serializers.py:46`).
- Upload : magic-bytes + whitelist extension + MIME + taille + rejet `octet-stream` + cap anti-bombe 25M px + scrub EXIF (`upload_security.py`). Couvre vidéo invalide, fichier corrompu, image géante, **extension falsifiée**, **image malveillante**. **VALIDÉ**.
- **CONSTAT ARCHITECTURAL (BUG-S1)** : `Product` n'expose **qu'une image et une vidéo** (`catalog/models.py:36-37`), pas de modèle `ProductImage`. → consigne « 1/10 images » **NON SUPPORTÉE** par la couche données (max 1 image). « 0 image » OK (champ nullable).

### Phase 5/6 — Stock & Catalogue
- Stock WHOLESALER = `available_qty` (obligatoire, validé `serializers.py:120-132`) ; SUPPLIER = paliers min/max + prix dégressif (cohérence prix imposée `serializers.py:115-119`). **VALIDÉ (code)**.
- Concurrence : décréments financiers sous `select_for_update` (escrow). Pagination DRF active (`results` dans réponse, test catalog). **VALIDÉ** pour pagination.
- Charge « 1000 produits / pagination profonde » : **NON PROUVÉ** (pas de test de charge exécuté).

### Phase 7 — Commandes / Machine à états
- `Order` **mono-produit** (`orders/models.py:37-58`). États : PENDING→SOURCING→SUPPLIER_VERIFIED→ADMIN_APPROVED→SHIPPING→COMPLETED + DISPUTED/REFUNDED/CANCELLED.
- **Pas de FSM centralisée** : chaque opération garde ses états-source autorisés (ex. `release_supplier_escrow` exige statut ∈ {SOURCING, SUPPLIER_VERIFIED, ADMIN_APPROVED, SHIPPING}, sinon `ValidationError`, `services.py:582`). Annulation bornée à `CANCELLABLE_ORDER_STATUSES` (`services.py:962-1000`). → transition interdite type « LIVRÉ→PAYÉ » rejetée par garde. **VALIDÉ (par gardes)**, mais **non formalisé**.
- Suite `apps.orders` = **10 tests OK** (inclut annulation/refund concurrents atomiques).

---

## 3. SELLER_FINTECH_AUDIT — **VALIDÉ** (suite `apps.wallets` = **49 tests OK**)

Invariants DB (`wallets/models.py:28-47`) : `available/locked/pending >= 0`,
`blocked == locked`, `balance == available+locked+pending` (CheckConstraint).

Primitive comptable unique `WalletAccountingService.mutate_wallet` (`services.py:163-246`) :
- `SELECT FOR UPDATE` sur le wallet ; montant strictement positif ;
- idempotence replay-safe (rejoue le miroir ledger si tué entre-temps) ;
- snapshots `*_before` / `*_after` sur chaque écriture (ledger double-entrée auditable) ;
- gardes : `InsufficientFundsError` si available<0, `FinancialInvariantError` si locked/pending<0 ;
- miroir vers ledger double-entrée **dans le même bloc atomique** (`services.py:244`).

| Opération | Verdict | Preuve |
|---|---|---|
| Escrow lock (achat) | **VALIDÉ** | `lock_funds_for_order` available→locked, idempotent (`orders/services.py:66-176`) |
| Libération vendeur + commission | **VALIDÉ** | `release_supplier_escrow` / `release_local_escrow_…` : buyer locked −gross, seller pending +net, commission retenue plateforme (`services.py:577-778`) |
| Payout MoMo + rollback atomique | **VALIDÉ** | `_queue_payout_transaction` + `rollback_failed_payout` (gel/DISPUTED si fonds insuffisants) |
| Remboursement / annulation | **VALIDÉ** | `_apply_locked_refund`, `cancel_order` (commit/rollback conjoints) |
| Split litige (invariant) | **VALIDÉ** | `dispute_split_release` impose `buyer_refund + seller_release == total_locked` (`services.py:1124`) |
| Solde dispo/bloqué/total | **VALIDÉ** | propriété `total_balance` + champs séparés |
| « 1000 ops aléatoires, 0 création/destruction » | **VALIDÉ par construction** + 49 tests | invariants DB + montants positifs + double-entrée ; **fuzz 1000 ops non exécuté littéralement** |

Observation : la commission n'est pas créditée sur un wallet plateforme tracké (sortie de l'espace
utilisateur) ; elle est suivie via `DailyReconciliationReport.platform_commission_total`. Acceptable, à documenter.

### Phase 9 — Retraits
- **PIN wallet SUPPRIMÉ** (décision produit) : `request_otp` → **410 GONE** (`wallets/views.py:489-494`).
  Le retrait est protégé par un **OTP email** (`verify_sensitive_action_challenge`, action `wallet.withdraw`, `views.py:473-487`).
  → Sous-items « PIN invalide / expiré / bloqué / 5 erreurs / rotation / reset PIN » = **NON APPLICABLE** (mécanisme retiré, remplacé par 2FA email).
- Flux retrait : OTP → fraude **fail-closed** → idempotence → contrôle solde → `mutate_wallet` (available→pending) → décaissement NotchPay → rollback si échec. **VALIDÉ**.
- Webhooks : HMAC-SHA256 **obligatoire** (rejet si secret absent), fenêtre anti-replay, contrôle montant exact, idempotence par `event_id` unique (`views.py:267-362, 1149-1197`). **VALIDÉ**.

---

## 4. SELLER_SECURITY_AUDIT (Phases 10/13/14)

| Vecteur | Verdict | Preuve |
|---|---|---|
| IDOR produit | **VALIDÉ** | update/destroy gardés par `seller_id == user.id` (`catalog/views.py:60-70`) ; test catalog acheteur=403 |
| IDOR wallet | **VALIDÉ** | `WalletViewSet.get_queryset` filtre `owner=request.user` (`wallets/views.py:55-56`) |
| Privilege escalation (inscription) | **VALIDÉ** | HiddenField/ChoiceField rôle (`serializers.py:396-602`) |
| Mass assignment | **VALIDÉ** | `is_active`/`seller` read-only ; rôle non writable |
| WebSocket hijacking / isolation salon | **VALIDÉ** | `ChatConsumer.connect` exige JWT (close 4401) + appartenance salon (close 4403) ; `receive` force `sender_id` (`chat/consumers.py:15-52`) |
| Upload malware / extension falsifiée | **VALIDÉ** | magic-bytes + MIME + cap pixels (`upload_security.py`) |
| JWT forgery | **VALIDÉ (code)** | SimpleJWT + auth scope WS ; bypass debug refusé hors DEBUG (test `debug_bypass_attempt_outside_debug`) |
| Webhook forgery (paiement) | **VALIDÉ** | HMAC obligatoire + anti-replay + montant |
| Rate limiting | **VALIDÉ (code)** | `throttle_scope` (`wallet`, `register`) |
| SQL Injection | **NON PROUVÉ / mitigé** | ORM Django paramétré, aucune requête brute trouvée ; **pas de payload live injecté** |
| XSS / CSRF | **NON PROUVÉ / mitigé** | API JSON DRF + JWT stateless (pas de cookie de session) ; **pas de test live** |
| SSRF / RCE / Path traversal | **NON PROUVÉ** | non testés en live cette session |

---

## 5. SELLER_FLUTTER_AUDIT (Phase 15)
- `flutter analyze` (app vendeur `frontend/app`) : **« No issues found! »**, exit 0 (Flutter 3.38.9). **VALIDÉ**.
- Builds Android / iOS / Web : **NON PROUVÉ cette session** (C: saturé empêche le build). Builds release prouvés antérieurement (mémoire projet), non re-validés ici.
- Tests widget/intégration Flutter : **NON PROUVÉ** (non exécutés).

## 6. SELLER_INFRA_AUDIT (Phase 16/infra)
- Stockage preuves : `FileSystemStorage` interdit en prod (`orders/services.py:45-63`). **VALIDÉ (code)**.
- Reconciliation quotidienne + retry payout + alertes ops présents (`wallets/`). **VALIDÉ (code)**.
- Vérification live prod (S3/CloudFront/Redis/Celery) : **NON PROUVÉ** (pas d'accès live cette session).

## 7. SELLER_E2E_REPORT (exécution réelle)
| Suite | Résultat | Durée |
|---|---|---|
| `apps.catalog` (produits vendeur) | **14 tests OK** | 26.5 s |
| `apps.wallets` (fintech) | **49 tests OK** | 116.8 s |
| `apps.orders` (escrow/états) | **10 tests OK** | 64.9 s |
| `apps.accounts` (auth/KYC/rôles) | **219 tests OK** | 344.4 s |
| `apps.ledger` (double-entrée) | **4 tests OK** | 10.4 s |
| `apps.disputes` / `apps.escrow` / `apps.chat` | **0 test découvert** sous ce label (logique couverte indirectement via orders/wallets) | — |
| **TOTAL backend exécuté** | **296 tests OK · 0 échec · 0 erreur** | ~9 min |
| `flutter analyze` app vendeur | **0 issue**, exit 0 | 9.4 s |

## 8. SELLER_BUGS_FOUND
- **BUG-S1 (MOYEN, fonctionnel)** : `Product` ne supporte qu'**une seule image** (pas de galerie). Consigne « 10 images » impossible sans modèle `ProductImage`.
- **OBS-S2 (FAIBLE, archi)** : machine à états des commandes décentralisée (gardes par opération) — fonctionne mais non formalisée, contrairement aux litiges (`DisputeStateMachine`).
- **OBS-S3 (FAIBLE, compta)** : commission plateforme non tracée sur un wallet dédié (suivie via reconciliation).
- **OBS-S4 (INFO)** : PIN wallet retiré → 2FA email ; documentation à mettre à jour si Phase 9 attendait un PIN.

## 9. SELLER_FIXES_APPLIED
Aucune modification appliquée au code dans cette session (audit en lecture/exécution seule, conformément
à la politique Zero Trust de preuve). BUG-S1 nécessite une décision produit (galerie multi-images).

## 10. SELLER_PRODUCTION_READINESS — NOTATION & VERDICT

| Axe | Note | Justification |
|---|---|---|
| Architecture | **9/10** | DDD modulaire, ledger double-entrée, litiges event-sourced ; −1 (Product mono-image, FSM commandes décentralisée) |
| Sécurité | **8/10** | IDOR/upload/webhook/WS/inscription + fraude fail-closed prouvés ; −2 (pas de pentest live SQLi/XSS/SSRF) |
| Fintech | **9/10** | invariants DB + double-entrée + idempotence + rollback + reconciliation ; −1 (commission hors wallet tracké) |
| Performance | **6/10** | index + pagination présents ; aucun test de charge exécuté → NON PROUVÉ |
| Logique métier | **8/10** | cycle escrow complet, invariant split litige ; −2 (commande mono-produit, panier local) |
| Flutter | **7/10** | analyze 0 issue prouvé ; builds/tests non ré-exécutés cette session |
| Infrastructure | **6/10** | garde-fous code présents ; live prod non vérifié + disque C: saturé (risque opérationnel réel) |

### VERDICT FINAL : **GO CONDITIONNEL**

Le cœur vendeur (publication, stock, commandes/escrow, wallet/retraits, litiges, isolation des rôles
et des salons) est **solide et prouvé par exécution réelle** (**296 tests backend verts, 0 échec**
+ analyze Flutter 0 issue). Réserve de transparence : les labels `disputes`/`escrow`/`chat` n'ont
découvert aucun test dédié (logique couverte indirectement). Conditions à lever avant un GO ferme :
1. **Exécuter en live** : `runserver` + parcours API vendeur réel, tests de charge (1000 produits / fuzz 1000 ops wallet), pentest live (SQLi/XSS/SSRF). → actuellement **NON PROUVÉ**.
2. **Builds mobiles** Android/iOS/Web à re-valider (bloqués par C: saturé).
3. **Résoudre la saturation disque C: (0 octet)** — risque opérationnel immédiat sur la machine de build/test.
4. Décision produit sur **BUG-S1** (galerie multi-images) si requis par l'UX.
