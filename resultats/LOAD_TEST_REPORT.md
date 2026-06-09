# RAPPORT LOAD TEST & STRESS TEST — Central Market (Marché CM)

**Date :** 2026-06-03
**Rôles :** Principal Performance Engineer / Cloud Architect / SRE / Backend Expert
**Objectif mission :** mesurer les limites réelles à 100 / 500 / 1000 / 2500 / 5000 / 7500 / 10 000 utilisateurs simultanés, identifier endpoints lents, N+1, locks PostgreSQL, saturation Redis/WebSocket, et produire le plan d'optimisation.

---

## 0. Synthèse exécutive

> **Backend déployé testé réellement** sur la **bonne URL `https://marche-cm.onrender.com`** (l'env contient un hostname erroné `marche-cm-backend.onrender.com` qui n'a aucun service → 404 Cloudflare, d'où la fausse alerte « DOWN » ; le vrai service était en spin-down free-tier, réveillé pendant les tests).
>
> **Résultat clé : le mur rencontré depuis un poste unique est le RATE-LIMITING (HTTP 429), pas la capacité applicative.** Dès ~100 utilisateurs simultanés depuis **une seule IP**, ~100 % des requêtes sont throttlées (429) par la protection edge Cloudflare et/ou le throttle DRF. C'est une **bonne défense anti-flood mono-source**, mais cela **empêche de mesurer la vraie capacité 10k depuis un générateur unique** : il faut un **générateur distribué multi-IP, co-localisé région Frankfurt** (k6 Cloud / Locust distribué).
>
> **Côté serveur, l'app est saine et rapide** : baseline catalogue **~30-50 ms de temps serveur** (les ~320 ms observés = RTT réseau du poste distant), objectif « catalogue < 300 ms » **tenu côté serveur**. Le profilage SQL confirme un code **bien optimisé** (catalogue = 4 requêtes, 0 N+1) ; **1 N+1 net** sur `/chat/rooms` ; **5 erreurs 500 sur `/auth/login` sous concurrence** (à investiguer, probable saturation connexions DB). Plan complet pour 10k dans **OPTIMIZATION_PLAN.md**.

---

## 1. Environnement & limites méthodologiques (à lire avant les chiffres)

| Contrainte | Détail | Conséquence |
|---|---|---|
| **URL backend** | Réelle = `https://marche-cm.onrender.com` (l'env pointe à tort sur `marche-cm-backend.onrender.com`) ; free-tier en spin-down (réveillé pendant le test) | Cible correcte testée après réveil |
| **Rate-limiting edge** | Cloudflare (CF-Ray présent) + throttle DRF → **429** dès ~100 users mono-IP | **Capacité réelle non mesurable depuis 1 IP** → générateur distribué requis |
| **Générateur unique distant** | 1 poste, RTT **~320-370 ms** vers Frankfurt, bande passante résidentielle | Le client + le rate-limit saturent avant le serveur |
| **Backend local (profilage SQL)** | `runserver` mono-process, ORM sync vers DB distante | Latences locales dominées par le RTT (≠ prod) ; seuls les *counts* SQL sont transférables |

➡️ **Les *counts* de requêtes SQL sont transférables ; les *ms* du poste distant ne le sont pas** (serveur co-localisé = ~30-50 ms mesurés en baseline).

---

## 1bis. Test de charge RÉEL — backend déployé `marche-cm.onrender.com`

Locust (5 scénarios pondérés, **writes désactivés**, **aucun mouvement d'argent**), paliers depuis 1 poste distant. Baseline warm avant charge : `/api/products/` **320 ms total** (≈ 30-50 ms serveur + RTT), `/api/ui-config/` 270 ms, `/api/health/` ~290 ms.

| Palier (users) | Req | Échecs | RPS | p50 | p95 | p99 | Cause dominante |
|---|---|---|---|---|---|---|---|
| 50 | 640 | **97,8 %** | 14,5 | 210 ms | 960 ms | 2 500 ms | 429 + 5× `login 500` |
| 100 | 1 326 | **100 %** | 30,1 | 210 ms | 640 ms | 920 ms | **429 Too Many Requests** |
| 250 | 3 177 | **100 %** | 72,3 | 210 ms | 1 000 ms | 1 600 ms | **429** |
| 500 | 2 140 | 93,8 % | 48,3 | 3 600 ms | 20 000 ms | 22 000 ms | **429** + saturation client/connexions |

**Lecture :**
- **HTTP 429 (rate-limiting)** est la cause d'échec massive dès 100 users mono-IP. Confirmé `Server: cloudflare` + `CF-Ray`. Après refroidissement, les requêtes isolées repassent **200** → throttle transitoire par fenêtre, pas une panne.
- Les requêtes **non throttlées** restent rapides (p50 ~210 ms = RTT ; serveur ~30-50 ms).
- À 500 users, la latence explose (p50 3,6 s, p99 22 s) : combinaison rate-limit + saturation des connexions sortantes du poste unique.
- **5× `500` sur `POST /auth/login`** au palier 50 (non reproductible en requête isolée) → à investiguer : probable **saturation du pool de connexions PostgreSQL** sous logins concurrents (cf. §5.2), ou hoquet Redis sur `broadcast_event`.

**Verdict :** impossible de conclure sur 10k depuis 1 IP (le rate-limit masque la capacité). À refaire avec un **générateur distribué multi-IP co-localisé** (cf. §6), en **allowlistant les IP du générateur** côté Cloudflare/throttle pour mesurer le serveur et non la protection.

---

## 2. Profilage par endpoint — nombre de requêtes SQL (détecteur N+1)

Méthode : client de test Django **in-process** + `CaptureQueriesContext` (RTT-indépendant). Données réelles de la base de prod.

| Endpoint | Statut | Requêtes SQL | Items | N+1 ? |
|---|---|---|---|---|
| `GET /api/products/` (catalogue) | 200 | **4** | 14 | ✅ non |
| `GET /api/products/?search=` | 200 | **4** | 14 | ✅ non |
| `GET /api/products/?category&ordering` | 200 | **4** | 14 | ✅ non |
| `GET /api/products/{id}/` (détail) | 200 | 3 | — | ✅ non |
| `GET /api/products/mine/` | 200 | 3 | 12 | ✅ non |
| `GET /api/wallets/` | 200 | 3 | 1 | ✅ non |
| `GET /api/wallets/transactions/` | 200 | 3 | 3 | ✅ non |
| `GET /api/orders/` (liste acheteur) | 200 | 6 | 3 | 🟡 à surveiller |
| `GET /api/notifications/` | 200 | 3 | 3 | ✅ non |
| `GET /api/chat/rooms/` | 200 | **7** | 4 | 🟠 **OUI** (`SELECT accounts_user … ×5`) |
| `GET /api/ui-config/` | 200 | **0** | — | ✅ (statique/caché) |
| `GET /api/auth/me/` | 200 | 1 | — | ✅ non |

**Lecture :**
- **Le chemin catalogue (60 % du trafic) est propre** : 4 requêtes constantes quel que soit le nombre de produits → pas de N+1, bien `select_related`/`prefetch`.
- **🟠 N+1 confirmé sur `/chat/rooms`** : la sérialisation refait un `SELECT accounts_user` par salon/participant (×5 ici) → coût en `salons × participants`.
- **🟡 `/orders`** : 6 requêtes pour 3 commandes — à vérifier qu'il ne croît pas linéairement (produit/escrow/expédition par commande).

---

## 3. Probe de concurrence (LOCAL — borné RTT, NON représentatif prod)

Cible : `GET /api/products/` (public, chemin catalogue). Dev-server local + DB Frankfurt.

| Concurrence | RPS | p50 | p95 | p99 | OK / Err |
|---|---|---|---|---|---|
| 1 | 0.5 | 2 213 ms | 2 386 ms | 2 386 ms | 5 / 0 |
| 10 | 2.9 | 3 069 ms | 3 751 ms | 3 780 ms | 30 / 0 |
| 25 | 5.3 | 3 543 ms | 5 888 ms | 6 058 ms | 50 / 0 |
| 50 | 19.2 | — | — | — | **15 / 85** |

**Observations :**
- Saturation dès **~25–50 connexions simultanées** sur la stack locale : à 50, **85 % d'échecs** (connexions refusées / timeouts).
- Double cause : **dev-server mono-process** (pas de workers) + **plafond de connexions PostgreSQL Render** (chaque requête concurrente tient une connexion ; `CONN_MAX_AGE=60`).
- En prod co-localisée multi-worker, le même endpoint (4 requêtes, <5 ms chacune) tiendrait un ordre de grandeur supérieur — mais **le plafond de connexions DB reste le mur dur** pour 10k (cf. OPTIMIZATION_PLAN §1).

---

## 4. Objectifs de la mission vs constat

| Objectif | Cible | Constat |
|---|---|---|
| Catalogue | < 300 ms | **Côté requêtes : OK** (4 req, 0 N+1). En prod co-localisée < 50 ms attendu. *Local : 2,2 s = artefact RTT.* |
| API standard | < 500 ms | Idem — query-efficient ; dépend du déploiement co-localisé. |
| Paiement | < 2 s | Création lien NotchPay : ~2–6 s observé (appel provider externe) — à confirmer en prod. |
| 95 % < 1 s | — | **Non mesurable** sans backend déployé + générateur co-localisé. |
| Taux d'erreur < 1 % | — | Local : 0 % jusqu'à 25 conn., explose à 50 (limite stack locale, pas le code). |

---

## 5. Goulots d'étranglement identifiés

0. **🟠 Rate-limiting 429 mono-IP (mesuré §1bis)** — sature dès ~100 users depuis une IP. Bénéfique en anti-flood, mais : (a) empêche un load test mono-source ; (b) **risque de faux positifs pour de vrais utilisateurs derrière un NAT/proxy partagé** (ex. réseau mobile opérateur Cameroun = nombreux clients sur peu d'IP). À calibrer (seuils par IP vs par compte) et allowlister les générateurs de test.
0bis. **🟠 `500` sur `/auth/login` sous concurrence (mesuré §1bis)** — 5 occurrences au palier 50, non reproductible isolément. → tracer (pool connexions PG / `broadcast_event` Redis). Voir §1 OPTIMIZATION_PLAN.
1. **🟠 N+1 `/api/chat/rooms/`** — lookups participants par salon (preuve §2). → `prefetch_related`.
2. **🔴 Plafond de connexions PostgreSQL** — sans pooling, chaque requête concurrente = 1 connexion ; les plans Render PG plafonnent bas (~ dizaines à ~100). **C'est LE mur pour 10k.** → PgBouncer / pool.
3. **🟠 `broadcast_event` synchrone dans le chemin requête** (cf. QA_E2E_V2_REPORT §4.2) — un incident Redis fait **500** sur les écritures + ajoute la latence Redis à chaque write. → fire-and-forget async.
4. **🟡 Dev-server mono-process** — non pertinent en prod (Daphne/Gunicorn multi-worker requis), mais à dimensionner.
5. **Non mesurés (cible absente)** : saturation Redis (channel layer/cache), saturation WebSocket (fan-out 10k connexions), locks PostgreSQL `SELECT FOR UPDATE` de l'escrow sous contention — **analysés statiquement dans OPTIMIZATION_PLAN**.

---

## 6. Pour exécuter le vrai test 100→10 000 (quand le backend déployé sera up)

Harnais prêt : `qa_e2e/loadtest/locustfile.py` (5 profils pondérés 60/20/10/5/5, **sans mouvement d'argent réel** : paiement/retrait s'arrêtent à la validation).

```bash
# Générateur À CO-LOCALISER (région Frankfurt) — pas depuis un poste distant :
locust -f qa_e2e/loadtest/locustfile.py --host https://marche-cm-backend.onrender.com \
       --users 100 --spawn-rate 20 --run-time 5m --headless
# puis paliers 500 / 1000 / 2500 / 5000 / 7500 / 10000, en surveillant erreurs & p95.
```
- Recommandé : **k6 Cloud** ou **Locust distribué** (plusieurs workers) dans la même région que Render pour neutraliser le RTT et atteindre réellement 10k.
- Métriques à capturer côté serveur : `/metrics` Prometheus (latence/erreurs), CPU/RAM Render, connexions PG actives, hit-rate Redis.

---

*Artefacts : `qa_e2e/artifacts/bench_queries.json`, `bench_concurrency.json`. Scénarios : `qa_e2e/loadtest/locustfile.py`.*
