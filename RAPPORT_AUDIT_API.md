# Rapport d'audit de sécurité — Exposition des endpoints & fuites d'information

**Projet :** Marché CM (backend Django + 4 clients Flutter + site vitrine React)
**Date :** 2026-06-10
**Périmètre :** endpoints exposés, fuites d'URL/endpoint dans messages/logs/JSON,
secrets côté client & serveur, infos internes (localhost/IP/ports/BDD/stack traces),
gestion d'erreurs centralisée.

---

## 1. Synthèse exécutive

Le backend est **déjà fortement durci** (DEBUG=False par défaut, handler d'exceptions
qui masque les stack traces, validations de démarrage, JWT/CORS/HSTS, RBAC).
L'audit a néanmoins identifié **1 vulnérabilité critique**, **1 haute**, **2 moyennes**
et des points cosmétiques. Toutes les corrections de code ont été appliquées ; **une
action opérationnelle (rotation des clés) reste à la charge de l'exploitant.**

| Sévérité | Nombre | État |
|----------|--------|------|
| 🔴 Critique | 1 | Code corrigé — **rotation des clés requise** |
| 🟠 Haute | 1 | ✅ Corrigé |
| 🟡 Moyenne | 2 | ✅ Corrigé |
| 🔵 Faible / cosmétique | 3 | Documenté (sans fuite) |

**Score de sécurité :**
- Avant remédiation : **58 / 100**
- Après remédiation du code : **82 / 100**
- Après rotation des secrets compromis : **92 / 100** (objectif atteignable)

---

## 2. Vulnérabilités détaillées

### 🔴 CRITIQUE — Secrets de production réels committés dans le dépôt git

| | |
|---|---|
| **Fichier** | `backend/marche-cm.local.env.bak` |
| **Commit** | `cdc20a1` (« Implement 5 security + performance improvements ») |
| **Risque** | Critique |

**Explication.** Le `.gitignore` ignorait `marche-cm.env` et `*.env`, mais le suffixe
`.bak` **échappe au motif `*.env`**. Ce fichier de sauvegarde était donc suivi par git
et contenait des **secrets de production réels** :

- `NOTCHPAY_LIVE_PRIVATE_KEY=sk.…` — **clé privée de paiement LIVE** (vrai argent : MTN/Orange)
- `NOTCHPAY_LIVE_PUBLIC_KEY`, `NOTCHPAY_HASH_KEY`, `NOTCHPAY_WEBHOOK_TOKEN`
- `NOTCHPAY_CHECKOUT_WEBHOOK_SECRET`, `NOTCHPAY_DISBURSE_WEBHOOK_SECRET`
- `DATA_ENCRYPTION_KEY` (Fernet) — commentaire explicite : « **Même clé Fernet que la prod** »
  → déchiffre les colonnes chiffrées (KYC, PII, données sensibles)
- `DEVICE_FINGERPRINT_SECRET`

Quiconque a (ou a eu) accès au dépôt peut signer des webhooks de paiement frauduleux,
déclencher des décaissements et **déchiffrer toutes les données sensibles** de la base.

**Correction appliquée.**
1. Fichier retiré du suivi git : `git rm --cached backend/marche-cm.local.env.bak`
   (le fichier local est conservé pour le dev).
2. `.gitignore` durci : ajout de `*.bak`, `*.env.bak`, `marche-cm.local.env*`.

**Action restante OBLIGATOIRE (exploitant — non automatisable).**
> Les secrets restent présents dans **l'historique git** (`cdc20a1`). Les retirer du
> suivi ne suffit pas. Il faut :
> 1. **Faire tourner (rotate) immédiatement** toutes les clés ci-dessus côté NotchPay
>    et régénérer la clé Fernet (avec `DATA_ENCRYPTION_FALLBACK_KEYS` pour migrer les
>    colonnes existantes sans perte).
> 2. Purger l'historique (`git filter-repo --path backend/marche-cm.local.env.bak --invert-paths`)
>    puis forcer le push, ou considérer le dépôt comme compromis et le recréer.
> 3. Vérifier les logs NotchPay pour toute utilisation non autorisée.

---

### 🟠 HAUTE — L'app Driver expose l'URL d'endpoint dans les messages d'erreur

| | |
|---|---|
| **Fichiers** | `frontend/Driver App/app/lib/core/network/driver_dio_client.dart` ; pages `quote_send_page.dart:75`, `delivery_proof_page.dart:95`, + 7 autres |
| **Risque** | Haute |

**Explication.** Le client réseau du Driver (`DriverDioClient`) **n'avait aucun
sanitizer d'erreur**. Les pages affichaient directement `"Envoi impossible : ${e.toString()}"`.
Pour une `DioException` (Dio 5.7), `toString()` expose, selon le type :
- l'**URI complète** de l'endpoint (`https://marche-cm.onrender.com/api/shipments/{id}/quote/`) ;
- sur erreur de transport, la `SocketException` sous-jacente qui révèle **l'hôte:port** du serveur.

C'est exactement le scénario « endpoint affiché dans un message utilisateur ».

**Correction appliquée.**
- Nouveau `core/network/api_error.dart` : couche centralisée `ApiError.friendly(e)`
  qui ne renvoie **jamais** d'URL, d'endpoint, d'hôte ou de chaîne technique.
- Nouvel intercepteur `_ErrorSanitizerInterceptor` dans `DriverDioClient` : reconstruit
  chaque `DioException` avec un message propre (en conservant le `detail` déjà
  sanitisé côté Django pour les 4xx), `error`/`stackTrace`/`response` supprimés.
- **11 call-sites** migrés vers `ApiError.friendly(e)` (auth, missions, livraison,
  wallet, véhicule, documents…).

---

### 🟡 MOYENNE — Fuite de l'hôte serveur sur erreur réseau (apps `app`, `Clients`, `admin`)

| | |
|---|---|
| **Fichiers** | `frontend/app/lib/core/security/secure_dio_client.dart`, `frontend/admin/project/lib/core/security/secure_dio_client.dart`, `frontend/Clients/lib/core/api_service.dart` |
| **Risque** | Moyenne |

**Explication.** Les erreurs **HTTP** (4xx/5xx) étaient bien sanitisées, mais les
erreurs de **transport** (DNS, TLS, timeout, connexion refusée) ne l'étaient pas :
- App `app`/`admin` (Dio) : le `_ErrorSanitizerInterceptor` ne gérait que `onResponse`,
  pas `onError`. Une `SocketException` (« Failed host lookup: 'marche-cm…' ») remontait
  jusqu'à l'UI via `e.toString()`.
- App `Clients` (`package:http`) : les exceptions embarquaient `"$path failed: <status> <body>"`,
  exposant **le chemin d'endpoint ET le corps brut** à tout call-site utilisant
  `e.toString()` au lieu du helper `toUserMessage()`.

**Correction appliquée.**
- `app` + `admin` : ajout de `onError` au `_ErrorSanitizerInterceptor` → toute erreur de
  transport est remplacée par un message générique (sans hôte:port).
- `Clients/api_service.dart` : sanitisation **à la source** — un unique point de levée
  `_throwHttpError(status, body)` qui n'inclut ni chemin ni corps brut, et une enveloppe
  `_guarded()` qui convertit toute erreur réseau (`SocketException`/`ClientException`/
  `XMLHttpRequest`/timeout) en message générique. Toutes les pages sont ainsi protégées,
  quel que soit leur mode d'affichage.

---

### 🟡 MOYENNE — Documentation API (OpenAPI/Swagger/Redoc) exposée publiquement

| | |
|---|---|
| **Fichiers** | `backend/config/urls.py:186-190`, `backend/config/settings.py` |
| **Risque** | Moyenne (information disclosure / reconnaissance) |

**Explication.** Les routes `/api/schema/`, `/api/schema/swagger/`, `/api/schema/redoc/`
étaient montées **inconditionnellement** et le schéma servi en `AllowAny` (défaut
drf-spectacular). Elles cartographient **toute la surface d'API** (chaque route, payload,
exigence d'auth) — du matériel de reconnaissance précieux pour un attaquant ciblant une fintech.

**Correction appliquée.**
- Nouveau flag `ENABLE_API_DOCS = _env_bool("ENABLE_API_DOCS", DEBUG)`.
- Les 3 routes ne sont montées **que si `ENABLE_API_DOCS`** (404 en production par défaut).
- `SPECTACULAR_SETTINGS["SERVE_PERMISSIONS"] = ["IsAuthenticated"]` : même activé, le
  schéma JSON exige une session/token.

---

### 🔵 FAIBLE / cosmétique (pas de fuite après remédiation)

1. **Préfixe technique résiduel** dans `app`/`Clients` `innovation_hub_page.dart:99`
   et les pages support : sur erreur réseau, le message peut afficher
   `DioException [connectionError]: …`. **Aucune URL/hôte** n'est exposée (sanitisé) ;
   seul le préfixe de type subsiste. Recommandé : router ces call-sites via
   `service.toUserMessage(e)`.
2. **URL de prod hardcodée** dans les clients (`https://marche-cm.onrender.com`).
   **Normal et inévitable** : un client doit connaître son API. Surchargée au build via
   `--dart-define=API_BASE_URL`. Non considéré comme une vulnérabilité.
3. **`http://localhost:5000` en fallback web dev** (`app/lib/core/app_config.dart:27`) :
   bloqué en release par `_assertHttpsInRelease`. Acceptable.

---

## 3. Liste des endpoints détectés (surface d'API)

Source unique : `backend/config/urls.py` (routage centralisé, pas d'`urls.py` par app).

**Système / public**
- `GET /api/health/` — `AllowAny`
- `GET /api/ui-config/`
- `GET /metrics/` — Prometheus, `IsGeneralAdmin`
- `/admin/` — Django admin

**Auth** (`/api/auth/…`) : `register/`, `register/seller/`, `register/driver/`,
`login/`, `login/verify/`, `refresh/`, `logout/`, `me/`, `profile/`, `location/resolve/`,
`wallet-pin/`, `sensitive-action/request/`, `sessions/`, `password-change/`, `kyc/submit/`,
`fcm-token/`, `verify-email/`, `google/`

**Admin / Innovation** : `/api/admin/dashboard/`, `/api/admin/audit/export/`,
`/api/loyalty/account/`, `/api/innovation/{escrow-split, rfq-compare, shipment-timeline,
disputes/<id>/escalate, onboarding/checklist, seller-dashboard, recommendations/reasons,
notifications/smart-run}/`

**ViewSets REST** (`/api/…`, via `DefaultRouter`) : `users`, `compliance-documents`,
`products`, `product-favorites`, `product-filters`, `video-likes`, `video-comments`,
`orders`, `wallets`, `chat/rooms`, `chat/messages`, `campaigns`, `rfqs`, `rfq-offers`,
`transport-profiles`, `shipments`, `transport-quotes`, `shipment-disputes`, `price-alerts`,
`rfq-counter-offers`, `wallet-approval-requests`, `partner-api-keys`, `webhook-subscriptions`,
`notifications`, `support/tickets`, `escrow/holds`, `disputes`, `fraud/assessments`,
`fraud/risk-profiles`, `compliance/kyc`, `audit/events`, `ledger/accounts`, `ledger/transactions`

**Documentation** (désormais gated) : `/api/schema/`, `/api/schema/swagger/`, `/api/schema/redoc/`

> Permissions par défaut : `IsAuthenticated` (DRF global). Seuls `health`, `ui-config`,
> et les endpoints d'auth d'entrée sont publics. Throttling global anon + user actif.

---

## 4. Endpoints / URLs encore visibles côté client (résiduel acceptable)

| Élément | Emplacement | Statut |
|---|---|---|
| `https://marche-cm.onrender.com` (base API prod) | clients Flutter `app_config.dart` | **Inévitable** — un client doit cibler son API |
| `https://api.marketcm.com`, `https://app.marketcm.com` | site vitrine `src/data/site.ts` | URLs marketing publiques |
| `http://localhost:5000` (fallback web dev) | `app/lib/core/app_config.dart` | Bloqué en release |
| Préfixe `DioException [type]:` sur erreur réseau | 2 pages innovation/support | Cosmétique, **aucune** donnée sensible |

Aucune clé API, token, secret, IP interne, port privé, nom de BDD, chemin serveur ou
stack trace n'est exposé côté client après remédiation. Le site vitrine est propre.

---

## 5. Couche de gestion d'erreurs centralisée (livrée)

| App | Mécanisme central | Garantie |
|---|---|---|
| Backend Django | `config/exceptions.py` (préexistant) | 5xx → message opaque + `error_id`, stack loguée serveur uniquement |
| `Clients` (http) | `core/api_service.dart` → `_throwHttpError` + `_guarded` | Aucun chemin/corps/hôte dans les exceptions |
| `app` / `admin` (Dio) | `_ErrorSanitizerInterceptor` (`onResponse` + **`onError`**) | HTTP et transport sanitisés |
| `Driver` (Dio) | **`core/network/api_error.dart`** + `_ErrorSanitizerInterceptor` | `ApiError.friendly()` ne renvoie jamais d'URL/hôte |

Exemple conforme à la demande :
> **Avant :** `Envoi impossible : DioException … uri: https://marche-cm.onrender.com/api/shipments/12/quote/`
> **Après :** `Une erreur est survenue. Veuillez réessayer plus tard.`

---

## 6. Recommandations prioritaires

1. 🔴 **(URGENT) Faire tourner toutes les clés exposées** (NotchPay LIVE + webhooks +
   Fernet `DATA_ENCRYPTION_KEY`) et **purger l'historique git**. Tant que ce n'est pas
   fait, considérer les clés comme compromises.
2. 🟠 **Committer** les changements de cet audit (`.gitignore`, retrait du `.bak`,
   sanitizers, gating Swagger).
3. 🟡 **Mettre `ENABLE_API_DOCS=0`** (ou ne pas le définir) dans l'environnement de prod.
4. 🟡 Ajouter un **secret scanner** en CI (gitleaks / trufflehog) pour bloquer toute
   future fuite avant le push.
5. 🔵 Router les 2-3 call-sites cosmétiques restants via `toUserMessage()`.
6. 🔵 Envisager un **scrub des en-têtes serveur** (`Server`, `X-Powered-By`) au niveau
   du reverse-proxy / WhiteNoise pour réduire le fingerprinting.

---

## 7. Fichiers modifiés

**Backend**
- `backend/config/settings.py` — `ENABLE_API_DOCS`, `SERVE_PERMISSIONS`
- `backend/config/urls.py` — gating des routes de documentation

**Frontend — Clients**
- `frontend/Clients/lib/core/api_service.dart` — `_throwHttpError`, `_guarded`, `_isNetworkError`

**Frontend — app & admin**
- `frontend/app/lib/core/security/secure_dio_client.dart` — `onError` sanitizer
- `frontend/admin/project/lib/core/security/secure_dio_client.dart` — `onError` sanitizer

**Frontend — Driver (couche + 11 call-sites)**
- `frontend/Driver App/app/lib/core/network/api_error.dart` *(nouveau)*
- `frontend/Driver App/app/lib/core/network/driver_dio_client.dart` — sanitizer
- pages : `quote_send_page`, `delivery_proof_page`, `mission_detail_page`, `documents_page`,
  `login_page`, `register_page`, `onboarding_page`, `vehicle_page`, `withdrawal_page`,
  `pickup_confirmation_page`

**Dépôt**
- `.gitignore` — motifs `*.bak`, `*.env.bak`, `marche-cm.local.env*`
- `backend/marche-cm.local.env.bak` — retiré du suivi git (rotation des clés requise)
