# FINAL_PRODUCTION_AUDIT — MarketCM
**Date :** 2026-06-12 · **Auditeur :** passe d'audit exécutoire (vérifier → exécuter → corriger → retester → prouver)
**Production :** `https://cm.digital-get.com` · **AWS :** compte 958924735829, eu-north-1 · EC2 `i-09e104c1cd49c757e`

> Principe appliqué : chaque ✅ correspond à une **exécution réelle** (AWS CLI, SSM RunCommand, curl prod, suite de tests). Tout le reste est marqué **❌ NON VÉRIFIÉ**.

---

## 1. Scores

| Domaine | Score | Justification (preuve) |
|---|---:|---|
| Infrastructure | **88/100** | EC2/RDS/CloudWatch sains ; corrigé Celery+Redis ; reste EBS non chiffré, EIP/SG orphelins |
| Backend | **95/100** | 319/319 tests OK + 4 invariants ledger + 3 bugs corrigés/testés |
| Flutter | **92/100** | analyze 0 issue ×4, tests verts ×4, 4 APK release construits ; tests d'intégration légers |
| AWS | **85/100** | RDS/S3/IAM app bien durcis ; reste IAM user admin, EBS, cert CloudFront par défaut |
| Sécurité | **90/100** | fuite critique S3/KYC corrigée & re-testée ; contrôles live conformes ; reste 3 medium signalés |
| Fintech | **94/100** | double entrée + conservation + idempotence prouvées par exécution ; réconciliation désormais active |
| Performance | **86/100** | SELECT 1 = 26 ms, cache 102 ms, load 0.01, 0 éviction Redis ; pas de test de charge relancé ce jour |
| Scalabilité | **80/100** | single-EC2 + RDS MultiAZ ; Redis/Celery sur l'instance (pas de scale-out horizontal) |
| **Production Readiness** | **88/100** | Go conditionnel — voir §6 (commit+redéploiement des correctifs requis) |

---

## 2. Bugs corrigés (avec preuve de test)

| ID | Description | Correctif | Preuve |
|---|---|---|---|
| INFRA-P0-001 | **Aucun worker/beat Celery en prod** : escrow auto-release, outbox, retries payouts, réconciliation, SLA — rien ne tournait | 3 services ajoutés au compose AWS et déployés | `docker ps` : beat + 2 workers Up ; tâches `succeeded` en boucle |
| INFRA-P0-003 | `dispatch_pending` : `select_for_update` hors transaction → crash chaque batch | enveloppé dans `transaction.atomic()` | `test_dispatch_pending.py` 3/3 OK |
| INFRA-P0-004 | `apps/wallets/tasks.py` inexistant mais référencé par le beat → "unregistered task" | module créé, branché sur services existants | tâches enregistrées listées ; `retry_failed_payouts` succeeded en prod |
| INFRA-P0-005 | `next_retry_at` NULL exclu par le filtre → événements outbox invisibles à vie | filtre `isnull=True OR <=now` | test couvre handler exécuté |
| INFRA-P0-002 | Redis : `cap_drop ALL` sans CHOWN/DAC_OVERRIDE → crash-loop à toute recréation (déclenché en live) | caps ajoutées | `docker ps` redis healthy après recréation |
| INFRA (Redis) | `maxmemory-policy allkeys-lru` pouvait évincer les files Celery | → `volatile-lru` | config conteneur vérifiée |

## 3. Vulnérabilités corrigées

| ID | Sévérité | Description | État |
|---|---|---|---|
| SEC-CRIT-001 | 🔴 Critique | Code source backend (`deploy/code.tar.gz`) **et documents KYC** (`compliance/*`) téléchargeables publiquement via CloudFront (HTTP 200) | ✅ bucket policy restreinte à `products/*`+`avatars/*`, cache invalidé. **Re-test : 403** |
| IAM-S3EXPRESS | 🟡 Faible | Policy `AmazonS3ExpressFullAccess` superflue sur le rôle d'instance | ✅ détachée ; PUT/DELETE S3 re-testés OK |

## 4. Optimisations / ressources détectées

**Appliqué :**
- Politique d'éviction Redis durcie (protège les files de tâches).
- Workers Celery dimensionnés (limits CPU/mémoire) ; financial sérialisé (c=1).
- Policy IAM superflue retirée (moindre privilège).

**Détecté & signalé (non supprimé — décision exploitant / risque d'interruption) :**
- SG `SecureGroup-Mcm` et `group-secure-marketcm` non attachés → suppression.
- `redis-server` host (systemd) en doublon du conteneur → `systemctl disable`.
- 955 objets S3 `backend/` (staticfiles obsolètes, 6,4 MB) → suppression.
- Volume EBS racine non chiffré → recréation via snapshot chiffré.
- IAM user `central-market` = AdministratorAccess → scoping + MFA.
- `LOADTEST_BYPASS_TOKEN` actif en prod (bypass rate-limit) → blanchir hors campagne + purger historique git.
- Cert CloudFront par défaut (TLSv1 min) + CachePolicy legacy → domaine custom + ACM + CachingOptimized.

## 5. Preuves d'exécution (synthèse)
- **Tests backend :** suite complète **319/319 OK** ; sous-ensemble fintech **63/63 OK** ; invariants ledger **4/4 OK** ; régression outbox **3/3 OK**.
- **Sécurité live :** IDOR→401 (×8), bruteforce→429, Host injection→400, traversal→404, TRACE→405, Swagger/admin/metrics→404, WS anonyme→403, HSTS/CSP stricts.
- **Infra live (SSM) :** RDS SELECT 1 = 26 ms, cache 102 ms, Redis 0 éviction/0 rejet, EC2 load 0.01 / 6,4 G RAM libre / disque 21 %, 7 conteneurs Up.
- **Flutter :** analyze 0 issue ×4, test vert ×4, **4 APK release** (60/60/52,8/49,2 MB) sur disque.
- **S3/CloudFront :** fuite fermée (compliance 403, deploy 403) ; média public maintenu (produit 200).

## 6. ⚠️ Action durable REQUISE avant de considérer l'audit clos
Les correctifs d'infrastructure (services Celery, caps Redis dans `backend/docker-compose.aws.yml`) et de code (`core/events/dispatcher.py`, `apps/wallets/tasks.py`, 2 fichiers de test) sont **actifs sur l'EC2** et **présents dans le dépôt local**, mais le pipeline CI redéploie depuis `s3://market-cm/deploy/code.tar.gz`. **Sans commit + redéploiement, le prochain déploiement écraserait les workers Celery et ré-introduirait le crash-loop Redis.**

À faire :
1. `git add` + commit des fichiers modifiés (compose, dispatcher, wallets/tasks, tests) sur la branche, puis merge.
2. Déclencher le pipeline (repackage S3 + `_deploy_ssm.sh`) — qui inclut désormais le reload nginx recommandé.
3. Ajouter un reload nginx systématique en fin de `_deploy_ssm.sh` (l'IP de l'upstream `web` change à chaque recréation → évite les 502).

## 7. Éléments NON VÉRIFIÉS (transparence)
- ❌ iOS build (Windows — nécessite macOS/Xcode).
- ❌ Paiement NotchPay LIVE réel de bout en bout (argent réel).
- ❌ Email OTP réel / push FCM réel sur device.
- ❌ `flutter build appbundle` (.aab) et keystore de release Play Store.
- ❌ Test de charge relancé ce jour (rapport antérieur existant non re-exécuté).
- ❌ Réplication RDS read-replica (inexistante, non requise à ce volume).

## 8. Verdict
**GO conditionnel à la mise en production.** Les deux défauts bloquants découverts (Celery absent, fuite KYC/code) sont **corrigés et re-testés en production**. Le système est sain, sécurisé et cohérent comptablement à l'instant T. La condition unique avant clôture : **committer et redéployer** les correctifs pour qu'ils survivent au prochain cycle CI (§6).

Aucune erreur critique, vulnérabilité critique, incohérence métier, erreur de compilation, endpoint dangereux ou transaction non sécurisée ne subsiste à l'état vérifié ce jour.
