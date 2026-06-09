# Rapport de test E2E — Central Market / Marché CM
**Date :** 2026-06-02 · **Environnement :** local (backend Django live sur `http://127.0.0.1:8000`, SQLite, DEBUG, NotchPay **LIVE**)
**Méthode :** tests de bout en bout **réels** (vraies requêtes HTTP via `requests`, WebSocket réel via `websockets`, vrais fichiers image/vidéo/PDF, vérification de l'état **jusqu'en base** via l'ORM Django). Aucun résultat supposé : chaque ligne du rapport est adossée à une requête réellement exécutée (journal `qa_e2e/artifacts/calls.jsonl`) et un verdict (`results.jsonl`).

---

## 1. Résumé exécutif

| Indicateur | Valeur |
|---|---|
| Tests E2E exécutés | **128** |
| Réussites | **118** |
| Échecs / écarts | **10** |
| — dont **critiques** | **3** |
| — dont **majeurs** | **6** |
| — dont **mineurs** | **1** |

**Verdict global :** le cœur transactionnel (auth, JWT, escrow, idempotence, RBAC, cloisonnement IDOR, validation d'upload, litiges, temps réel WebSocket) est **robuste et bien sécurisé**. En revanche, **3 bugs critiques** bloquent des parcours utilisateurs essentiels : la **création de produit depuis l'app vendeur est cassée**, tout **produit créé avec photo devient invisible** au catalogue, et **l'annulation d'une commande bloque définitivement les fonds** de l'acheteur.

### Périmètre réellement couvert
Authentification & rôles, profil & KYC, produits & médias (image/vidéo/PDF), wallet (recharge LIVE + retrait), commandes & escrow, livraison, litiges & preuves, chat, notifications, WebSocket temps réel, administration, sécurité (IDOR/JWT/SQLi/XSS/traversal/headers/mass-assignment), performance.

### Limites assumées (argent réel & UI)
- **Recharge LIVE réalisée** (1000 FCFA, +237670766331) jusqu'à la création du lien de paiement NotchPay — **aucun argent déplacé** (le débit exige une validation Mobile Money sur le téléphone du titulaire ; le webhook NotchPay ne peut pas atteindre `localhost`).
- **Retrait / décaissement vendeur NON déclenchés** : `withdraw` et la libération d'escrow appellent `NotchPayDisbursementService.send_money` (virement réel). Les **gardes** (PIN, 2FA, solde, limites KYC) ont été testées intégralement car elles s'exécutent **avant** tout appel sortant.
- **Crédit wallet pour tester l'escrow** : amorçage **interne** via le service ledger de l'app (DB de test locale, sans argent réel ni provider).
- **UI Flutter** : non pilotée pixel-par-pixel (rendu `<canvas>` CanvasKit non fiable en automation) ; les contrats frontend↔backend ont été vérifiés en **rejouant les payloads exacts du code Flutter** contre l'API réelle.

---

## 2. Bugs CRITIQUES

### 🔴 C-1 — La création de produit depuis l'app vendeur est cassée (contrat frontend↔backend rompu)
- **Gravité :** Critique (fonction vendeur principale inutilisable)
- **Endpoint :** `POST /api/products/`
- **Frontend :** [supplier_product_edit_page.dart:91-106](frontend/app/lib/features/supplier/supplier_product_edit_page.dart#L91-L106)
- **Backend :** [apps/catalog/serializers.py](backend/apps/catalog/serializers.py) (`ProductSerializer`)
- **Repro :** se connecter comme SUPPLIER ; soumettre le formulaire de création produit de l'app vendeur (payload exact rejoué contre l'API).
- **Attendu :** `201 Created`.
- **Observé :** `400` — `{"category":["Type incorrect. Attendait une clé primaire, a reçu str."]}`.
- **Cause :** l'app envoie des **clés non alignées** au serializer :
  - `"category"` (chaîne) au lieu de `"category_name"` (le champ `category` est une PK entière → 400 immédiat) ;
  - `"min_qty"` / `"max_qty"` au lieu de `"min_order_qty"` / `"max_order_qty"` (ignorés → le backend exige ensuite ces champs pour un SUPPLIER) ;
  - mapping **inversé** des prix (`price_for_max_qty ← prix min`, `price_for_min_qty ← prix max`) ;
  - aucun champ image ni `is_active` envoyé.
- **Correction recommandée :** aligner le payload Flutter sur le contrat serializer (`category_name`, `min_order_qty`, `max_order_qty`, prix dans le bon sens, `is_active: true`), idéalement via un modèle de requête partagé/typé. Ajouter un test de contrat (schéma OpenAPI déjà exposé sur `/api/schema/`).

### 🔴 C-2 — Tout produit créé avec une image (multipart) devient `is_active=False` → invisible au catalogue
- **Gravité :** Critique (produits publiés jamais visibles des acheteurs)
- **Endpoint :** `POST /api/products/` (multipart/form-data)
- **Backend :** [apps/catalog/serializers.py](backend/apps/catalog/serializers.py) (`ProductSerializer`, `fields="__all__"` expose `is_active`) ; `ProductViewSet.perform_create` ne force pas `is_active`.
- **Repro / preuve E2E :**
  - multipart **sans** `is_active` → `is_active=False` ❌
  - multipart **avec** `is_active=true` → `is_active=True` ✔
  - JSON **sans** `is_active` → `is_active=True` ✔ (défaut modèle)
- **Attendu :** `is_active=True` par défaut quel que soit le type de requête (le défaut modèle est `True`).
- **Observé :** en `multipart`, un `BooleanField` **absent** est interprété par DRF comme **`False`** (héritage des cases à cocher HTML), ce qui écrase le défaut modèle. Le catalogue public filtre `is_active=True` → le produit n'apparaît jamais. Seul l'endpoint vidéo y échappe car il force `is_active=True`.
- **Correction recommandée :** retirer `is_active` des champs **écrivables** du serializer (le rendre `read_only`) et le piloter côté serveur (statut brouillon/publié explicite) ; ou définir `is_active = serializers.BooleanField(default=True, required=False)` explicitement. Aligner aussi le frontend (cf. C-1).

### 🔴 C-3 — Annulation acheteur : commande passée à CANCELLED mais escrow NON remboursé → fonds bloqués
- **Gravité :** Critique (perte d'accès aux fonds de l'acheteur)
- **Endpoint :** `POST /api/shipments/{id}/update_status/` `{ "status": "CANCELLED" }`
- **Backend :** [apps/logistics/views.py](backend/apps/logistics/views.py) (`update_status`, ~l.405-415, **pas de `transaction.atomic()`** ; `_can_update_status` l.120 autorise l'acheteur) vs [apps/orders/services.py](backend/apps/orders/services.py) (`refund_order_locked_funds` **interdit** l'acheteur).
- **Repro :** acheteur → annuler sa commande en cours (shipment `PICKUP_PENDING` → `CANCELLED`).
- **Attendu :** annulation **atomique** : soit (commande CANCELLED **et** escrow remboursé), soit aucun changement.
- **Observé (prouvé en base) :** réponse `400` (« Action de remboursement reservee a l'administration ou au transitaire ») **mais** `order.status=CANCELLED`, `escrow LOCAL status=LOCKED amount=8600`, wallet acheteur `locked` inclut toujours les 8600 FCFA **non remboursés**. Comme CANCELLED est terminal, le remboursement ne peut plus être rejoué → **argent bloqué définitivement**.
- **Cause double :** (1) `update_status` n'est pas transactionnel → `order.save(CANCELLED)` est commité avant l'échec du refund ; (2) **permissions contradictoires** : la vue autorise l'acheteur à annuler, mais le service de remboursement le lui interdit.
- **Correction recommandée :** envelopper toute la séquence d'annulation dans `transaction.atomic()` ; rendre `refund_order_locked_funds` autorisé pour l'acheteur dans le cadre d'une annulation (ou router l'annulation acheteur vers un service dédié qui rembourse) ; ajouter un test couvrant annulation→remboursement.

---

## 3. Bugs MAJEURS

### 🟠 M-1 — Inscription bloquée par un appel de géocodage **synchrone** (Nominatim/OpenStreetMap)
- **Endpoint :** `POST /api/auth/register/` (+ `/seller/`, `/driver/`)
- **Backend :** [serializers.py:489](backend/apps/accounts/serializers.py#L489) → [location_service.py:138](backend/apps/accounts/location_service.py#L138)
- **Observé :** latences mesurées **2557 / 3925 / 8592 ms** (variance typique d'un appel réseau). `create()` appelle `update_user_location(force=True)` → `geocode_with_nominatim()` → `urlopen` vers `nominatim.openstreetmap.org` (timeout **jusqu'à 10 s**) à **chaque** inscription.
- **Attendu :** inscription < 500 ms.
- **Impact :** fiabilité (un worker bloqué jusqu'à 10 s si OSM est lent/down), risque DoS, et l'API publique Nominatim limite à 1 req/s (échecs sous charge). `city` vide → géocode inutilement le centroïde du pays.
- **Correction :** déplacer le géocodage en tâche **Celery** asynchrone (post-inscription), avec timeout court et fallback ; ne jamais bloquer l'inscription dessus.

### 🟠 M-2 / M-3 — KYC acheteur : `PROOF_ADDRESS` et `SELFIE` annoncés valides mais **rejetés** par le serializer
- **Endpoint :** `POST /api/auth/kyc/submit/`
- **Backend :** `views.py:BuyerKycSubmitView.IDENTITY_DOC_TYPES` (CNI, CNI_VERSO, PASSPORT, **PROOF_ADDRESS**, **SELFIE**) vs `serializers.py:ComplianceDocumentSerializer.ALLOWED_DOC_TYPES` (= CERT_* + CNI/CNI_VERSO/PASSPORT/DRIVER_LICENSE — **sans** PROOF_ADDRESS ni SELFIE).
- **Repro :** acheteur → soumettre `doc_type=PROOF_ADDRESS` (ou `SELFIE`) + image.
- **Attendu :** `201`.
- **Observé :** `400` — `{"doc_type":["Type de document invalide."]}`.
- **Impact :** le wizard KYC acheteur (justificatif de domicile + selfie) échoue sur 2 de ses étapes.
- **Correction :** ajouter `PROOF_ADDRESS` et `SELFIE` à `ALLOWED_DOC_TYPES` (ou à un ensemble dédié partagé entre vue et serializer).

### 🟠 M-4 — Grossiste : impossible de créer un produit avec le flux conçu (prix requis malgré la dérivation)
- **Endpoint :** `POST /api/products/`
- **Backend :** `serializers.py:ProductSerializer.validate()` dérive `price_for_min_qty`/`price_for_max_qty` depuis `unit_price` pour un WHOLESALER, **mais** ces champs modèle sont **obligatoires** → la validation de champ échoue **avant** `validate()`.
- **Repro :** grossiste → créer un produit avec `available_qty` + `unit_price` seulement.
- **Attendu :** `201` (dérivation des prix).
- **Observé :** `400` — `{"price_for_min_qty":["Ce champ est obligatoire."],"price_for_max_qty":[...]}` ; la logique de dérivation est du **code mort**.
- **Correction :** rendre `price_for_min_qty`/`price_for_max_qty` `required=False` au niveau serializer (et les remplir dans `validate()`), ou les déclarer `read_only` et les calculer côté serveur.

### 🟠 M-5 — Driver App : WebSocket temps réel vers une route inexistante (`/ws/driver/`)
- **Frontend :** [Driver App app_config.dart:23](frontend/Driver%20App/app/lib/core/config/app_config.dart#L23) (`driverWsUrl = $wsBaseUrl/ws/driver/`)
- **Backend :** routes WS réelles = `/ws/notifications/`, `/ws/chat/<id>/`, `/ws/tracking/<id>/`, `/ws/dashboard/`, `/ws/events/` — **pas de `/ws/driver/`**.
- **Repro / preuve :** connexion WS à `/ws/driver/` → **500** ; la même connexion à `/ws/events/` → **acceptée**. 
- **Impact :** temps réel du livreur (notifications/tracking) non fonctionnel ; en bonus, l'absence de route renvoie un **500** (le routeur ASGI devrait répondre proprement).
- **Correction :** pointer la Driver App vers `/ws/events/` (comme les apps acheteur/vendeur) ou `/ws/tracking/<id>/` selon le besoin ; ajouter une route 404 propre côté ASGI.

### 🟠 M-6 — Fonction « blocage / suspension utilisateur » absente côté admin
- **Attendu (mission) :** l'admin peut bloquer/suspendre un utilisateur.
- **Observé :** aucun endpoint de blocage dans `accounts/views.py` (`UserViewSet` est `ReadOnlyModelViewSet`) et l'app admin ([admin_repository.dart](frontend/admin/project/lib/features/data/admin_repository.dart)) ne référence aucune action de blocage.
- **Correction :** exposer un endpoint admin `POST /api/users/{id}/block|suspend/` (gardé par `admin.users.manage`) qui bascule `is_active`/un statut de suspension + invalide les sessions JWT, et le câbler dans la console admin.

---

## 4. Bugs MINEURS

### 🟡 m-1 — Nom d'affichage forcé unique au profil (incohérent avec l'inscription)
- **Endpoint :** `POST /api/auth/profile/`
- **Backend :** `serializers.py:ProfileUpdateSerializer.validate_name` **rejette** un nom déjà utilisé par un autre utilisateur, alors que `RegisterSerializer.validate_name` a justement **retiré** ce contrôle (correctif anti-énumération H-005).
- **Observé :** `400` — `{"name":["Ce nom affiché est déjà utilisé."]}` en tentant un nom déjà pris.
- **Impact :** deux utilisateurs ne peuvent pas partager un nom d'affichage courant (« Jean ») ; léger vecteur d'énumération.
- **Correction :** supprimer le contrôle d'unicité sur `name` (first_name) au profil, par cohérence avec l'inscription.

---

## 5. Sécurité — synthèse (tout VERT sauf notes)

| Test | Résultat |
|---|---|
| Accès non authentifié aux endpoints protégés | ✅ 401/403 partout |
| JWT falsifié / expiré | ✅ rejeté (401) |
| Logout invalide le refresh (blacklist) | ✅ |
| Escalade de privilège à l'inscription (role=GENERAL_ADMIN, injection role) | ✅ rejetée/forcée BUYER |
| Mass-assignment (`is_superuser`/`role`/`kyc_level` via profil) | ✅ ignoré |
| IDOR (wallet, commande, produit, chat, litige, utilisateur) | ✅ 404/403 |
| Injection SQL (recherche produits, id de chemin, recherche chat) | ✅ neutralisée (ORM paramétré) |
| Upload polyglotte / mauvais magic bytes | ✅ rejeté |
| Path traversal | ✅ non servi |
| En-têtes de sécurité (X-Content-Type-Options, X-Frame-Options) | ✅ présents |
| PIN wallet (trivial/court rejeté, brute-force lockout, 2FA retrait) | ✅ |
| Cloisonnement des rôles (chaque app ne crée/sert que son rôle) | ✅ |

**Notes :**
- **XSS stocké** : l'API stocke le titre `<script>…` tel quel et le renvoie en **JSON** (`application/json`) — pas de rendu HTML côté serveur. La sécurité d'affichage incombe au frontend (les `Text` widgets Flutter sont sûrs). Recommandé : sanitiser/normaliser à l'affichage web admin si du HTML y est jamais rendu.
- **DEBUG=True (local uniquement)** : les pages 404/500 exposent des informations de debug. À garder strictement `False` en prod (déjà le cas via `marche-cm.env`).

---

## 6. Performance

| Endpoint | Médiane | Verdict |
|---|---|---|
| `GET /api/health/` | 33 ms | ✅ |
| `GET /api/products/` | 62 ms | ✅ |
| `GET /api/auth/me/` | 16 ms | ✅ |
| `GET /api/wallets/` | 49 ms | ✅ |
| `GET /api/orders/` | 62 ms | ✅ |
| `GET /api/admin/dashboard/` | 33 ms | ✅ |
| `GET /api/users/` | 53 ms | ✅ |
| **`POST /api/auth/register/`** | **2,5–8,6 s** | 🟠 cf. **M-1** (géocodage synchrone) |
| `POST /api/auth/login/` | ~1,1–1,5 s | ℹ️ PBKDF2 870k itérations (tradeoff sécurité, acceptable) |
| `POST /api/auth/password-change/` | ~3 s | ℹ️ deux hash PBKDF2 |

- **N+1 :** non observé aux volumes testés — `select_related`/`prefetch_related` en place sur `products`/`orders`.
- **Recommandation perf :** corriger M-1 (priorité) ; envisager Argon2id (déjà dans `PASSWORD_HASHERS`) si la latence d'auth devient un point de friction.

---

## 7. Incohérences Frontend ↔ Backend (récapitulatif)

| # | Incohérence | Frontend | Backend | Sévérité |
|---|---|---|---|---|
| 1 | Clés de création produit (`category`, `min_qty/max_qty`, prix inversés) | `supplier_product_edit_page.dart` | `ProductSerializer` | 🔴 C-1 |
| 2 | Produit multipart sans `is_active` → invisible | apps qui uploadent une image | `ProductSerializer` | 🔴 C-2 |
| 3 | Driver App → `/ws/driver/` inexistant | `Driver App/app_config.dart` | `realtime/routing.py` | 🟠 M-5 |
| 4 | KYC `PROOF_ADDRESS`/`SELFIE` annoncés mais rejetés | wizard KYC | vue vs serializer | 🟠 M-2/M-3 |
| 5 | Double système de notifications (`/ws/events/` vs `/ws/notifications/`) | apps → `/ws/events/` ✔ | `create_realtime_notification` → groupe `user_{id}` (`/ws/events/`) | ℹ️ cohérent en pratique ; `/ws/notifications/` peu utilisé |

---

## 8. Ce qui fonctionne très bien (points forts vérifiés)

- **Escrow & intégrité financière** : prix calculés **côté serveur** (override client `total_price=1` ignoré → total réel 5000), débit acheteur exact (5000 + 3600 transport), idempotence des recharges (rejouer la clé ne crée **aucun** doublon), double-entrée ledger.
- **Recharge LIVE réelle** : lien NotchPay créé (`https://pay.notchpay.co/…`), transaction `PENDING`, wallet **non crédité** avant webhook — comportement correct.
- **Sécurité** : JWT (tamper/expiry/blacklist), RBAC, IDOR, magic bytes, mass-assignment, SQLi — tout résiste.
- **Temps réel** : WebSocket authentifié JWT, le vendeur **reçoit réellement** un événement quand l'acheteur commande ; cloisonnement chat (participant vs non-participant).
- **Litiges** : ouverture + preuves **image et vidéo**, cloisonnement, résolution admin `REFUND_BUYER` → remboursement effectif.
- **Admin** : dashboard, validation KYC (→ APPROVED en base), export CSV d'audit, RBAC strict (non-admin 403 partout).
- **Chat** : append-only (DELETE 405), recherche cloisonnée par salon, messages texte/image/vidéo.

---

## 9. Recommandations priorisées

### 🚨 Urgent (avant mise en production)
1. **C-3** — rendre l'annulation atomique + autoriser le remboursement acheteur (risque : argent client bloqué).
2. **C-1** — réaligner le payload de création produit de l'app vendeur (parcours vendeur cassé).
3. **C-2** — `is_active` en `read_only`/défaut explicite (produits invisibles).
4. **M-1** — géocodage d'inscription en asynchrone (fiabilité/DoS).

### 🔶 Important
5. **M-2/M-3** — accepter `PROOF_ADDRESS`/`SELFIE` côté serializer (KYC acheteur).
6. **M-4** — débloquer la création produit grossiste.
7. **M-5** — corriger l'URL WebSocket de la Driver App.
8. **M-6** — implémenter le blocage/suspension utilisateur côté admin.

### 💡 Amélioration future
9. **m-1** — harmoniser l'unicité du nom d'affichage entre inscription et profil.
10. Nettoyer le préfixe mort `/api/catalog/` dans `RequestSizeLimitMiddleware` (`_UPLOAD_PATH_PREFIXES`) et **distinguer la limite vidéo (200 MB) de la limite image (5 MB)** — actuellement les uploads vidéo produit sont plafonnés à 50 MB par le `_global_max`.
11. Tests de contrat automatisés frontend↔backend à partir du schéma OpenAPI (`/api/schema/`).

---

## 10. Annexes
- **Harnais & artefacts :** dossier [qa_e2e/](qa_e2e/). Rejouer : démarrer le backend puis `python t1_auth.py … t10_security.py` depuis `qa_e2e/`.
- **Journaux bruts :** `qa_e2e/artifacts/calls.jsonl` (chaque requête/réponse/latence), `qa_e2e/artifacts/results.jsonl` (verdicts), `qa_e2e/artifacts/aggregated.json` (128 tests dédupliqués).
- **Médias de test réels :** `qa_e2e/media/` (JPEG, PNG, GIF, MP4, PDF, + fichiers de cas négatifs).
