# INFRA_AUDIT.md — Phase 2 : Validation Infrastructure (Zero-Trust)

> Méthode : sondes réseau **read-only** réelles depuis le poste + lecture Terraform.
> **Limite honnête** : aucune credential AWS dans cet environnement
> (`aws sts get-caller-identity` → *Unable to locate credentials*).
> Donc la vérification niveau-API AWS (describe EC2/RDS/SG/VPC…) est **NOT VERIFIED**.
> Tout ce qui est marqué PASS l'est par preuve réseau directe, pas par déclaration Terraform.
> Date : 2026-06-18 · cible : `https://cm.digital-get.com` + CDN.

## Matrice infra

| Ressource | Méthode de preuve | Résultat | Verdict |
|---|---|---|---|
| **EC2 / origine backend** | `GET /api/health/` → 200, `Server: nginx` | App Django UP derrière nginx | **PASS** |
| **RDS PostgreSQL** | `GET /api/products/` → 200 + **50 produits réels** renvoyés | requête SQL aboutie → DB up & servante | **PASS** (indirect) |
| **CloudFront** | image média → `Via: …cloudfront.net` + `X-Amz-Cf-Id` + `X-Cache: Miss from cloudfront` | CDN actif | **PASS** |
| **S3** | même requête → `Server: AmazonS3`, HTTP 200, `image/jpeg` | objets servis depuis S3 via CDN | **PASS** |
| **S3 + OAC (origin access)** | média accessible **uniquement** via domaine CloudFront `df7t18zqeme69.cloudfront.net` | front CDN/OAC en place | **PASS** |
| **TLS / certificat** | `openssl s_client` : Let's Encrypt, `CN=cm.digital-get.com`, valide **04/06→02/09/2026** | cert valide, hostname correct | **PASS** |
| **HSTS / headers** | `max-age=63072000; includeSubDomains; preload`, X-Frame DENY, nosniff, CSP `default-src 'none'` | durcissement transport+navigateur | **PASS** |
| **Surface réduite** | `/api/schema/` → 404, `/admin/` → 404 | docs & admin Django non exposés en prod | **PASS** |
| **Redis** | non joignable en read-only (privé, IP-allowlist) ; health check ne le teste pas | dépendance Celery/Channels non prouvée ici | **NOT VERIFIED** |
| **VPC / Subnets / SG / NAT / Route Tables** | déclarés Terraform (4 subnets, 5 SG, EIP) ; pas de creds pour `describe` | existence non confirmée niveau-API | **NOT VERIFIED** |
| **SSM / KMS / SNS / CloudWatch / Budgets** | déclarés Terraform (~18 SSM, KMS, SNS, 6 alarmes) ; pas de creds | non confirmé niveau-API | **NOT VERIFIED** |
| **Load Balancer** | aucun `aws_lb*` dans Terraform ; nginx sur EC2 fait le front | pas d'ALB → SPOF mono-EC2 | **PARTIAL** (voir finding I-2) |

## Mesures réseau (réelles)
- TLS handshake (`time_appconnect`) ≈ **1.10 s**, total `/` ≈ 1.39 s. Acceptable, pas de CDN devant l'API.
- `POST /api/auth/login/` sans body → **400** (validation propre, pas de 500).
- `GET /api/auth/login/` → **405** (méthode refusée correctement).

## Findings SRE
- **I-1 (MOYEN) — Health check superficiel.** `config/health.py` renvoie 200 statique :
  il ne vérifie **ni PostgreSQL ni Redis ni Celery**. Un Redis/DB down laisserait `/api/health/`
  vert → fausse santé pour les sondes CloudWatch/ELB.
  *Reco* : health profond (SELECT 1 + `redis ping` + broker ping), code 503 si une dépendance est down.
- **I-2 (MOYEN) — Pas de Load Balancer / mono-EC2.** Aucune ressource `aws_lb` ;
  nginx sur une seule instance = point de défaillance unique, pas d'auto-scaling, déploiement non rolling.
  *Reco* : ALB + ≥2 instances (ou ECS/ASG) avant montée en charge réelle.
- **I-3 (INFO) — AWS non auditable depuis ce poste.** Pas de credentials → les ressources
  VPC/SG/RDS/SSM/KMS ne sont prouvées que par Terraform (intention), pas par état réel.
  *Reco* : rejouer cette phase avec un rôle read-only (`ReadOnlyAccess`) pour passer NOT VERIFIED → PASS.

## Statut Phase 2
**PARTIAL** — plan de données (EC2/RDS/S3/CloudFront/TLS) **PROUVÉ vivant et durci** ;
plan de contrôle AWS (VPC/SG/SSM/Redis) **NOT VERIFIED** faute de credentials read-only.
