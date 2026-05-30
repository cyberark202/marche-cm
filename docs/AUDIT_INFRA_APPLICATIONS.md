# Audit infra — Applications Marché CM

Date : 2026-05-30
Portée : les 4 applications Flutter + la nouvelle console admin, et leur couplage au backend Django.
Auteur : passe « console admin dédiée + retrait admin des autres apps + audit ».

---

## 0. Addendum — 2e passe (corrections + écrans manquants + sécurité)

État `flutter analyze` **après corrections** : `Clients` ✅ 0 · `app` ✅ 0 · `Driver App` ✅ 0 · `admin` ✅ 0. Tests : `app` ✅, `Driver App` ✅, `admin` ✅.

**Défauts pré-existants corrigés :**
- `Clients` : suppression de `lib/firebase_options.dart` (orphelin, Firebase non déclaré → 6 erreurs) ; `feed_page.dart` `ProfileHubPage(onRefresh:)` → `const ProfileHubPage()`.
- `app` : `test/widget_test.dart` réécrit (référençait l'ancien dashboard admin supprimé + `scaffoldKey` manquant) ; garde `mounted` ajoutée dans `dispute_detail_page.dart` (`use_build_context_synchronously`).
- `Driver App` : `test/widget_test.dart` réécrit (pointait `package:app/main.dart` + `MyApp`).
- Lints `info` auto-corrigés via `dart fix --apply` (app 32, Clients 9, Driver 31).

**Écrans catalogue manquants :** couverture quasi-complète (Acheteur=Clients, Vendeur=app, Livreur=Driver App, Admin=app dédiée). Seul écart à valeur : **signature manuscrite KYC (écran 46)** → implémentée dans `app/buyer_kyc_page.dart` (CustomPaint, sans dépendance) + consentement CGU. Le mapping d'upload KYC a été **corrigé** (`doc_type`/`file`/`CNI_VERSO` au lieu de `certificate_type`/`document`). « Variantes de logo » (50) = artefact de marque, non implémenté (hors scope fonctionnel).

**Livrables associés :** `PENTEST_BACKEND.md` (pen-test statique OWASP/ASVS), `INCOHERENCES_BACKEND_FRONTEND.md`, `DEPLOIEMENT_V1_PRODUCTION.md`.

---

## 1. Inventaire des applications

| App | Package | Rôles servis | Firebase | État |
|-----|---------|--------------|----------|------|
| `frontend/app` | `marche_cm` | Acheteur, Fournisseur, Grossiste, Transitaire *(plus admin — retiré)* | Oui | Actif |
| `frontend/Clients` | `clients_app` | Acheteur / client | **Non (dép. absente)** | Actif, voir §5 |
| `frontend/Driver App/app` | `driver_app` | Livreur / transitaire | Oui | Actif |
| `frontend/admin/project` | `project` | **GENERAL_ADMIN uniquement (nouveau)** | Non (volontaire) | Nouveau, `flutter analyze` = 0 issue |

La console admin est désormais une application **autonome** : un compte non‑`GENERAL_ADMIN` est refusé à la connexion et au restore de session.

---

## 2. Console admin (nouvelle) — `frontend/admin/project`

### 2.1 Écrans livrés (catalogue 32→42, + 01/02)

| # Catalogue | Écran | Fichier | Endpoint(s) backend |
|---|---|---|---|
| 01 | Splash | `features/splash/admin_splash.dart` | — |
| 02 | Login admin | `features/auth/admin_login_page.dart` | `POST /api/auth/login/`, `GET /api/auth/me/` |
| 32 | Tableau de bord | `features/dashboard/admin_dashboard_page.dart` | `GET /api/admin/dashboard/` + agrégats `orders`, `shipment-disputes`, `escrow/holds`, `users/online` |
| 33 | Utilisateurs | `features/users/users_page.dart` | `GET /api/users/` |
| 34 | Fiche utilisateur | `features/users/user_detail_page.dart` | `GET /api/users/{id}/`, `GET /api/compliance-documents/` |
| 35 | Conformité KYC | `features/compliance/kyc_queue_page.dart` | `GET /api/compliance-documents/`, `GET /api/users/` |
| 36 | Revue document | `features/compliance/document_review_page.dart` | `POST /api/compliance-documents/{id}/review/` |
| 37 | Litiges | `features/disputes/disputes_page.dart` | `GET /api/shipment-disputes/` |
| 38 | Arbitrage | `features/disputes/arbitration_page.dart` | `GET /api/shipment-disputes/{id}/`, `POST /api/shipment-disputes/{id}/decide/` |
| 39 | Réconciliation | `features/wallet/reconciliation_page.dart` | `GET /api/escrow/holds/`, `POST /api/auth/sensitive-action/request/`, `POST /api/wallets/reconcile/` |
| 40 | Audit & journaux | `features/audit/audit_page.dart` | `GET /api/audit/events/`, `GET /api/admin/audit/export/` (CSV) |
| 41 | Configuration | `features/config/configuration_page.dart` | `GET /api/ui-config/` (lecture seule) |
| 42 | Profil admin | `features/profile/admin_profile_page.dart` | `GET /api/auth/me/`, `POST /api/auth/logout/` |

Navigation : `AdminShell` (Accueil · Comptes · Litiges · Wallet · Profil), conforme au pied de page de l'écran 32. Audit / Configuration / Fiche utilisateur / Revue / Arbitrage sont atteints par push.

### 2.2 Sécurité reprise à l'identique des apps de production
- `SecureDioClient` : device binding (`X-Device-ID`), `X-Correlation-ID`, `X-Request-Nonce`, `X-Request-Timestamp`, refresh JWT réactif sur 401 (completer anti‑refresh concurrent), sanitisation des erreurs serveur.
- `TokenRepository` : tokens dans Android Keystore / iOS Keychain (jamais SharedPreferences). **Namespace de clés distinct** (`admin.*`) pour ne pas entrer en collision avec une session acheteur/vendeur sur le même appareil.
- `AppConfig` : HTTPS forcé en release (crash fast sinon). Même base URL que les autres apps → même backend.
- Rafraîchissement proactif du JWT 60 s avant expiration (`AdminSessionStore`).

### 2.3 Garde‑fous métier
- **Réconciliation wallet** : le flux respecte la step‑up 2FA exigée par le backend (`wallet.reconcile`) — demande de code par e‑mail puis envoi `challenge_token` + `verification_code`. Aucune opération financière sans 2FA.
- **Arbitrage** : décisions limitées à `REFUND_BUYER` / `RELEASE_SELLER` / `SPLIT`, `resolution_note` obligatoire (contrat backend respecté).
- **Revue KYC** : validation bloquée tant que la checklist n'est pas complète.
- **Configuration** : lecture seule (les commissions/sécurité se changent côté backend, audité) — pas de mutation exposée.

### 2.4 Limites assumées (dépendantes du backend)
- Pas d'endpoint listant les transactions PENDING à l'échelle plateforme → la réconciliation se fait par **ID de transaction externe** saisi manuellement (honnête vs capacités backend).
- Montant « séquestre concerné » d'un litige affiché en best‑effort (le modèle `ShipmentDispute` n'expose pas de champ montant direct ; dérivé de la commande/escrow quand disponible).
- KPIs GMV/commission calculés côté client à partir de `orders`/`escrow/holds` (le backend n'expose pas encore d'agrégat GMV admin dédié — cf. §6).

---

## 3. Couverture backend / RBAC

Tous les endpoints admin sont protégés **deny-by-default** côté backend :
- `admin.dashboard.view`, `audit.export`, `admin.users.manage`, `compliance.review`, `admin.disputes.decide`, `wallet.reconcile` passent par `_require_action` / `has_action_permission` (enum RBAC `GENERAL_ADMIN`, pas le flag Django `is_staff`).
- `UserViewSet` / `ComplianceDocumentViewSet` : autorisation **relationnelle** (BOLA/IDOR — OWASP A01), 404 anti‑énumération pour les non‑admins.
- `metrics/` Prometheus : `IsGeneralAdmin`.

La console front ne fait donc que consommer des endpoints déjà verrouillés ; aucune élévation de privilège n'est introduite côté client.

---

## 4. Retrait de l'admin des autres apps (effectué)

| Action | Fichier | Effet |
|---|---|---|
| Suppression | `app/lib/features/admin/admin_dashboard_page.dart` + `managed_user_creation_page.dart` | Écrans admin retirés (étaient du **code mort** — aucun import) |
| Édition | `app/lib/features/wallet/wallet_page.dart` | Retrait du bloc « Réconciliation » réservé `generalAdmin` + helpers + import devenu inutile |
| Édition | `Clients/lib/features/wallet/wallet_page.dart` | Idem |

Empreinte git stricte (hors `admin/project`) : 2 wallets modifiés + 2 fichiers supprimés.

**Conservé volontairement** (ce ne sont PAS des écrans admin) :
- l'enum `UserRole.generalAdmin` (modèle de rôle partagé, utilisé dans des `switch`),
- les vues de litige (`shipment_disputes_page`, `dispute_detail_page`…) partagées acheteur/vendeur/transitaire,
- le gating de visibilité par rôle dans `innovation_hub_page` / `role_backend_data_page`.

Retirer ces éléments aurait été du sur‑périmètre et aurait cassé des `switch`/compilations.

Vérification non‑régression : `flutter analyze` sur `app` et `Clients` — **aucune erreur nouvelle** introduite par ces changements (les fichiers édités ne produisent aucun diagnostic).

---

## 5. Problèmes infra PRÉ-EXISTANTS détectés (non introduits par cette passe)

> Ces points existaient avant l'intervention. Listés par sévérité pour suite à donner.

### 🔴 Bloquant compilation — `frontend/Clients`
- `lib/firebase_options.dart` référence `package:firebase_core/firebase_core.dart` **alors que `firebase_core` n'est pas dans `Clients/pubspec.yaml`** → 6 erreurs d'analyse. Soit ajouter les dépendances Firebase, soit supprimer `firebase_options.dart` (et ses usages) si Clients ne fait pas de push.
- `lib/features/feed/feed_page.dart:572` : paramètre nommé `onRefresh` inexistant → 1 erreur.

### 🟠 Tests cassés
- `app/test/widget_test.dart:28` construit `const MarcheCmApp()` sans le paramètre requis `scaffoldKey` → test ne compile pas. (La console admin a, elle, un smoke test vert.)

### 🟡 Hygiène (info lints)
- ~50 `info` `prefer_const_constructors` / `unnecessary_brace_in_string_interps` sur `app` (qualité, non bloquant).

### 🟡 Cohérence projet
- L'app admin garde le nom de package par défaut `project`. Sans impact fonctionnel (imports relatifs), mais à renommer (`marche_cm_admin`) pour la lisibilité/CI — implique de mettre à jour `package:project/...` dans `test/`.

---

## 6. Recommandations (next steps)

1. **Clients** : trancher Firebase (ajouter deps ou retirer `firebase_options.dart`) et corriger `feed_page` — actuellement non compilable en l'état.
2. **app** : réparer `widget_test.dart` (passer un `scaffoldKey`) pour réactiver la CI tests.
3. **Backend (optionnel, pour enrichir l'admin)** :
   - endpoint d'agrégat GMV/commission admin (évite le calcul client),
   - endpoint listant les transactions `PENDING` plateforme (réconciliation par liste plutôt que saisie d'ID),
   - exposer un montant séquestre directement sur `ShipmentDispute` (DRY pour l'arbitrage).
4. **Renommer** le package admin et ajouter une icône/splash brandée.
5. **CI** : ajouter `flutter analyze` de `admin/project` au pipeline (déjà vert).

---

## 7. Verdict

- Console admin : **11 écrans livrés, câblés aux endpoints dédiés, sécurité de prod reprise, `analyze` vert, smoke test vert**.
- Retrait admin des autres apps : **fait, sans régression**.
- Aucune infrastructure existante cassée par cette passe ; les seuls défauts restants sont **pré‑existants** et documentés ci‑dessus.
