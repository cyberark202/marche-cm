# CONNECTIVITY_AUDIT.md — Validation des communications MarketCM
**Date :** 2026-06-12 · Tous les chiffres proviennent d'exécutions réelles (curl local, SSM RunCommand sur l'EC2, docker exec dans le conteneur web prod).

## 1. Matrice de connectivité

| Liaison | Test exécuté | Résultat |
|---|---|---|
| Internet → API (HTTPS) | `curl https://cm.digital-get.com/api/health/` | ✅ 200, JSON santé |
| Internet → API (HTTP) | `curl http://...` | ✅ 301 → https (redirection forcée) |
| TLS | poignée de main TLS ≥1.2, HSTS preload 2 ans | ✅ |
| API → PostgreSQL (RDS) | `SELECT 1` depuis le conteneur web | ✅ **26 ms** (TLS require) |
| API → Redis (cache) | `cache.set/get` depuis le conteneur web | ✅ **102 ms** (1er rtt, pool froid) |
| API → Celery broker | tâches `received`/`succeeded` dans worker-default et worker-financial | ✅ (après correctifs INFRA-P0-001..005) |
| Beat → files | `Scheduler: Sending due task` toutes les 5 s | ✅ |
| API → S3 | `put_object` + `delete_object` boto3 via rôle d'instance | ✅ PUT-OK / DELETE-OK |
| CloudFront → S3 (OAC) | GET objet `products/` | ✅ 200 |
| CloudFront — chemins privés | GET `compliance/*`, `deploy/*` | ✅ **403 après correctif** (était 200 = fuite) |
| Internet → WebSocket | upgrade `wss://…/ws/notifications/` sans token | ✅ chemin routé jusqu'à Daphne, refus propre **403 Access denied** (anonyme rejeté, attendu) |
| API → SMTP | non testé en envoi réel (éviter le spam depuis l'audit) | ❌ NON VÉRIFIÉ (config SSM présente : Gmail TLS 587) |
| API → NotchPay | non testé en transaction réelle (mode LIVE, argent réel) | ❌ NON VÉRIFIÉ dans cette phase — couvert par tests unitaires webhooks (319 verts) |
| API → FCM | dépend de la clé firebase-admin en prod | ❌ NON VÉRIFIÉ (pas de push réel déclenché) |

## 2. Timeouts / retries / robustesse
- DB : `DB_CONNECT_TIMEOUT=5`, `CONN_MAX_AGE=60`, `sslmode=require` — vérifiés dans l'env compose + settings.
- Celery : `task_acks_late=True`, `task_reject_on_worker_lost=True`, `prefetch=1` — livraison at-least-once ; file `financial` sérialisée (c=1).
- Outbox : retries avec backoff (`next_retry_at`), dead-letter après `max_retries` ; correctif [INFRA-P0-005] garantit la prise en charge des événements frais.
- Géocodage inscription : publication Celery sur thread daemon + fallback silencieux → l'inscription ne bloque jamais sur le broker (prouvé par la suite de tests : `test_register_fast_even_when_broker_unreachable`).
- nginx → web : ⚠️ résolution DNS upstream au chargement seulement — un `web` recréé change d'IP et nginx sert 502 jusqu'au reload (constaté en live). Recommandation : reload nginx en fin de déploiement (à ajouter dans `_deploy_ssm.sh`).

## 3. DNS / erreurs réseau
- `cm.digital-get.com` résout vers l'EIP 16.170.68.148 (stable, associée).
- Aucun échec DNS/TLS rencontré sur l'ensemble des sondes de l'audit.
