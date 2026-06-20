# LOAD_TEST_REPORT.md — Phase 12 (charge légère autorisée)

> Périmètre **explicitement validé par le PO** : charge légère (≤100 req contrôlées) sur endpoints
> **non-financiers** en lecture seule. PAS de 100/500/1000 users, PAS de paiements réels.
> Méthode : `urllib` + ThreadPool 20 workers, percentiles réels. Date : 2026-06-18. Cible prod.

## Résultats mesurés
| Endpoint | N | Codes | P50 | P90 | P95 | P99 | Max |
|---|---|---|---|---|---|---|---|
| `/api/health/` | 60 | 200×22, **429×38** | 948 ms | 2354 ms | 2391 ms | 2395 ms | 2400 ms |
| `/api/products/?page_size=20` | 90 | 200×39, **429×51** | 932 ms | 1866 ms | 1899 ms | 1944 ms | 1949 ms |
| `/api/ui-config/` | 60 | 200×5, **429×55** | 942 ms | 1066 ms | 1083 ms | 1088 ms | 1102 ms |

## Lecture
- **Rate-limiting ACTIF et strict** : dès ~20 requêtes concurrentes depuis une IP, la majorité
  est throttlée en **429**. → bonne protection anti-DoS/anti-burst (sécurité PASS).
- **Latence élevée** : P50 ≈ 930 ms même sur `/api/health/` (réponse 200 statique) sous concurrence.
  Cohérent avec l'origine **mono-EC2 sans Load Balancer ni CDN devant l'API** (cf. INFRA I-2).

## Findings
- **L-1 (MOYEN) — Scalabilité non démontrée / plafond par IP bas.** Throttle dès 20 concurrents/IP.
  La tenue à 100/500/1000 utilisateurs **distincts** n'est **NOT VERIFIED** (test non autorisé sur prod)
  et reste douteuse sans scale horizontal. *Reco* : ALB + ≥2 instances/ASG, puis test de charge dédié
  sur staging avec IP distinctes.
- **L-2 (BAS) — Pas de header `Retry-After`/`X-RateLimit-*`.** Les clients ne savent pas quand réessayer.
  *Reco* : exposer `Retry-After` sur les 429.
- **L-3 (INFO) — Latence P50 ~930 ms.** À investiguer (région, cold path, absence de cache/CDN API).

## Statut Phase 12
**PARTIAL** — rate-limiting prouvé efficace (PASS sécurité) ; **scalabilité 100→1000 = NOT VERIFIED**
(hors périmètre autorisé) + findings perf/scale (L-1, I-2).
