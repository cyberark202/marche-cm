# Incohérences backend ↔ frontend — Marché CM

Date : 2026-05-30
Portée : contrats d'API entre les 4 apps Flutter (`app`, `Clients`, `Driver App`, `admin`) et le backend Django.
Statut : ✅ corrigé dans cette passe · ⚠️ à corriger (backend) · ℹ️ par conception.

---

## 1. ✅ KYC `app` — mauvais noms/valeurs de champs (upload cassé)

- **Constat** : `app/lib/features/buyer/buyer_kyc_page.dart` postait sur `/api/compliance-documents/` les champs `certificate_type='ID_CARD'|'PASSPORT'`, `document`, `document_back`.
- **Contrat backend réel** (`ComplianceDocumentSerializer`) : champs **écritables** = `doc_type` et `file`. `validate_doc_type` exige une valeur de l'allow-list `{CNI, CNI_VERSO, PASSPORT, DRIVER_LICENSE, CERT_*}`. `ID_CARD` n'existe pas ; `document`/`document_back` ne sont pas des champs.
- **Effet** : l'upload KYC depuis `app` échouait (400 / champ requis manquant). Incohérence **pré-existante**.
- **Correction (faite)** : envoi `doc_type='CNI'|'PASSPORT'` + `file` ; le verso CNI est désormais un **second document** `doc_type='CNI_VERSO'`. `flutter analyze` vert.

---

## 2. ✅ Signature KYC — champ backend ajouté (migration `0015`)

- **Constat initial** : l'écran 46 (signature manuscrite « vous engage légalement ») était implémenté dans `app` (capture PNG + consentement CGU), mais `ComplianceDocument` n'avait **ni champ signature, ni horodatage de consentement** → la signature n'était pas conservée ni opposable.
- **Correction (faite, backend)** :
  - Modèle `ComplianceDocument` (`apps/accounts/models.py`) : ajout de `signature_image` (ImageField), `consent_accepted_at` (DateTime), `consent_version` (str).
  - Serializer (`ComplianceDocumentSerializer`) : entrées **write-only** `signature` (ImageField, validée + EXIF scrubbée) et `consent_accepted` (bool) ; lecture `signature_url` ; `create()` horodate le consentement (`timezone.now()`) + `consent_version` (`settings.KYC_CONSENT_VERSION`, défaut `"1.0"`).
  - Migration : `apps/accounts/migrations/0015_compliancedocument_consent_accepted_at_and_more.py`. `manage.py check` ✓, **180 tests accounts ✓**.
  - Le frontend (`app/buyer_kyc_page.dart`) envoie déjà `signature` + `consent_accepted` → désormais **persistés** côté serveur.
- **Restriction rôle BUYER : ✅ résolue** — endpoint dédié `POST /api/auth/kyc/submit/` (`BuyerKycSubmitView`) ouvert à tout utilisateur authentifié, restreint aux types identité (CNI/CNI_VERSO/PASSPORT), re-soumission = update + reset `PENDING`. Le frontend `app/buyer_kyc_page.dart` pointe désormais vers cet endpoint. Couvert par `tests_production_readiness.py`.

---

## 3. ✅ Réconciliation wallet — step-up 2FA manquant côté consumer

- **Constat** : `app` et `Clients` (wallet) appelaient `/api/wallets/reconcile/` avec `{transaction_id, status, reason}` **sans** `challenge_token`/`verification_code`.
- **Contrat backend** : `wallet.reconcile` exige une vérification sensible (step-up 2FA) → ces appels renvoyaient **403**. De plus, c'est une action **réservée admin** dans une app grand public.
- **Correction (faite)** : blocs admin retirés de `app` + `Clients` (cf. audit infra) ; la **console admin dédiée** implémente le flux step-up complet (`/api/auth/sensitive-action/request/` → code → reconcile).

---

## 4. ℹ️ Flux d'auth — endpoints désactivés (par conception)

- `/api/auth/login/verify/`, `/api/auth/verify-email/` : **désactivés** (flux OTP login retiré, email de confirmation supprimé). Les apps utilisent `/api/auth/login/` (email+mot de passe) directement.
- `/api/auth/refresh/` : non appelé explicitement par les UIs — géré par les intercepteurs Dio (refresh réactif sur 401 + proactif avant expiration). Cohérent.
- En cas de `AUTH_LOCKDOWN=True`, register/login/google renvoient `AuthDisabledView` : les écrans d'inscription doivent gérer ce 4xx proprement (à vérifier en QA).

---

## 5. ℹ️ Endpoints backend non consommés (normal)

- `/api/wallets/notchpay/checkout/webhook/`, `/api/wallets/notchpay/disburse/webhook/` : serveur-à-serveur (NotchPay), jamais appelés par les apps. ✔
- `/api/health/`, `/metrics/` : monitoring/infra, pas d'écran. ✔
- `/api/schema/…` (Swagger/Redoc) : documentation. ✔

---

## 6. Points à vérifier en QA (non confirmés en statique)

| # | Vérification | App |
|---|---|---|
| 6.1 | `certificate_type` encore utilisé ailleurs ? (rechercher d'autres uploads KYC obsolètes) | `Clients`, `Driver App` |
| 6.2 | Champs montant litige : l'arbitrage admin affiche le montant en best-effort ; confirmer qu'un champ montant est exposé sur `ShipmentDispute` ou ajouter un agrégat | `admin` |
| 6.3 | Gestion du `410 Gone` / `AUTH_LOCKDOWN` sur les écrans d'inscription | toutes |
| 6.4 | Image-search / track-view en URL absolue (`feed_api_service.dart`) — confirmer cohérence base URL | `Clients`, `app` |
| 6.5 | ✅ Résolu — endpoint dédié `/api/auth/kyc/submit/` pour le KYC acheteur (`BuyerKycSubmitView`) | `app` (buyer KYC) |

## 8. ✅ Défaut backend PRÉ-EXISTANT corrigé — auto-provisioning du wallet

- **Constat** : 7 tests wallet échouaient (`apps.wallets.tests_security.M6CursorValidationTests` ×5, `H1ErrorSanitizationTests.test_withdraw_provider_error_not_exposed`, `WalletFlowTests.test_withdraw_paypal_accepts_email_destination`) avec **404 « Portefeuille introuvable »** ou 400.
- **Cause** : l'helper de test `_make_user` crée l'utilisateur mais **aucun wallet**, et l'endpoint `wallet-transactions` faisait un `.get()` strict → 404 pour tout utilisateur fraîchement créé.
- **Correction (faite)** : adoption du contrat **création paresseuse** (cohérent avec le reste de l'API wallet qui utilise déjà `get_or_create`). L'action `transactions` (`apps/wallets/views.py`) auto-provisionne désormais le wallet via `Wallet.objects.get_or_create(owner=request.user)` → un utilisateur authentifié sans wallet voit une **liste vide** au lieu d'un 404 fallacieux. Les chemins `withdraw`/`topup`/`reconcile` utilisaient déjà `get_or_create` (avec `select_for_update`).
- **Vérification** : les **7 tests passent** (`python manage.py test apps.wallets.tests_security.M6CursorValidationTests apps.wallets.tests_security.H1ErrorSanitizationTests.test_withdraw_provider_error_not_exposed apps.wallets.tests.WalletFlowTests.test_withdraw_paypal_accepts_email_destination` → `OK`, 7/7).

---

## 7. Bilan

- **2 incohérences réelles corrigées** côté frontend dans cette passe (KYC field mapping, reconcile consumer).
- **1 incohérence structurelle corrigée** côté backend (champ signature KYC — migration `0015`).
- **1 défaut backend pré-existant corrigé** (Section 8 — auto-provisioning wallet, 7 tests rétablis).
- Le reste relève du **par conception** ou de **vérifications QA** non bloquantes.
