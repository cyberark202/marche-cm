# INFRASTRUCTURE_AUDIT.md — Audit infrastructure AWS MarketCM
**Date :** 2026-06-12 · **Méthode :** AWS CLI authentifié (user `central-market`, compte 958924735829, eu-north-1) + SSM RunCommand sur l'instance. Chaque constat ci-dessous provient d'une exécution réelle.

## 1. Verdict synthétique

| Domaine | État | Note |
|---|---|---|
| EC2 | ✅ sain (corrigé) | t3.large, load 0.01, RAM 6.4G dispo, disque 21 % |
| RDS | ✅ très bien durci | privé, chiffré, MultiAZ, deletion protection, backups 7 j |
| S3 | ✅ corrigé | était : code source + KYC publics via CloudFront |
| CloudFront | ⚠️ acceptable | OAC + redirect-https, mais cert par défaut (TLSv1 min) et cache policy legacy |
| Redis | ✅ corrigé | politique d'éviction dangereuse pour le broker corrigée |
| Celery | 🔴→✅ corrigé | AUCUN worker/beat ne tournait en prod |
| CloudWatch | ✅ | 6 alarmes EC2/RDS, toutes OK |
| IAM | ⚠️ | inline policy app bien scopée ; user humain = AdministratorAccess |
| SSM | ✅ | 33 paramètres /marche-cm/prod/*, accès KMS conditionné ViaService |

## 2. Constats détaillés (preuves)

### 2.1 EC2 — i-09e104c1cd49c757e (t3.large, 16.170.68.148 EIP)
- `uptime` : load 0.01 · `free -m` : 6420 MB disponibles · `df` : 21 % de 38 G — marge confortable. ✅
- Conteneurs (après correctifs) : nginx, web (Daphne), redis, finops-retries, **worker-default, worker-financial, beat** — tous Up, web/redis/nginx healthy. ✅
- SG effectifs : `launch-wizard-1` (80/443 monde — attendu pour un backend public) + `ec2-rds-1` (egress vers RDS). SSH **non exposé** (SG ne l'ouvre pas ; accès par SSM uniquement). ✅
- ⚠️ Volume EBS racine `vol-0806f94cad0e69433` (40 G) **non chiffré**. Remédiation = snapshot → copie chiffrée → swap (interruption requise) — **signalé, non appliqué**.
- ⚠️ `DisableApiTermination=false` — activer la protection est recommandé.
- ⚠️ Un `redis-server` host (systemd, 127.0.0.1:6379) tourne en doublon du conteneur Redis — inutilisé par l'app (l'app pointe sur le réseau Docker interne). Candidat à `systemctl disable` — **signalé**.

### 2.2 RDS — marchecm-postgres (db.t3.medium, PostgreSQL 18.3)
- PubliclyAccessible=false, StorageEncrypted=true, MultiAZ=true, BackupRetention=7 j, DeletionProtection=true, 9 snapshots, stockage 200 G → autoscaling 1 T. ✅
- SG `rds-ec2-1` : 5432 accessible uniquement depuis le SG EC2. ✅
- Latence applicative mesurée depuis le conteneur web : **SELECT 1 = 26 ms**. ✅
- ⚠️ Performance Insights désactivé (gratuit en rétention 7 j) — recommandé.
- ❌ NON VÉRIFIÉ : réplication read-replica (aucune réplique n'existe ; non requis à ce volume).

### 2.3 S3 — bucket market-cm
- Public Access Block : 4/4 ✅ · Chiffrement AES256 + BucketKey ✅ · Versioning Enabled ✅ · CORS : origines prod + localhost dev (⚠️ retirer les localhost à terme).
- 🔴 **CORRIGÉ [SEC-CRIT-001]** : la bucket policy autorisait CloudFront sur `market-cm/*` entier. Conséquence prouvée par exécution : `https://df7t18zqeme69.cloudfront.net/deploy/code.tar.gz` → **HTTP 200** (code source backend téléchargeable par quiconque) et `/compliance/<fichier>.jpg` → **HTTP 200** (documents KYC réels publics). **Correctif appliqué** : policy restreinte à `products/*` et `avatars/*` (seuls préfixes que le backend sert en URL non signée) + invalidation CloudFront des chemins sensibles. Re-test : objet compliance frais → **403**. ✅
- ⚠️ 955 objets parasites sous `backend/` (staticfiles d'un ancien collectstatic S3, 6,4 MB, dernière écriture 2026-05-29) — inertes, désormais non servables par le CDN ; suppression recommandée (signalé).

### 2.4 CloudFront — E1GA5ICIZQJOLK
- OAC actif (E2RCZWW9L6UJ0D), ViewerProtocolPolicy=redirect-to-https, Compression on, HTTP/2. ✅
- ⚠️ Certificat CloudFront par défaut (pas d'alias) → `MinimumProtocolVersion=TLSv1` imposé par AWS tant qu'un domaine custom + cert ACM ne sont pas posés — signalé.
- ⚠️ CachePolicy legacy (ForwardedValues) — migrer vers une Cache Policy managée (CachingOptimized) recommandé.

### 2.5 Redis (conteneur sur EC2)
- AOF activé, dernier bgsave ok, 1,53 M / 256 M utilisés, 0 éviction, 0 rejet, 20 clients. ✅
- 🔴 **CORRIGÉ [INFRA-P0-002]** : la recréation du conteneur échouait en boucle (`find: ./appendonlydir: Permission denied`) — l'entrypoint root ne pouvait plus traverser le dossier AOF (700, uid redis) avec `cap_drop: ALL` sans `DAC_OVERRIDE`. Défaut latent qui aurait fait échouer **tout** redéploiement → caps `CHOWN`+`DAC_OVERRIDE` ajoutées au compose.
- ⚠️→✅ **CORRIGÉ** : `maxmemory-policy allkeys-lru` pouvait évincer des files Celery (listes sans TTL) sous pression mémoire → passé à `volatile-lru`.

### 2.6 Celery — 🔴 défaut majeur corrigé [INFRA-P0-001]
- **Constat prouvé** : `docker ps` ne montrait ni worker ni beat ; files Redis `default/financial/outbox` à 0 sans consommateur. Le `beat_schedule` (celery_app.py) planifie pourtant : auto-release escrow (5 min), outbox (5 s), retries payouts (3 min), réconciliation quotidienne + wallet↔ledger horaire, SLA litiges, intégrité chaîne d'audit. **Aucune de ces tâches ne tournait en production.**
- **Correctifs appliqués et déployés** (docker-compose.aws.yml) : services `worker-default` (-Q default,outbox, c=2), `worker-financial` (-Q financial, c=1 sérialisé), `beat` (DatabaseScheduler, `--pidfile=`).
- **Bugs révélés par la mise en route, corrigés et testés** :
  - [INFRA-P0-003] `dispatch_pending` : `select_for_update` hors transaction → `TransactionManagementError` à chaque batch. Corrigé (`transaction.atomic()`), test de régression `core/events/test_dispatch_pending.py` (3 tests verts).
  - [INFRA-P0-004] `apps/wallets/tasks.py` **n'existait pas** alors que le beat le référence (3 tâches) → "Received unregistered task". Module créé, branché sur payout_retry/reconciliation/idempotency_service existants.
  - [INFRA-P0-005] `event_bus.publish` ne renseigne pas `next_retry_at` (NULL) et le filtre `__lte=now` excluait tout événement frais → événements outbox invisibles à vie. Filtre corrigé (NULL = dispatchable).
- **Preuve post-déploiement** : `process_outbox_events` succeeded toutes les 5 s ; `retry_failed_payouts` received + succeeded `{'processed': 0, ...}`. ✅
- ℹ️ Constat architecture : la table OutboxEvent est **vide** — aucun code métier n'appelle encore `event_bus.publish`. Le pattern est câblé mais inutilisé (signalé, pas un bug).

### 2.7 IAM
- Instance profile `accessRoles3` : `AmazonSSMManagedInstanceCore` + inline `marche-cm-app-access` **bien scopée** (SSM /marche-cm/prod/*, KMS via SSM uniquement, S3 limité au bucket, logs). ✅
- 🔴→✅ **CORRIGÉ** : policy managée `AmazonS3ExpressFullAccess` détachée (service S3 Express jamais utilisé ; l'inline couvre le besoin). Vérification post-retrait par exécution : PUT/DELETE S3 depuis le conteneur web → OK.
- ⚠️ User `central-market` (clés CLI) = `AdministratorAccess` — privilège excessif pour un usage quotidien ; créer un rôle/scopes dédiés (signalé — non modifié pour ne pas couper l'accès en cours d'audit).
- Rôle `marche-cm-github-deploy` (OIDC CI/CD) : présent. ✅

### 2.8 SSM Parameter Store
- 33 paramètres `/marche-cm/prod/*` couvrant DB, JWT (RS256, clés PEM), NotchPay (live), SMTP, chiffrement données, CORS/CSRF, ALLOWED_HOSTS. Aucun manquant constaté par rapport aux variables consommées par compose/settings. ✅
- ⚠️ `LOADTEST_BYPASS_TOKEN` présent en prod — vérifier sa rotation après chaque campagne de test de charge (signalé).

### 2.9 CloudWatch
- 6 alarmes (EC2 CPU high, status-check ; RDS CPU/mémoire/stockage/connexions) — toutes `OK`. ✅
- Logs conteneurs → log group `/aws/container/marche-cm` (web, nginx, finops + désormais worker-default, worker-financial, beat). ✅
- ⚠️ Aucune alarme sur les 5xx applicatifs ni sur la profondeur des files Celery — recommandé.

### 2.10 Ressources orphelines / coûts
| Ressource | État | Action |
|---|---|---|
| SG `SecureGroup-Mcm`, `group-secure-marketcm` | non attachés | suppression recommandée (signalé) |
| redis-server host (systemd) | doublon inutilisé | `systemctl disable --now` recommandé (signalé) |
| Objets S3 `backend/` (955 staticfiles) | inertes | suppression recommandée (signalé) |
| EIP 16.170.68.148 | associée | RAS |
| Volumes EBS | 1 seul, attaché | RAS |
| ElastiCache / SNS / ressources fantômes | aucune trouvée | RAS |

## 3. Incident survenu pendant l'audit (transparence)
Le déploiement des workers Celery a recréé le conteneur Redis, déclenchant le défaut latent [INFRA-P0-002] (caps insuffisantes vs AOF) → API en 502/504 (fenêtre constatée via timestamps SSM : ~23:55 → 01:33 UTC). Service restauré après ajout des caps + reload nginx (le conteneur web recréé change d'IP ; nginx résout les upstreams au chargement). **Tout redéploiement standard aurait déclenché ce même incident** ; il est désormais neutralisé. Recommandation : ajouter `resolver 127.0.0.11` ou un reload nginx systématique dans le pipeline de déploiement.
