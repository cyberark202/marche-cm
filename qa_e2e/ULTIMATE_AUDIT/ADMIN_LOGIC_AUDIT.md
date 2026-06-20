# ADMIN_LOGIC_AUDIT — Marché CM

**Date :** 2026-06-20
**Périmètre :** Application ADMIN (Flutter `frontend/admin/project` + backend Django)
**Méthode :** preuve par exécution. Aucun audit antérieur réutilisé. Toute conclusion
est rattachée à un fichier:ligne, un endpoint testé ou une commande exécutée.

**Environnement de preuve :**
- Django 5.1.6, Python 3.12 (`python manage.py check` → *0 issue*).
- Suite complète : `python manage.py test` → **332 tests OK** (456 s).
- Tests admin dédiés (créés) : `apps/accounts/test_admin_logic_audit.py` → **17 tests OK**.
- Non-régression `UserViewSet` : suspension + sécurité + audit → **54 tests OK**.
- `flutter analyze` (app admin) → **No issues found**.

---

## 1. Cartographie réelle de l'ADMIN

### Surface RÉELLEMENT câblée dans la console Flutter
Source unique des appels : [`admin_repository.dart`](../frontend/admin/project/lib/features/data/admin_repository.dart).

| Action admin (écran) | Page Flutter | Endpoint API | Permission backend | Service | Impact DB |
|---|---|---|---|---|---|
| Voir KPIs | `admin_dashboard_page` | `GET /api/admin/dashboard/` | `admin.dashboard.view` | `AdminDashboardView` | aucun (lecture) |
| Lister/chercher users | `users_page` | `GET /api/users/[?q=]` | `IsAuthenticated` + scope admin | `UserViewSet` | aucun |
| Détail user | `user_detail_page` | `GET /api/users/{id}/` | scope admin | `UserViewSet` | aucun |
| File KYC | `kyc_queue_page` | `GET /api/compliance-documents/` | relationnelle | `ComplianceDocumentViewSet` | aucun |
| Valider/rejeter doc | `document_review_page` | `POST /api/compliance-documents/{id}/review/` | `compliance.review` | idem | `status`, `reviewed_by` + audit |
| Arbitrer litige | `arbitration_page` | `POST /api/shipment-disputes/{id}/decide/` | `admin.disputes.decide` | `ShipmentDisputeViewSet` | escrow/refund + audit |
| Réconcilier wallet | `reconciliation_page` | `POST /api/wallets/reconcile/` | `wallet.reconcile` + **step-up 2FA** | `WalletViewSet.reconcile` | transaction PENDING→SUCCESS/FAILED + audit |
| Escrow (lecture) | dashboard/wallet | `GET /api/escrow/holds/` | scope admin | `EscrowHoldViewSet` | aucun |
| Journal d'audit | `audit_page` | `GET /api/audit/events/`, `GET /api/admin/audit/export/` | `IsGeneralAdmin` / `audit.export` | `AuditEventViewSet`, `AuditLogExportView` | aucun |
| Config UI | divers | `GET /api/ui-config/` | `AllowAny` | `UiConfigView` | aucun |

### Capacités backend NON exposées par la console (constat, pas faille)
- Suspension/réactivation utilisateur : `UserViewSet.suspend/unsuspend`
  ([views.py:313-352](../backend/apps/accounts/views.py)) — **existe et testée** mais aucun bouton dans l'app admin.
- Création d'utilisateur géré : `create_managed_user` ([views.py:287](../backend/apps/accounts/views.py)) — non câblée en UI.
- Modération produit : un admin peut éditer/supprimer n'importe quel produit via
  `ProductViewSet.perform_update/destroy` ([catalog/views.py:60-70](../backend/apps/catalog/views.py)) — **aucun écran produit** dans l'app admin.

---

## 2. Authentification admin

| # | Élément | État | Preuve |
|---|---|---|---|
| 2.1 | Utilisateur normal sur endpoint admin | **403/404** | `test_buyer_forbidden_on_every_admin_endpoint` (8 endpoints) OK |
| 2.2 | Anonyme sur endpoint admin | **401/403** | `test_anonymous_forbidden_on_admin_endpoints` OK |
| 2.3 | JWT falsifié | **401** | `test_forged_jwt_rejected` OK |
| 2.4 | Admin légitime | **200** | `test_admin_dashboard_ok`, `test_admin_audit_events_ok_buyer_forbidden` OK |
| 2.5 | Token après suspension | **rejeté** | `test_existing_access_token_rejected_after_suspension` (suite existante) OK |
| 2.6 | Blacklist / rotation refresh | présent | `rest_framework_simplejwt.token_blacklist` importé ([views.py:31](../backend/apps/accounts/views.py)) |

**Verdict authentification : conforme.** Résultat attendu (normal→403, admin→OK) prouvé.

---

## 3. Gestion des utilisateurs

**Fonctionnalité :** lister, rechercher, filtrer, voir profil.
**État initial :** `users_page` chargeait `GET /api/users/` (1ʳᵉ page paginée = **20 lignes**,
`PAGE_SIZE=20`) puis filtrait **côté client**. `UserViewSet` n'avait **aucune recherche serveur**.

**Problème trouvé (A-01, fonctionnel — HIGH) :** au-delà de 20 comptes, tous les autres
utilisateurs étaient **invisibles et introuvables** par la recherche admin → l'exigence
« gros volume / rechercher / filtrer » échoue.
**Problème trouvé (A-02, LOW) :** le champ de recherche prétendait chercher `téléphone`/`ville`,
or `UserSerializer` n'expose ni `phone_number` ni `city` → critères morts.

**Risque :** un administrateur ne peut pas retrouver un compte litigieux dans une base
réelle → modération/KYC/anti-fraude inopérants en production.

**Correction appliquée :**
- Backend [`UserViewSet.get_queryset`](../backend/apps/accounts/views.py) : recherche serveur
  admin `?q=` sur `username / email / first_name / reference_code` + filtre `?role=` serveur.
  Le scope non-admin (auto-restriction à son propre id) reste **avant** tout filtre → anti-IDOR préservé.
- Frontend : [`AdminRepository.users({query})`](../frontend/admin/project/lib/features/data/admin_repository.dart)
  encode `?q=` ; [`users_page`](../frontend/admin/project/lib/features/users/users_page.dart)
  déclenche la recherche **serveur** (submit + bouton) et garde le filtre local pour les chips de rôle.
  Libellé corrigé en « Nom, email, code réf… ».

**Test effectué / Résultat :**
- `test_admin_server_side_search_beyond_first_page` (cible créée après 30 fillers, hors page 1) → **trouvée. OK**
- `test_admin_search_by_reference_code` → **OK**
- `test_search_query_does_not_break_non_admin_scoping` (acheteur `?q=autrui` ne voit que lui) → **OK**
- `flutter analyze` → **0 issue**.

### Suspension / modification (anti-escalade)
| Cas | Attendu | Preuve |
|---|---|---|
| Admin suspend un user | 200, login bloqué, audit écrit | suite existante `test_admin_can_suspend_user` OK |
| Admin se suspend lui-même | **400 refus** | `test_admin_cannot_suspend_self` OK |
| Admin suspend un autre admin | **400 refus** | `test_admin_cannot_suspend_another_admin` OK |
| Non-admin suspend | **403/404** | `test_non_admin_cannot_suspend` OK |
| **buyer → admin via profil** | **ignoré** | `test_buyer_cannot_self_promote_via_profile` : `role/is_superuser/is_staff/kyc_level` non modifiés. OK |
| PATCH rôle via `/api/users/{id}/` | **405** (ReadOnlyModelViewSet) | `test_userviewset_is_read_only_no_role_patch` OK |
| Admin crée un GENERAL_ADMIN via API | **400 refus** | `ManagedUserCreateSerializer.validate_role` ([serializers.py:338](../backend/apps/accounts/serializers.py)) ; `test_admin_cannot_create_general_admin_via_api` OK |

Le profil ([`ProfileUpdateSerializer`](../backend/apps/accounts/serializers.py), champs
`username/name/email/phone_number/avatar` uniquement) **n'expose ni rôle, ni solde, ni flags**
→ pas de mass-assignment. **Verdict : pas d'escalade de privilège possible.**

---

## 4. KYC / Compliance

**Workflow :** upload (rôle compliance) → stockage privé → file admin → review APPROVED/REJECTED → re-sync `is_verified`.

| Point | État | Preuve |
|---|---|---|
| Stockage privé KYC | **URL S3 signée, expirante** | [`config/storages.py`](../backend/config/storages.py) : `products/`+`avatars/` = public non signé ; tout le reste (compliance) = `querystring_auth=True`, `custom_domain=None` ; `AWS_DEFAULT_ACL=None` ([settings.py:377](../backend/config/settings.py)) |
| Admin ne peut PAS rendre un KYC public | **garanti** | `get_file_url` passe par `obj.file.url` → backend privé ; aucun chemin `products/`/`avatars/` pour un doc compliance |
| Autorisation lecture doc | **relationnelle, deny-by-default, 404 anti-énumération** | `ComplianceDocumentViewSet.get_queryset` ([views.py:400-450](../backend/apps/accounts/views.py)) |
| Review réservée admin | **`compliance.review`** | `review()` ([views.py:466](../backend/apps/accounts/views.py)) ; buyer→403 prouvé (case 5 du test 2.1) |
| Validation fichier (PDF/image, magic bytes, extension fake) | présent | `validate_uploaded_file` + `scrub_image_metadata` ([serializers.py:234-262](../backend/apps/accounts/serializers.py)) ; couvert par `test_compliance_upload_mime.py` (suite existante) |
| Journalisation review | oui | `write_audit_log(action_key="compliance.review")` |

**Verdict KYC : conforme.** Aucun document KYC exposable publiquement par l'admin.

---

## 5/6/7. Produits / Vendeurs / Commandes

- **Produits :** modération admin disponible côté backend (édition/suppression de tout produit,
  `perform_update/destroy` réservés propriétaire **ou** admin). Catalogue public filtré `is_active=True`
  ([catalog/views.py:37-70](../backend/apps/catalog/views.py)) → masquer = `is_active=False`.
  ⚠️ *Observation (R-01, MED) :* `perform_destroy` fait un **hard delete**. Pour un produit déjà
  référencé par des commandes, préférer un soft-delete (`is_active=False`). Non bloquant pour l'admin
  (aucun écran produit câblé) — à traiter avant d'exposer la modération produit en UI.
- **Vendeurs :** activation pilotée par les certifications (`_sync_business_user_verification`,
  [views.py:103-110](../backend/apps/accounts/views.py)) ; suspension via le module utilisateur (testée).
- **Commandes :** l'admin lit `GET /api/orders/` ; l'intervention financière passe **exclusivement**
  par la décision de litige (escrow release/refund/split) qui est **journalisée** — pas de mutation
  d'état de commande « à la main » non tracée depuis la console.

---

## 8. Wallet / Fintech (partie critique)

| Invariant | État | Preuve |
|---|---|---|
| `wallet.reconcile` réservé admin | oui | `reconcile()` ([wallets/views.py:1376](../backend/apps/wallets/views.py)) ; buyer→403 (test 2.1) |
| **Step-up 2FA obligatoire** même pour admin | oui | `verify_sensitive_action_challenge` avant toute mutation ; `test_admin_reconcile_requires_stepup` → **403 sans code**. OK |
| Réconciliation limitée aux PENDING | oui | garde `tx.status != PENDING` → 409 ([wallets/views.py:1407](../backend/apps/wallets/views.py)) |
| Webhook : signature HMAC | oui | [wallets/views.py:282-296](../backend/apps/wallets/views.py) |
| Webhook : anti-replay (fenêtre 5 min) | oui | `X-Notch-Timestamp` ([wallets/views.py:232-245](../backend/apps/wallets/views.py)) |
| Idempotence (double recharge / double webhook) | oui | `idempotency_key` + contrainte unique ([wallets/views.py:539-588](../backend/apps/wallets/views.py)) |
| Invariant comptable Σdébits = Σcrédits | **prouvé** | `apps/ledger/test_invariants_audit.py` (conservation, idempotence, refus déséquilibre) — vert dans la suite 332 |

**Verdict fintech : conforme.** L'admin ne peut pas créditer/débiter sans step-up, et le grand
livre reste équilibré.

---

## 9/10. Litiges & Journal d'audit

- Décision litige réservée `admin.disputes.decide`, exécute l'effet financier via
  `OrderFinanceService` (refund/release/split) puis **journalise** (`write_audit_log`,
  [logistics/views.py:830](../backend/apps/logistics/views.py)).
- `resolution_note` **obligatoire** sur RESOLVED → décision non tracée impossible.
- Journal d'audit : `actor`, `action`, `action_key`, `metadata`, `created_at`. Les métadonnées
  passent par `sanitize_audit_metadata` qui **supprime PII/secrets** ([security.py:120-150](../backend/apps/accounts/security.py)).
- Toutes les actions admin sensibles auditées : suspend, compliance.review, disputes.decide,
  wallet.reconcile, admin.users.manage (vérifié dans chaque vue + `test_admin_can_create_supplier`
  qui asserte la ligne d'audit).

---

## 11. WebSocket admin

- `BaseAuthConsumer` ferme `4401` si non authentifié ([realtime/consumers.py:60](../backend/apps/realtime/consumers.py)).
- `DashboardConsumer` (canal `admin_dashboard`) ferme `4003` si `role != GENERAL_ADMIN`
  ([realtime/consumers.py:374-380](../backend/apps/realtime/consumers.py)) → un utilisateur normal
  ne peut pas écouter le flux admin. Couvert par `test_ws_routing.py` (suite existante).

---

## 12/13. Performance & Hardening

- Requêtes admin : `select_related/prefetch_related` sur les ViewSets clés
  (`ShipmentDisputeViewSet`, `ComplianceDocumentViewSet`, `AuditLogExportView`).
- IDOR : liste users auto-scopée (test), récupération d'autrui → 404 (test), KYC relationnel 404.
- Mass assignment : whitelist profil + `validate_role` création gérée (tests).
- Export audit borné à 2000 lignes ([views.py:1192](../backend/apps/accounts/views.py)).

---

## Tableau de synthèse des findings

| ID | Sévérité | Sujet | État |
|---|---|---|---|
| A-01 | HIGH (fonctionnel) | Annuaire admin plafonné à 20 users, recherche inopérante au-delà | **CORRIGÉ** (recherche serveur + câblage Flutter, 3 tests) |
| A-02 | LOW | Champ de recherche annonçant tél./ville non exposés | **CORRIGÉ** (libellé + recherche serveur) |
| R-01 | MED | `ProductViewSet.perform_destroy` = hard delete | **OBSERVATION** — à traiter avant d'exposer la modération produit en UI (non câblée aujourd'hui) |
| Sécurité authZ/escalade/IDOR/KYC/fintech/WS | — | — | **CONFORME, prouvé** |

---

## VERDICT FINAL

**ADMIN READY : ✅ Oui — pour le périmètre RÉELLEMENT exposé par la console.**

Justification :
- Aucune escalade de privilège, aucun IDOR, aucun mass-assignment : prouvé par 17 tests dédiés + 54 de non-régression.
- Capacités strictement nécessaires : l'admin ne peut ni se promouvoir, ni créer un super-admin,
  ni créditer un wallet sans step-up, ni exposer un KYC, ni muter une commande sans trace.
- Le seul défaut **bloquant fonctionnellement** (A-01) a été corrigé et prouvé.

**Réserves (non bloquantes pour la mise en service de la console actuelle) :**
1. **R-01** — implémenter le soft-delete produit **avant** d'ajouter un écran de modération produit à l'app admin.
2. Les capacités backend `suspend/unsuspend/create_managed_user` ne sont pas câblées dans l'UI :
   décision produit à prendre (les exposer ou les retirer pour réduire la surface).
3. Preuves non réalisables dans cet environnement (à exécuter en CI/prod) : test de charge 100 admins,
   `flutter build apk/ios`, E2E live bout-en-bout connecté à la prod.
