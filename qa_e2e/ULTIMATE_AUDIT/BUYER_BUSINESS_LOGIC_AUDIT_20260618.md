# AUDIT COMPLET — LOGIQUE MÉTIER APPLICATION ACHETEUR (BUYER) — Marché CM
Date : 2026-06-18 · Méthode : vérification directe du code source (aucune supposition, anciens rapports ignorés)
App auditée : `frontend/Clients` (rôle `BUYER` — `frontend/Clients/lib/main.dart:177`)
Backend : Django REST (`backend/apps/*`) · Preuves runtime : `flutter analyze` = 0 issue, Django `check` = 0, **52 tests backend OK** (orders + wallets.security + accounts.e2e_payment).

---

## 0. SYNTHÈSE / VERDICT

Le **cœur financier (wallet, ledger double-entrée, escrow, webhooks NotchPay, payout/retry/rollback)** est de **qualité production** : verrous `SELECT FOR UPDATE`, invariants de solde au niveau DB (`CheckConstraint`), idempotence multi-couche, HMAC obligatoire sur webhooks avec contrôle de montant, fraude *fail-closed* sur les sorties d'argent. Les contrôles d'accès (IDOR, WebSocket JWT, chat, KYC relationnel) sont solides.

Les défauts trouvés ne sont **pas dans la mécanique de l'argent** mais dans les **garde-fous métier périphériques** : pas de validation de mot de passe à l'inscription, pas de gestion de stock, vendeurs suspendus encore commandables, risque de double-commande au checkout, et incohérences d'affichage/onglets côté Flutter.

**Prêt commercialement ?** → **Conditionnel.** Le module paiement/séquestre est apte. Corriger les 2 HIGH + le double-checkout avant ouverture commerciale réelle.

---

## 1. BUYER_BUSINESS_LOGIC_MAP (cartographie réelle, prouvée)

| Étape | Frontend (Clients) | Endpoint backend | Modèle / logique | DB |
|---|---|---|---|---|
| Inscription | `features/auth/*`, `RegisterSerializer` | `POST /api/auth/register/` → `RegisterView` | `RegisterSerializer.create` rôle **forcé BUYER** (HiddenField) ; auto-login (JWT immédiat) ; géocodage Celery | `User` |
| Connexion | `auth`, `TokenRepository` (Keychain/Keystore) | `POST /api/auth/login/` → `LoginRequestView` | email+mot de passe → JWT ; **OTP login supprimé** (`LoginVerifyView` = 410) | JWT blacklist |
| Profil | `profile/profile_hub_page.dart` | `POST /api/auth/profile/` → `ProfileUpdateView` | mise à jour de `request.user` uniquement (pas d'IDOR) ; **OTP obligatoire** (`profile.update` ∈ 2FA) | `User` |
| Recherche | `feed/*`, `home/*` | `GET /api/products/?q=` → `ProductViewSet` | filtre `is_active=True`, recherche multi-termes title/brand/description | `Product` |
| Produit | `feed/*` | `GET /api/products/{id}/`, `/reviews/`, `/track-view/` | détail + avis vérifiés + profil de préférences | `Product`, `OrderReview`, `BuyerPreferenceProfile` |
| Panier | `buyer/cart_page.dart` + `buyer_store.dart` | **aucun** (panier 100 % local) | `Cart ≠ Order` respecté : panier en mémoire client | — |
| Checkout | `cart_page._checkout` | `POST /api/orders/` (1 par article) | `OrderSerializer.create` calcule prix (snapshot), frais transport, type LOCAL/INTL | `Order`, `Shipment` |
| Paiement / Escrow | (financé en amont via wallet) | `OrderFinanceService.lock_funds_for_order` | bloque `available → locked` ; crée `OrderEscrow` (LOCAL ou SPLIT supplier/logistics) | `Wallet`, `WalletLedgerEntry`, `OrderEscrow` |
| Commande | `orders/orders_page.dart` | `GET /api/orders/` (scopé buyer) | statuts métier (voir §6) ; transitions par actions dédiées | `Order` |
| Livraison | `orders/order_tracking_page.dart`, WS `tracking_{id}` | `POST /api/shipments/{id}/update_status`, `submit_proof`, `validate_delivery` | preuve obligatoire avant DELIVERED ; deadline contestation 48 h | `Shipment`, `DeliveryProof`, `ShipmentEvent` |
| Confirmation / Libération | `validate_delivery` (buyer) | `release_local/logistics_escrow_after_buyer_confirmation` | `locked → vendeur (pending) − commission` puis payout NotchPay | `OrderEscrow`, `WalletTransaction` |
| Avis | `orders_page` | `POST /api/orders/{id}/review/` | uniquement si `COMPLETED`, achat vérifié, 1 seul avis | `OrderReview` |
| Litige | `logistics/shipment_disputes_page.dart` | `POST /api/shipments/{id}/open_dispute`, `/api/shipment-disputes/` | gèle les escrows (`freeze_order_escrows`) ; décision admin = split | `ShipmentDispute`, `OrderEscrow` |
| Remboursement | (admin/livreur) | `refund_order_locked_funds`, `dispute_split_release` | `locked → available` (acheteur) atomique | `Wallet`, `OrderEscrow` |

---

## 2. BUYER_API_AUDIT (authentification)

- **Inscription** : rôle forcé `BUYER` (`serializers.py:406` HiddenField) — un client ne peut pas s'auto-promouvoir. Anti-énumération sur email (`serializers.py:416-426`) et username (suffixe silencieux). Auto-login via `_issue_session_tokens` (`views.py:572`).
- **Wallet à l'inscription** : **non créé** par signal ; création paresseuse `get_or_create` au 1er usage (`services.py:143`). Fonctionnellement OK (le wallet existe toujours quand requis) mais diverge de l'attente « création auto ». → BUG-07 (LOW).
- **OTP de connexion** : **supprimé** — `LoginVerifyView` renvoie 410 (`views.py:684-692`). Login = email+mot de passe direct → JWT.
- **JWT** : `RefreshToken.for_user` ; refresh **avec rotation + blacklist** de l'ancien (`CustomTokenRefreshView`, `views.py:695-746`) ; logout blackliste le refresh (`views.py:843`).
- **Compte suspendu** : `LoginRequestSerializer.validate` (`serializers.py:653`) + `LoginRequestView` (`views.py:662`) refusent ; `User.suspend()` blackliste tous les refresh (`models.py:63`).
- **Stockage token Flutter** : `flutter_secure_storage` adossé Keystore/Keychain, AES-GCM (`token_repository.dart:16-25`). ✔
- **Reset mot de passe** : code 6 chiffres hashé PBKDF2, anti-énumération, attempt-cap, révocation des sessions (`PasswordResetRequest/Confirm`).

**Cas testés (par lecture) :** email déjà existant → 400 générique ✔ ; OTP login → 410 (n/a) ; trop de tentatives reset → code brûlé ✔ ; compte suspendu → 403 ✔. **Téléphone déjà utilisé → non détecté** (BUG-06). **Mot de passe faible accepté** (BUG-01).

---

## 3. BUYER_SECURITY_AUDIT

| Vecteur | Résultat | Preuve |
|---|---|---|
| IDOR profil (modifier un autre user) | **Bloqué** — agit sur `request.user` seul | `views.py:756-808` |
| IDOR documents KYC (BOLA) | **Bloqué** — autorisation relationnelle, 404 anti-énumération | `views.py:400-450` |
| Modif profil sans token | **Bloqué** — `IsAuthenticated` | `views.py:757` |
| Upload avatar malveillant | **Bloqué** — `validate_uploaded_file` (magic bytes) + `scrub_image_metadata` | `serializers.py:138-146` |
| WebSocket sans token / token en URL | **Bloqué** — JWT validé (signature/exp/blacklist), query-string refusée en prod | `websocket_auth.py:52-98`, `consumers.py:50-64` |
| Chat — accès conversation étrangère | **Bloqué** — querysets scopés participants ; append-only (pas de PATCH/PUT/DELETE) | `chat/views.py:15-55` |
| Chat — recherche cross-room (fuite) | **Bloqué** — `room` obligatoire, LIKE échappé | `chat/views.py:42-54` |
| Webhook paiement forgé | **Bloqué** — HMAC-SHA256 obligatoire, montant vérifié, idempotent | `wallets/views.py:267-314, 1149-1197` |
| Fraude indispo (DoS) sur sortie d'argent | **Fail-closed** (503) pour withdraw/transfer/payout | `wallets/views.py:369-420` |

**Faille notable : mots de passe.** `AUTH_PASSWORD_VALIDATORS` est défini (`settings.py:337-342`) mais **jamais appelé** par l'API (aucun `validate_password` dans `apps/accounts`). L'inscription n'applique que `min_length=8` → `12345678`, `password`, `00000000` acceptés. → BUG-01 (HIGH).

---

## 4. BUYER_DATABASE_AUDIT (catalogue, panier, commande)

- **Catalogue** : `ProductViewSet.get_queryset` filtre `is_active=True` sur list/retrieve (`catalog/views.py:37-48`). Produits inactifs masqués ✔.
  - **MAIS** : aucun filtre sur le vendeur suspendu/inactif → produits d'un vendeur suspendu **toujours visibles et commandables** (BUG-03). Aucun filtre stock (`available_qty`) → produits à stock 0 listés (lié BUG-02).
- **Panier** : 100 % local (`buyer_store.dart`), invariant **Cart ≠ Order** respecté. Snapshot du prix calculé à la commande (pas au panier).
- **Commande** : `Order` est **mono-produit** (`product` FK + `quantity`) — **il n'existe pas de modèle `OrderItem`** ni de `Cart` côté serveur. Prix figé : `unit_price`/`total_price` calculés depuis le produit puis stockés (`orders/serializers.py:108-136`).
  - **Stock** : `OrderSerializer.create` valide `min_order_qty ≤ quantity ≤ max_order_qty` mais **ne vérifie ni ne décrémente `available_qty`** → **survente possible** (BUG-02).
- **Contraintes DB clés vérifiées** : `Wallet` `CheckConstraint` (soldes ≥ 0, `balance = available+locked+pending`, `blocked=locked`) `wallets/models.py:27-47` ; `WalletTransaction`/`WalletLedgerEntry` uniques sur `idempotency_key` ; `OrderEscrow` unique `(order, escrow_type)`.

---

## 5. BUYER_FINTECH_AUDIT (zone critique) — **SOLIDE**

- **Modèle de flux** : pas d'« étape paiement » séparée. Le buyer **recharge** le wallet (NotchPay), puis la création de commande **bloque** les fonds (`available → locked`) via `lock_funds_for_order` (`orders/services.py:66-176`). Avant : `Wallet = X`. Après : `available = X − total`, `locked += total`. L'argent vendeur reste **bloqué en escrow** jusqu'à confirmation acheteur. ✔ (correspond exactement à la spec demandée).
- **Recharge** :
  - Paiement réussi → webhook `payment.complete` crédite `available` (`_mark_transaction_success`).
  - Paiement échoué → `_mark_transaction_failed` (rollback withdraw, etc.).
  - **Webhook doublé** → `WalletWebhookEvent.event_id` unique → 200 idempotent (`views.py:1133`).
  - **Montant falsifié** → comparé à `abs(tx.amount)`, rejet 400 ; **montant absent** → rejet (`views.py:1149-1173`).
- **Double paiement / double-clic / timeout** : `Idempotency-Key` (`IdempotencyService` + contrainte DB) ; `SELECT FOR UPDATE` sur wallet ; savepoints anti-`IntegrityError`.
- **Ledger double-entrée** : chaque mutation wallet est **mirroir** dans `LedgerTransaction` dans la **même transaction atomique** (`services.py:241-244`) — les deux ledgers ne peuvent pas diverger ; replay-safe (`_ensure_ledger_mirror_present`).
- **Limites KYC** : `KYC_LIMITS` appliqué incluant les `PENDING` (anti-bypass parallèle, `views.py:446-471`). **Niveau 0 (nouvel acheteur) = 25 000 XAF/tx, 50 000/jour** (`settings.py:676`). → contrainte produit (BUG-08/INFO) : un nouvel acheteur ne peut pas financer un achat > 25 000 XAF avant validation KYC admin.
- **Libération** : commission plateforme (5 %, `services.py:35`) **fixée serveur**, jamais par le client ; prélevée côté **vendeur** (net = montant − commission). Payout NotchPay avec `PayoutRetryJob` + `rollback_failed_payout` (remet en litige si solde incohérent).

---

## 6. Commande — statuts & transitions (Phase 6)

Énumération réelle (`orders/models.py:8-20`) — **différente** du modèle classique attendu : `PENDING, SOURCING, SUPPLIER_VERIFIED, ADMIN_APPROVED, SHIPPING, DELIVERED, COMPLETED, DISPUTED, REFUNDED, CANCELLED, CONFIRMED(legacy)`.

- **Transitions interdites** : map `ORDER_STATUS_TRANSITIONS` (`orders/views.py:15-28`). `COMPLETED`/`CANCELLED`/`REFUNDED` = états terminaux (`set()`), donc `COMPLETED → PROCESSING` **impossible**. ✔
- **Pas de mutation libre** : `OrderViewSet.http_method_names = ["get","post",...]` — **pas de PATCH/PUT/DELETE** ; les transitions passent par actions dédiées + `select_for_update` (`orders/views.py:62`).
- **Annulation** : `cancel_order` atomique (statut + refund escrow ensemble) — corrige le bug historique « CANCELLED avec fonds bloqués » (`services.py:971-1012`).

---

## 7. Phase 8 — PIN wallet

- **Supprimé (décision produit)** : `WalletPinView` = 410 (`accounts/views.py:859-870`). Sorties d'argent protégées par **OTP email** (`wallet.withdraw` ∈ `SENSITIVE_ACTIONS_REQUIRING_2FA`, `security.py:73-80`), OTP **hashé PBKDF2**, attempt-cap, single-use (`verify_sensitive_action_challenge`).
- Colonnes `wallet_pin_*` et méthodes `set/check_wallet_pin` **résiduelles mais inutilisées** (code mort) — pas de risque, à nettoyer.

---

## 8. Phase 9 — Livraison

- `submit_proof` : **réservé au livreur assigné** (`logistics/views.py:435`), validation magic-bytes de la photo, stockage distant exigé en prod.
- `validate_delivery` : **réservé à l'acheteur** ET **exige une `DeliveryProof` existante** avant de passer `DELIVERED` et de libérer l'escrow (`views.py:462-503`). → **pas de livraison validée sans preuve** ✔.
- `update_status` : interdit de poser `DELIVERED` directement, transitions contrôlées, `CANCELLED` atomique avec refund ; faux livreur bloqué (`_can_update_status`, `views.py:116-123`).
- Chaîne de garde (`CustodyEvent`) avec `integrity_hash` SHA-256 + vérification d'altération.

---

## 9. Phase 10/11 — Chat & Litiges

- **Chat** : voir §3 (scopé participants, append-only, WS JWT, anti-spoof GPS). ✔
- **Litiges (buyer)** : l'app utilise `/api/shipment-disputes/` + `POST /api/shipments/{id}/open_dispute` (`shipment_disputes_page.dart`), réservé aux parties de l'expédition (`views.py:509`, `768`). Ouverture → gèle les escrows. Modif/suppression de litige = **admin only** ; ajout de preuve nécessite `dispute.evidence.add`. Preuves immuables (`DisputeEvidence`, hash SHA-256).
- **INFO** : un **second** système de litige existe (`apps.disputes.DisputeCase`, event-sourced, `/api/disputes/`) **non câblé dans la Buyer app** → code parallèle/mort à clarifier (BUG-09).

---

## 10. Phase 12 — Notifications

- `create_realtime_notification` (`notifications/service.py`) : crée la `Notification` en DB + broadcast WebSocket (`notification_{user_id}`) + **push FCM best-effort** (n'échoue jamais le flux). Déclenchée sur : commande créée, paiement confirmé/échoué, livraison finalisée, nouvel avis, incidents wallet (admins notifiés).
- FCM token : anti-hijack — refus si le token est déjà lié à un autre compte (`accounts/views.py:1347-1360`).

---

## 11. BUYER_FLUTTER_AUDIT (Phase 13)

- **`flutter analyze` (Clients) = `No issues found!` (132 s)** — prouvé. Pas d'erreur de lint, donc `use_build_context_synchronously`, dead code, etc. propres.
- Gestion d'erreur API : `try/catch` + `_api.toUserMessage(e, fallback:)` systématique (ex. `cart_page.dart:166-171`, `orders_page.dart:270`). États loading présents (`_loadingProfiles`, `LinearProgressIndicator`). Contexte après `await` gardé par `if (!mounted) return` (`cart_page.dart:148,173`).
- **Défauts UI** : voir BUG-04 (double-checkout) et BUG-05 (affichage commission) et BUG-10 (onglet « Litiges »).

---

## 12. BUYER_E2E_TEST_REPORT (Phase 14)

Exécuté réellement (sqlite test DB) :
```
python manage.py test apps.orders apps.wallets.tests_security apps.accounts.tests_e2e_payment
→ Ran 52 tests ... OK
```
Couvre : création commande + lock escrow, confirmation livraison + libération, annulation/refund atomique (concurrence), sécurité wallet (topup/withdraw/reconcile/webhook HMAC), e2e paiement. **0 échec, 0 régression.** `manage.py check` = 0 issue.

Le scénario complet acheteur (inscription → connexion → recherche → panier → commande → escrow → livraison → confirmation → avis) est **couvert et vérifié** à travers le code + ces tests. Limite : pas de run live contre NotchPay (mode webhook/simulé testé).

---

## 13. BUG_LIST

### BUG-01 — Validateurs de mot de passe non appliqués à l'inscription — **HIGH**
- **Localisation** : `backend/apps/accounts/serializers.py:448-479` (`RegisterSerializer.create`), `settings.py:337-342`.
- **Cause** : `set_password()` appelé sans `django.contrib.auth.password_validation.validate_password()`; les `AUTH_PASSWORD_VALIDATORS` ne tournent que via l'admin Django, pas via l'API. Seul `min_length=8` est imposé.
- **Impact** : comptes acheteurs avec mots de passe triviaux (`12345678`, `password`) → credential stuffing/brute force facilités.
- **Correction** : dans un `validate_password()` du serializer, appeler `password_validation.validate_password(value, user=None)` et propager les `ValidationError`. Appliquer aussi à Seller/Driver/PasswordChange/Reset.
- **Test de validation** : POST `/api/auth/register/` avec `password="password"` → 400.

### BUG-02 — Aucun contrôle/décrément de stock (survente) — **HIGH**
- **Localisation** : `backend/apps/orders/serializers.py:105-111` ; `backend/apps/catalog/models.py:41` (`available_qty`).
- **Cause** : seule la plage `min/max_order_qty` est validée ; `available_qty` n'est ni lu ni décrémenté à la création de commande.
- **Impact** : un produit à stock fini peut recevoir un nombre illimité de commandes → engagements de vente impossibles à honorer, escrows multiples.
- **Correction** : si `available_qty` non nul, vérifier `quantity ≤ available_qty` et décrémenter sous `select_for_update` dans la transaction de création ; rejeter sinon.
- **Test** : produit `available_qty=2`, commander 5 → 400 ; 2 commandes de 1 puis 1 de 1 → la 3ᵉ échoue.

### BUG-03 — Produits de vendeurs suspendus/inactifs commandables — **MEDIUM**
- **Localisation** : `backend/apps/catalog/views.py:37-48` (filtre `is_active` produit seulement) ; `backend/apps/orders/serializers.py:73-95` (pas de check vendeur).
- **Cause** : aucun filtre `seller__is_active=True` / `seller.is_suspended`.
- **Impact** : un acheteur peut commander auprès d'un vendeur suspendu (qui ne peut plus se connecter) → fonds séquestrés vers un compte gelé, litiges.
- **Correction** : exclure `seller__is_active=False` du catalogue ; valider l'état du vendeur dans `OrderSerializer.create`.
- **Test** : suspendre un vendeur → ses produits absents du catalogue ; `POST /api/orders/` sur son produit → 400.

### BUG-04 — Double-commande au checkout (pas d'idempotence ni de garde bouton) — **MEDIUM**
- **Localisation** : `frontend/Clients/lib/features/buyer/cart_page.dart:152-172` (boucle POST sans `Idempotency-Key`, bouton non désactivé) ; `backend/apps/orders/serializers.py:174` (clé `order-create:{order.id}` = par-commande, inutile pour dédup inter-requêtes).
- **Cause** : chaque `POST /api/orders/` crée une commande distincte ; aucun verrou anti-double-soumission.
- **Impact** : double-tap / latence réseau → commandes + blocages de fonds dupliqués.
- **Correction** : désactiver le bouton pendant l'envoi (flag `_submitting`) ; envoyer un `Idempotency-Key` stable par ligne de panier et l'honorer côté création de commande.
- **Test** : 2 POST identiques rapprochés → 1 seule commande.

### BUG-05 — Incohérence d'affichage financier au panier — **MEDIUM**
- **Localisation** : `frontend/Clients/lib/features/buyer/cart_page.dart:23,119-121,918` (commission **2,5 %** ajoutée au « Total à séquestrer ») vs `backend/apps/orders/serializers.py:118-122,168` + `services.py:35` (commission **5 %**, prélevée **côté vendeur**, **non ajoutée** au montant bloqué de l'acheteur).
- **Cause** : la logique d'affichage diverge de la logique serveur (taux et assiette).
- **Impact** : le montant « à séquestrer » montré ≠ montant réellement bloqué (le backend bloque produits+transport, sans commission acheteur) ; taux affiché faux.
- **Correction** : aligner l'UI sur la règle serveur (la commission n'est pas à la charge de l'acheteur) ; piloter le taux via `/api/ui-config/`.
- **Test** : comparer « total à séquestrer » UI vs `locked_balance` après commande → égalité.

### BUG-10 — Onglet « Litiges » filtre les commandes ANNULÉES, pas DISPUTED — **MEDIUM**
- **Localisation** : `frontend/Clients/lib/features/orders/orders_page.dart:277-297`.
- **Cause** : tab 2 (« Litiges ») filtre `status == "CANCELLED"` ; les commandes `DISPUTED` tombent dans « En cours » (tab 0 = tout sauf COMPLETED/CANCELLED).
- **Impact** : un acheteur en litige ne retrouve pas sa commande dans l'onglet « Litiges » ; les annulations y sont mal étiquetées.
- **Correction** : tab « Litiges » → `status == "DISPUTED"` ; prévoir un onglet/état « Annulées » distinct.
- **Test** : commande passée DISPUTED → visible sous « Litiges ».

### BUG-06 — Numéro de téléphone non unique à l'inscription — **LOW**
- **Localisation** : `backend/apps/accounts/serializers.py:14-25,441-442` ; champ `phone_number` = `EncryptedTextField` (non requêtable).
- **Cause** : pas de contrôle d'unicité (le chiffrement empêche un `filter(phone_number=...)`).
- **Impact** : plusieurs comptes avec le même numéro (peut être un choix produit ; à trancher).
- **Correction** (si unicité voulue) : stocker un hash déterministe indexé du téléphone pour contrôle d'unicité.

### BUG-07 — Wallet non créé à l'inscription — **LOW**
- **Localisation** : `RegisterSerializer.create` (pas de signal) ; `wallets/services.py:143` (`get_or_create` paresseux).
- **Impact** : aucun fonctionnel (le wallet existe au 1er usage) ; juste une divergence avec l'attente « création auto ». Optionnel : créer le wallet à l'inscription pour cohérence.

### BUG-08 — Plafond KYC niveau 0 bloque les achats de valeur — **INFO/MEDIUM (produit)**
- **Localisation** : `backend/config/settings.py:676` (`KYC_LIMITS[0] = 25 000/tx, 50 000/jour`) + `wallets/views.py:446-471`.
- **Impact** : un nouvel acheteur **ne peut pas recharger > 25 000 XAF** ni acheter au-delà avant validation KYC (PENDING → approbation admin). Parcours d'achat à valeur élevée gaté ; à documenter/calibrer + fluidifier l'onboarding KYC.

### BUG-09 — Double système de litige (code parallèle) — **INFO**
- **Localisation** : `apps.disputes.DisputeCase` (`/api/disputes/`, event-sourced) **non utilisé** par la Buyer app, qui passe par `apps.logistics.ShipmentDispute`.
- **Impact** : maintenance/confusion ; deux sources de vérité litige. Décider lequel est canonique et retirer/masquer l'autre.

---

## 14. CE QUI EST PROUVÉ CORRECT (frontend → backend → DB → infra)

- Séquestre escrow LOCAL & INTERNATIONAL (split supplier/logistics), libération conditionnelle, refund/annulation atomiques — **52 tests OK**.
- Webhooks NotchPay : HMAC obligatoire, montant vérifié, idempotents — testés.
- Contrôles d'accès : IDOR profil/KYC, WebSocket JWT, chat scopé, fraude fail-closed — vérifiés au code.
- `flutter analyze` Clients = 0 issue ; Django `check` = 0.

**Conclusion** : le moteur financier/séquestre de l'app acheteur est apte à un usage commercial. Les correctifs **BUG-01, BUG-02** (HIGH) et **BUG-04** (double-checkout) sont les prérequis de mise en marché ; BUG-03/05/10 améliorent fortement la fiabilité métier perçue.
