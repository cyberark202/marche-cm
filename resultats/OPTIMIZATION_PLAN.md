# OPTIMIZATION PLAN — Tenir 10 000 utilisateurs simultanés (Marché CM)

**Date :** 2026-06-03
**Base :** mesures de `LOAD_TEST_REPORT.md` (profilage requêtes SQL + concurrence) + analyse statique du code (Modular Monolith Django/DRF/Channels/Celery/PostgreSQL/Redis).
**Principe directeur :** le code applicatif est **déjà majoritairement efficace** (catalogue = 4 requêtes, 0 N+1). Les vrais leviers pour 10k sont **infra (pooling DB, workers, Redis), résilience (découplage temps réel), et diffusion (CDN média)**, pas une réécriture.

Légende priorité : 🔴 bloquant 10k · 🟠 fort impact · 🟡 hygiène/prévention.

---

## 1. 🔴 Base de données — pooling de connexions (LE mur dur)

**Constat :** à 50 requêtes concurrentes localement, 85 % d'échecs ; chaque requête concurrente tient une connexion PostgreSQL (`CONN_MAX_AGE=60`). Les plans Render PG plafonnent bas (dizaines à ~100 connexions). 10 000 utilisateurs simultanés ⇒ bien au-delà sans mutualisation.

**Actions :**
1. **PgBouncer en mode `transaction`** devant PostgreSQL (Render add-on ou sidecar). Objectif : N workers applicatifs × pool réduit → quelques dizaines de connexions backend max, des milliers de clients devant.
2. Avec PgBouncer transaction-pooling : `CONN_MAX_AGE=0` côté Django (laisser PgBouncer gérer), désactiver les `SET`/prepared-statements persistants incompatibles (psycopg : `prepare_threshold=None`).
3. Dimensionner : `max_connections` PG ↔ `default_pool_size` PgBouncer ↔ nb de workers (cf. §3). Régle de base : `workers × threads ≤ default_pool_size`.
4. Lectures lourdes (catalogue, recherche) → **réplica en lecture** si le trafic 60 % catalogue le justifie.

**Impact attendu :** passe le plafond de quelques dizaines à plusieurs milliers de connexions clientes. **Indispensable pour > 500 simultanés.**

---

## 2. 🟠 Requêtes N+1 & ORM

**Constat :** `GET /api/chat/rooms/` = 7 requêtes / 4 salons avec `SELECT accounts_user … ×5` (N+1 participants). `GET /api/orders/` = 6 requêtes / 3 commandes (à vérifier).

**Actions :**
1. **`/chat/rooms`** : `ChatRoomViewSet.get_queryset()` → `prefetch_related('participants')` (+ `select_related` sur le dernier message / l'autre participant). Cible : nombre de requêtes **constant** quel que soit le nombre de salons.
2. **`/orders`** : `select_related('product', 'escrow', 'shipment', 'buyer')` + `prefetch` des lignes si applicable. Re-mesurer avec `CaptureQueriesContext` (script `qa_e2e/_bench_queries.py`) : viser ≤ 3–4 requêtes constantes.
3. Ajouter un **garde-fou CI** : `assertNumQueries` sur les endpoints listés, pour empêcher toute régression N+1 future.
4. Vérifier la **pagination** partout (page_size raisonnable, `count()` indexé) — éviter les `LIMIT` sans `ORDER BY` indexé.

**Impact :** supprime la croissance linéaire des requêtes sur les listes ; protège le P95 sous charge.

---

## 3. 🔴 Serveur d'application — workers & autoscaling

**Constat :** le test tournait sur un **dev-server mono-process** ; non viable en prod.

**Actions :**
1. **ASGI multi-worker** : `uvicorn`/`gunicorn -k uvicorn.workers.UvicornWorker` (ou Daphne derrière plusieurs instances). `workers ≈ 2×vCPU + 1`. Séparer **HTTP** et **WebSocket** en services distincts (profils de charge différents).
2. **Autoscaling horizontal** Render (scale par CPU/RPS) — le monolithe est stateless côté HTTP (JWT), donc scalable à plat.
3. Garder le **worker Celery `financial` à concurrency=1** (règle anti-race) mais scaler `default`/`outbox` séparément.
4. Timeouts & backpressure : limiter le backlog d'accept, renvoyer **429** (throttle) plutôt que de laisser les requêtes s'empiler (le test a montré des erreurs dures à saturation, pas de dégradation propre).

---

## 3bis. 🟠 Calibrer le rate-limiting (mesuré au load test §1bis)

**Constat :** dès ~100 requêtes/s depuis **une seule IP**, ~100 % de **429** (Cloudflare + throttle DRF). Excellent contre un flood mono-source, **mais risque de faux positifs majeur dans le contexte Marché CM** : les réseaux mobiles camerounais (MTN/Orange) sortent de **nombreux abonnés derrière peu d'IP NAT** → à 10k utilisateurs légitimes, beaucoup partageront une IP et seront throttlés à tort.

**Actions :**
1. **Clé de throttle par utilisateur authentifié** (et non par IP seule) sur les endpoints authentifiés ; garder un throttle IP **uniquement** sur les routes anonymes sensibles (login, register).
2. **Aligner Cloudflare et DRF** : éviter le double comptage ; définir des seuils réalistes par scénario (catalogue lecture >> écriture).
3. **Allowlister les IP des générateurs de load test** pour mesurer le serveur, pas la protection.
4. Renvoyer **`Retry-After`** propre et un message clair côté client (back-off), plutôt qu'un échec sec.

---

## 4. 🟠 Cache (Redis) — décharger la DB sur le chemin 60 % catalogue

**Actions :**
1. **Cacher le catalogue & les facettes** : `GET /api/products/` et filtres → cache Redis court (30–60 s) avec clé par (filtres, page). Le catalogue est en lecture massive et peu volatile → énorme gain DB.
2. `ui-config` est déjà à **0 requête** ✅ — modèle à généraliser (réponses statiques cachées/edge).
3. **Cache d'entités chaudes** (détail produit, profils vendeurs) avec invalidation à l'écriture.
4. Dimensionner Redis : mémoire + `maxmemory-policy allkeys-lru` ; séparer **cache** / **channel layer** / **broker Celery** sur des DB/instances distinctes pour éviter la contention.

---

## 5. 🟠 Temps réel (WebSocket / Channels) — découplage & capacité

**Constats :** (a) `broadcast_event` est **synchrone dans le chemin requête** → un incident Redis ⇒ **500 sur les écritures** + latence Redis ajoutée à chaque write (cf. QA_E2E_V2_REPORT §4.2). (b) Saturation Redis/WebSocket **non mesurée** (cible absente).

**Actions :**
1. **Découpler le fan-out** : `broadcast_event`/`group_send` en **fire-and-forget** (try/except + log), ou via la file `outbox`/Celery. L'écriture métier ne doit jamais échouer parce que le temps réel est indisponible.
2. **Channel layer Redis** dédié et dimensionné pour 10k connexions WS : surveiller `CHANNEL_CAPACITY` (1500) et la mémoire ; envisager le **sharding** `channels_redis` multi-hôtes.
3. **Allowlister/ouvrir l'accès Redis** (l'IP de prod doit être autorisée ; cf. constat infra) et **fixer le typo `CACHE_URL` (`:63799`)**.
4. WebSocket sur un **service séparé autoscalé** (connexions longues ≠ requêtes HTTP courtes).

---

## 6. 🟠 Médias (Cloudflare R2) — diffusion publique + CDN

**Constat (QA_E2E_V2_REPORT §4.1) :** les URLs média pointent sur l'**endpoint S3 privé** R2 → GET public rejeté (400). Sous charge, servir les médias par l'app serait en plus un anti-pattern.

**Actions :**
1. Servir les médias via **domaine public R2 (`pub-….r2.dev`) ou domaine custom + CDN Cloudflare** ; ne jamais router les images par Django.
2. Valider le **nom de bucket** (`Market_File`) et l'accès public/lecture.
3. Vignettes/`srcset` pour le catalogue (réduire le poids sur mobile Cameroun).

---

## 7. 🟠 Paiement (NotchPay) — fiabiliser sous charge

**Constats (QA_E2E_V2_REPORT §4.4/4.5) :** `NOTCHPAY_PUBLIC_KEY` vide-présent cassait tous les top-ups (502) ; `RETURN_URL` vide redirige vers le webhook (405) ; le webhook serveur→serveur vise l'URL dashboard.

**Actions :**
1. **Corriger la config en prod (Render dashboard)** : retirer les vars vides `NOTCHPAY_PUBLIC_KEY`/`NOTCHPAY_PRIVATE_KEY` (fallback LIVE), définir `NOTCHPAY_CHECKOUT_RETURN_URL` (page succès), pointer le **webhook dashboard** vers le backend live.
2. **Activer la réconciliation Celery beat** (`reconcile_pending_transactions`, déjà existante et validée) comme filet de sécurité si un webhook est perdu sous charge.
3. Le checkout dépend d'un **appel provider externe** (~2–6 s) : le rendre **asynchrone/non bloquant** (créer le lien en tâche + polling/SSE côté client) pour ne pas tenir un worker pendant l'appel NotchPay sous forte charge.

---

## 8. 🔴 PostgreSQL — index & verrous (escrow)

**Actions :**
1. **Index** : vérifier la présence d'index sur les colonnes de **recherche/filtre/tri** du catalogue (`title`/`category`/`created_at`), sur tous les **FK** (`product`, `buyer`, `owner`, `room`, `order`) et sur les colonnes de `WHERE` fréquentes. Utiliser `EXPLAIN ANALYZE` sur catalogue+recherche en prod.
2. **Verrous escrow** : les transitions financières utilisent `SELECT FOR UPDATE` (règle d'architecture). Sous contention (mêmes wallets), garder la **portée du verrou minimale** (verrouiller la ligne wallet le plus tard/court possible), s'appuyer sur l'**idempotency_key** (déjà présent) et la file `financial` concurrency=1 pour sérialiser sans deadlock. Surveiller `pg_locks`/`pg_stat_activity` au load test.
3. Recherche produit : si le volume grossit, passer à un **index trigram (pg_trgm)** ou un moteur dédié plutôt que `ILIKE`.

---

## 9. 🟡 Observabilité (pré-requis du vrai load test)

1. Exposer/scraper **`/metrics`** (Prometheus déjà branché) : latence p50/p95/p99 par endpoint, taux d'erreur, RPS.
2. Dashboards : **connexions PG actives**, hit-rate Redis, profondeur file Celery, connexions WS, CPU/RAM par service.
3. Tracing (OpenTelemetry, stubs déjà présents) pour isoler les endpoints lents en prod réelle.

---

## 10. Feuille de route d'exécution

| Étape | Pré-requis | Action |
|---|---|---|
| 0 | — | Redéployer le backend ; ouvrir/allowlister Redis ; corriger config NotchPay (Render env) |
| 1 | déployé | **Vrai load test 100→10k** via Locust/k6 **co-localisé** (cf. LOAD_TEST_REPORT §6), capturer métriques serveur |
| 2 | 🔴 | PgBouncer + multi-worker ASGI + autoscaling (§1, §3) |
| 3 | 🟠 | Fix N+1 `/chat/rooms` + `/orders` + assertNumQueries CI (§2) |
| 4 | 🟠 | Cache catalogue Redis + CDN média R2 (§4, §6) |
| 5 | 🟠 | Découpler `broadcast_event` + dimensionner channel layer (§5) |
| 6 | 🟡 | Index/EXPLAIN + observabilité, re-test, itérer (§8, §9) |

**Cible :** après §2–§4, le chemin 60 % catalogue (4 requêtes, cachable) devrait tenir plusieurs milliers de RPS ; le mur historique (connexions DB) est levé par PgBouncer. Valider empiriquement au load test co-localisé avant d'annoncer 10k.
