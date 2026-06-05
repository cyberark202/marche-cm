# Inventaire infra AWS — compte central-market (958924735829)

Région : **eu-north-1** (Stockholm). Relevé : 2026-06-04 (read-only).
VPC unique : **`vpc-06c9268a6c1463479`** = **VPC par défaut**, CIDR `172.31.0.0/16`.

## EC2 — ⚠️ 3 instances aux noms quasi-identiques
| InstanceId | Tag Name | Type | État | EIP | Subnet (AZ) | IAM profile |
|---|---|---|---|---|---|---|
| `i-09e104c1cd49c757e` | **market-CM-API** | t3.large | running | 16.170.68.148 (`eipalloc-0b7ac1be31be19bfa`) | subnet-0716a4…ea8 (b) | accessRoles3 |
| `i-039f46312fcf50b44` | marchecm-api | t3.medium | running | 13.51.105.80 (`eipalloc-0791462f71ded447b`, tag "ip Elastc") | subnet-0740807…432 (a) | accessRoles3 |
| `i-08d79a376cc960064` | marketcm-api | t3.large | **stopped** | — | subnet-0740807…432 (a) | — |

Clé SSH commune : **`neue-key-api`** (≈ `Aws/new-key-api.ppk`). EBS : un volume par instance.

## RDS
- **`marchecm-postgres`** — db.r5.large — **PostgreSQL 18.3** — 200 Go gp3 (3000 IOPS)
- Endpoint : `marchecm-postgres.ch64seqcuph3.eu-north-1.rds.amazonaws.com:5432` — user `marchecm_admin`
- Chiffré KMS ✅ — backups 7 j ✅ — **MultiAZ : non** — **DeletionProtection : NON** — PerfInsights : non
- Subnet group `rds-ec2-db-subnet-group-1` (4 sous-réseaux privés RDS-Pvt-subnet-1..4)
- 3 SG : `sg-0650f15be757d09e3` (rds-ec2-1, OK), `sg-0883ba2a8933d59ba` (SecureGroup-Mcm), `sg-083d7a0e9c9eed317` (group-secure-marketcm)

## S3
- 1 bucket : **`market-cm`** (créé 2026-05-29)

## Security Groups (7) — constats
| SG | Nom | Inbound | Verdict |
|---|---|---|---|
| sg-03833d09622cb36b0 | launch-wizard-1 | 22/80/443 depuis **0.0.0.0/0** | 🔴 SSH ouvert au monde (sur les 2 instances running) |
| sg-0883ba2a8933d59ba | SecureGroup-Mcm | 22 depuis **0.0.0.0/0**, 443 depuis 129.0.99.166/32 | 🔴 SSH ouvert (attaché RDS) |
| sg-083d7a0e9c9eed317 | group-secure-marketcm | 80/443/22 depuis 129.0.99.166/32, 5000 depuis 102.244.197.67/32 | ✅ restreint |
| sg-0819d0a49a7c50f85 | ec2-rds-1 | (egress 5432 → rds-ec2-1) | ✅ liaison EC2→RDS |
| sg-0650f15be757d09e3 | rds-ec2-1 | 5432 depuis ec2-rds-1 | ✅ liaison RDS←EC2 |
| sg-0d483c9985c6f8fc4 | default | self | standard |

IP admin probable : **129.0.99.166**.

## IAM
- Rôle `accessRoles3` (assume EC2) + instance-profile `accessRoles3` → accès S3 pour les EC2 (à confirmer : policies attachées).
- `rds-monitoring-role` (enhanced monitoring RDS).
- Rôles AWS service-linked (EC2 Instance Connect, RDS, ResourceExplorer, Support, TrustedAdvisor) → **gérés par AWS, ne pas importer**.

## Manques (pour les chantiers demandés)
- **ECR** : aucun repository → à créer pour le CI/CD.
- **CloudWatch** : 0 alarme, aucun log group applicatif (seul `RDSOSMetrics`) → observabilité à bâtir.
- **Secrets Manager / SSM** : non utilisés → secrets encore en `.env`.

## À décider avant l'import Terraform
1. **Quelle instance EC2 est la prod canonique** (market-CM-API vs marchecm-api) — les 2 tournent = double coût.
2. Sort des 2 autres instances (garder / stopper / supprimer).
3. RDS : activer **DeletionProtection** ? (fintech)
4. Durcir SSH (fermer 0.0.0.0/0 → IP admin) — quand et avec quelle IP.
