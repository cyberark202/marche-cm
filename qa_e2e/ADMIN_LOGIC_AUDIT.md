# ADMIN_LOGIC_AUDIT — Marché CM

**Date :** 2026-06-20
**Périmètre :** Application ADMIN (Flutter `frontend/admin/project` + backend Django)
**Méthode :** preuve par exécution. Aucun audit antérieur réutilisé. Toute conclusion
est rattachée à un fichier:ligne, un endpoint testé ou une commande exécutée.

**Environnement de preuve :**
- Django 5.1.6, Python 3.12 (`python manage.py check` → *0 issue*).
- Suite complète : `python manage.py test` → **332 tests OK** (456 s) au lancement de l'audit.
- Après corrections : `apps.catalog` + `apps.accounts` → **260 tests OK**, 0 régression.
- Tests admin dédiés (créés) : `apps/accounts/test_admin_logic_audit.py` → **17 tests OK**.
- Soft-delete produit (créé) : `apps/catalog/test_product_soft_delete.py` → **4 tests OK**.
- `flutter analyze` (app admin) → **No issues found** (après câblage UI).

---

## 1. Cartographie réelle de l'ADMIN

Source unique des appels : [`admin_repository.dart`](../frontend/admin/project/lib/features/data/admin_repository.dart).

| Action admin (écran) | Endpoint API | Permission backend | Impact DB |
|---|---|---|---|
| Voir KPIs | `GET /api/admin/dashboard/` | `admin.dashboard.view` | aucun |
| Lister/chercher users | `GET /api/users/[?q=&role=]` | `IsAuthenticated` + scope admin | aucun |
| Détail user | `GET /api/users/{id}/` | scope admin | aucun |
| **Suspendre / réactiver** | `POST /api/users/{id}/suspend|unsuspend/` | `admin.users.suspend` | `is_suspended/is_active` + audit |
| **Créer compte géré** | `POST /api/users/create_managed_user/` | `admin.users.manage` | nouvel utilisateur + audit |
| File KYC | `GET /api/compliance-documents/` | relationnelle | aucun |
| Valider/rejeter doc | `POST /api/compliance-documents/{id}/review/` | `compliance.review` | `status/reviewed_by` + audit |
| Arbitrer litige | `POST /api/shipment-disputes/{id}/decide/` | `admin.disputes.decide` | escrow/refund + audit |
| Réconcilier wallet | `POST /api/wallets/reconcile/` | `wallet.reconcile` + **step-up 2FA** | transaction + audit |
| Escrow (lecture) | `GET /api/escrow/holds/` | scope admin | aucun |
| Journal d'audit | `GET /api/audit/events/`, `GET /api/admin/audit/export/` | `IsGeneralAdmin` / `audit.export` | aucun |

### Câblage console (corrections 2026-06-20)
- **Suspension/réactivation** : [`user_detail_page`](../frontend/admin/project/lib/features/users/user_detail_page.dart)
  — bandeau d'état + bouton + dialogue de motif, masqué pour les comptes admin.
- **Création de compte géré** : [`create_managed_user_page`](../frontend/admin/project/lib/features/users/create_managed_user_page.dart)
  — FAB sur l'annuaire ; rôles limités à Fournisseur/Grossiste/Livreur.
- **Modération produit** : désactivation via `perform_destroy` (soft-delete, cf. §5).

---

## 2. Authentification admin

| # | Élément | État | Preuve |
|---|---|---|---|
| 2.1 | Utilisateur normal sur endpoint admin | **403/404** | `test_buyer_forbidden_on_every_admin_endpoint` (8 endpoints) OK |
| 2.2 | Anonyme sur endpoint admin | **401/403** | `test_anonymous_forbidden_on_admin_endpoints` OK |
| 2.3 | JWT falsifié | **401** | `test_forged_jwt_rejected` OK |
| 2.4 | Admin légitime | **200** | `test_admin_dashboard_ok`, `test_admin_audit_events_ok_buyer_forbidden` OK |
| 2.5 | Token après suspension | **rejeté** | `test_existing_access_token_rejected_after_suspension` OK |

**Verdict authentification : conforme.**

---

## 3. Gestion des utilisateurs

**Problème A-01 (HIGH fonctionnel) — CORRIGÉ.** `UserViewSet` n'avait aucune recherche serveur :
`users_page` chargeait la 1ʳᵉ page (20 lignes, `PAGE_SIZE=20`) et filtrait côté client → tout
utilisateur au-delà du 20ᵉ était invisible/introuvable.
- Backend [`UserViewSet.get_queryset`](../backend/apps/accounts/views.py) : recherche serveur
  admin `?q=` (username/email/first_name/reference_code) + filtre `?role=`. Scope non-admin
  appliqué **avant** tout filtre → anti-IDOR préservé.
- Frontend : `AdminRepository.users({query})` + recherche serveur dans `users_page`.
- Preuve : `test_admin_server_side_search_beyond_first_page`,
  `test_admin_search_by_reference_code`, `test_search_query_does_not_break_non_admin_scoping` → **OK**.

**Problème A-02 (LOW) — CORRIGÉ.** Le champ promettait téléphone/ville non exposés → libellé corrigé
en « Nom, email, code réf… ».

### Anti-escalade (prouvé)
| Cas | Attendu | Preuve |
|---|---|---|
| buyer → admin via profil | **ignoré** | `test_buyer_cannot_self_promote_via_profile` OK |
| PATCH rôle via `/api/users/{id}/` | **405** | `test_userviewset_is_read_only_no_role_patch` OK |
| Admin crée un GENERAL_ADMIN via API | **400 refus** | `ManagedUserCreateSerializer.validate_role` ; `test_admin_cannot_create_general_admin_via_api` OK |
| Admin se suspend lui-même | **400 refus** | `test_admin_cannot_suspend_self` OK |
| Admin suspend un autre admin | **400 refus** | `test_admin_cannot_suspend_another_admin` OK |

Le profil ([`ProfileUpdateSerializer`]) n'expose ni rôle, ni solde, ni flags → pas de mass-assignment.
**Verdict : pas d'escalade de privilège possible.**

---

## 4. KYC / Compliance

| Point | État | Preuve |
|---|---|---|
| Stockage privé KYC | **URL S3 signée, expirante** | [`config/storages.py`](../backend/config/storages.py) ; `AWS_DEFAULT_ACL=None` |
| Admin ne peut PAS rendre un KYC public | **garanti** | `get_file_url` → backend privé ; aucun chemin `products/`/`avatars/` pour un doc compliance |
| Autorisation lecture doc | **relationnelle, 404 anti-énumération** | `ComplianceDocumentViewSet.get_queryset` |
| Review réservée admin | **`compliance.review`** | buyer→403 prouvé (test 2.1) |
| Validation fichier (magic bytes, extension fake) | présent | `validate_uploaded_file` + `test_compliance_upload_mime.py` |

**Verdict KYC : conforme.**

---

## 5. Produits / Vendeurs / Commandes

**R-01 (réévalué HIGH) — CORRIGÉ.** `ProductViewSet.perform_destroy` faisait un **hard delete**.
Or `Order.product` est **`on_delete=CASCADE`** ([orders/models.py:40](../backend/apps/orders/models.py)) :
supprimer un produit **supprimait en cascade toutes les commandes liées** (y compris payées/escrow),
détruisant l'historique financier.
- Correction [`catalog/views.py`](../backend/apps/catalog/views.py) `perform_destroy` : **soft-delete**
  (`is_active=False`) + audit `catalog.product.deactivate` + broadcast. Le produit disparaît du
  catalogue public (`get_queryset` filtre `is_active=True`) mais commandes/escrows préservés.
- Preuve `apps/catalog/test_product_soft_delete.py` (4 tests) :
  `test_admin_delete_is_soft_and_preserves_order`, `test_seller_delete_is_soft`,
  `test_deactivated_product_absent_from_public_catalogue`, `test_non_owner_non_admin_cannot_delete` → **OK**.

**Vendeurs :** activation pilotée par certifications (`_sync_business_user_verification`) ;
suspension via le module utilisateur (désormais câblé).
**Commandes :** intervention admin uniquement via décision de litige (escrow), **journalisée**.

---

## 6. Wallet / Fintech (critique)

| Invariant | État | Preuve |
|---|---|---|
| `wallet.reconcile` réservé admin | oui | buyer→403 (test 2.1) |
| **Step-up 2FA obligatoire** même admin | oui | `test_admin_reconcile_requires_stepup` → 403 sans code. OK |
| Réconciliation limitée aux PENDING | oui | garde 409 ([wallets/views.py:1407](../backend/apps/wallets/views.py)) |
| Webhook : signature HMAC + anti-replay 5 min + idempotency | oui | [wallets/views.py:232-296, 539-588](../backend/apps/wallets/views.py) |
| Invariant Σdébits = Σcrédits | **prouvé** | `apps/ledger/test_invariants_audit.py` |

**Verdict fintech : conforme.**

---

## 7. Litiges, Journal d'audit, WebSocket

- Décision litige : `admin.disputes.decide` + `resolution_note` obligatoire + `write_audit_log`.
- Audit : métadonnées passées par `sanitize_audit_metadata` (PII/secrets supprimés).
- WS admin : `BaseAuthConsumer` ferme `4401` (non-auth) ; `DashboardConsumer` ferme `4003`
  si `role != GENERAL_ADMIN` ([realtime/consumers.py:374-380](../backend/apps/realtime/consumers.py)).

---

## Tableau de synthèse des findings

| ID | Sévérité | Sujet | État |
|---|---|---|---|
| A-01 | HIGH (fonctionnel) | Annuaire admin plafonné à 20 users, recherche inopérante au-delà | **CORRIGÉ + prouvé (3 tests)** |
| A-02 | LOW | Champ de recherche annonçant tél./ville non exposés | **CORRIGÉ** |
| R-01 | HIGH (réévalué) | `perform_destroy` hard delete → cascade destructive sur commandes | **CORRIGÉ + prouvé (4 tests)** |
| C-01 | — (décision produit) | suspend/unsuspend/create_managed_user non câblés en UI | **CÂBLÉS dans la console** |
| Sécurité authZ/escalade/IDOR/KYC/fintech/WS | — | — | **CONFORME, prouvé** |

---

## VERDICT FINAL

**ADMIN READY : ✅ Oui.**

Justification :
- Aucune escalade de privilège, aucun IDOR, aucun mass-assignment : prouvé par 17 tests dédiés
  + 260 de non-régression (catalog+accounts), 0 régression.
- Capacités strictement nécessaires : l'admin ne peut ni se promouvoir, ni créer un super-admin,
  ni créditer un wallet sans step-up, ni exposer un KYC, ni détruire l'historique financier d'une commande.
- Les 3 défauts identifiés (A-01, A-02, R-01) sont **corrigés et prouvés** ; les capacités de
  modération (suspension + création de compte géré) sont désormais **câblées dans la console**.

**Réserves (non bloquantes, environnement) :** test de charge 100 admins, `flutter build apk/ios`,
E2E live bout-en-bout prod — à exécuter en CI/prod (non réalisable ici).

⚠️ **Modifications non committées** — commit + redéploiement requis (sinon écrasées au prochain CI).
