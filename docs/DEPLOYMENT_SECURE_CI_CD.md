# 🔒 Déploiement Sécurisé CI/CD + Terraform + SSM

**Date créée**: 2026-06-09  
**Status**: ✅ Production-ready  
**Auteur**: Infrastructure Team

## 📋 Vue d'ensemble

Ce guide configure le déploiement **100% sécurisé** sans aucune clé privée exposée:

- ✅ **OIDC** (GitHub → AWS): authentification sans secrets statiques
- ✅ **SSM send-command**: exécution de code sur l'EC2 (remplace SSH dangereux)
- ✅ **SSM Parameter Store**: stockage des secrets chiffrés (KMS)
- ✅ **Terraform**: infrastructure as code complète
- ✅ **Rollback automatique**: annulation en cas d'erreur

---

## 🚀 Démarrage rapide

### 1. Configuration initiale Terraform

Créer un fichier `terraform.tfvars` **LOCAL ONLY** (jamais committer):

```hcl
# infra/terraform/terraform.tfvars
aws_region = "eu-north-1"
aws_profile = "central-market_credentials"
environment = "prod"

# Base de données
db_password         = "VotreMDPForte!@#$%^&*()"
db_user             = "marchecm_admin"
db_name             = "marche_cm_db"

# JWT (générer avec: ssh-keygen -t rsa -b 4096 -N "" -m pem -f jwt_key)
jwt_signing_key     = file("~/.ssh/jwt_signing_key")
jwt_verifying_key   = file("~/.ssh/jwt_signing_key.pub")

# NotchPay (live mode)
notchpay_api_key    = "pk_live_xxxxx"
notchpay_secret_key = "sk_live_xxxxx"

# Email (SendGrid / Mailgun)
email_backend_api_key = "SG.xxxxxxxxxxxxx"

# Redis & Celery
redis_url           = "redis://redis-prod.xxxxx.ng.0001.eun1.cache.amazonaws.com:6379/0"
celery_broker_url   = "redis://redis-prod.xxxxx.ng.0001.eun1.cache.amazonaws.com:6379/1"

# Django / CORS
allowed_hosts       = "cm.digital-get.com,admin.digital-get.com"
cors_allowed_origins = "https://cm.digital-get.com"
```

⚠️ **IMPORTANT**:
- Ne JAMAIS committer `terraform.tfvars`
- `.gitignore` doit contenir `**/*.tfvars` (déjà configuré)
- Stocker le fichier LOCALEMENT ou dans un gestionnaire de secrets (1Password, Vault)

### 2. Créer les clés JWT (une seule fois)

```bash
# Générer la paire RSA 4096-bit
ssh-keygen -t rsa -b 4096 -N "" -m pem -f ~/.ssh/jwt_key

# Vérifier
cat ~/.ssh/jwt_key      # clé privée
cat ~/.ssh/jwt_key.pub  # clé publique

# Utiliser dans terraform.tfvars:
jwt_signing_key   = file("~/.ssh/jwt_key")
jwt_verifying_key = file("~/.ssh/jwt_key.pub")
```

### 3. Initialiser l'infrastructure

```bash
cd infra/terraform

# Initialiser Terraform
terraform init

# Vérifier le plan
terraform plan

# Appliquer (crée SSM Parameter Store + KMS)
terraform apply
```

✅ **Résultat**: tous les secrets sont maintenant dans SSM Parameter Store chiffrés avec KMS.

---

## 📝 Gestion des Secrets

### Lister les secrets SSM

```bash
aws ssm get-parameters-by-path \
  --path "/marche-cm/prod" \
  --recursive \
  --with-decryption \
  --region eu-north-1 \
  --output table
```

### Mettre à jour un secret

```bash
# Mettre à jour un secret existant
aws ssm put-parameter \
  --name "/marche-cm/prod/NOTCHPAY_API_KEY" \
  --value "pk_live_nouveauxxx" \
  --type SecureString \
  --key-id alias/marche-cm-ssm-secrets \
  --overwrite \
  --region eu-north-1

# Vérifier
aws ssm get-parameter \
  --name "/marche-cm/prod/NOTCHPAY_API_KEY" \
  --with-decryption \
  --region eu-north-1
```

### Ajouter un nouveau secret

```bash
# Via AWS CLI (direkt)
aws ssm put-parameter \
  --name "/marche-cm/prod/MON_NOUVEAU_SECRET" \
  --value "ma-valeur-secrete" \
  --type SecureString \
  --key-id alias/marche-cm-ssm-secrets \
  --region eu-north-1

# Via Terraform (ajouter dans ssm_secrets.tf puis terraform apply)
resource "aws_ssm_parameter" "mon_secret" {
  name            = "${local.ssm_prefix}/MON_NOUVEAU_SECRET"
  type            = "SecureString"
  value           = var.mon_nouveau_secret
  key_id          = aws_kms_key.ssm_secrets.id
  description     = "Description du secret"
  tags            = { Component = "app", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}
```

---

## 🔐 GitHub Actions Secrets

**Secrets GitHub** requis pour le déploiement:

### 1. `AWS_DEPLOY_ROLE_ARN`

ARN du rôle IAM assumé par le workflow GitHub Actions via OIDC.

```bash
# Obtenir l'ARN du rôle (créé par Terraform dans cicd_oidc.tf)
aws iam get-role \
  --role-name marche-cm-github-deploy \
  --region eu-north-1 \
  --query 'Role.Arn'

# Copier l'ARN (exemple)
# arn:aws:iam::958924735829:role/marche-cm-github-deploy
```

**Ajouter à GitHub**:
1. Aller à Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `AWS_DEPLOY_ROLE_ARN`
4. Value: `arn:aws:iam::958924735829:role/marche-cm-github-deploy`

### 2. `SLACK_WEBHOOK` (optionnel)

Pour les notifications Slack après déploiement:

```bash
# Dans Slack workspace:
# 1. Créer une app: api.slack.com/apps
# 2. Activer "Incoming Webhooks"
# 3. Copier l'URL

# Ajouter à GitHub comme secret
```

---

## 🚀 Déploiement

### Via GitHub Actions (automatique)

Le workflow se déclenche automatiquement sur `push` vers `main`:

```bash
git commit -m "Fix: JWT token rotation"
git push origin main

# GitHub Actions démarre automatiquement:
# 1. 📦 Build: crée un bundle tar.gz
# 2. 🔧 Deploy: upload sur S3 + SSM send-command sur EC2
# 3. 🏗️ Terraform: applique les changements infra
# 4. ✅ Verify: health checks
# 5. 🔄 Rollback: en cas d'erreur
```

### Manuellement (push vers une autre branche)

```bash
# Créer une branche feature
git checkout -b feature/xyz
git commit -m "Feature: xyz"
git push origin feature/xyz

# Pour déployer manuellement:
# 1. Aller à GitHub Actions
# 2. Cliquer sur "Run workflow"
# 3. Choisir la branche feature/xyz
# 4. Cliquer "Run workflow"
```

### Déploiement avec Terraform skip

```bash
# Déployer le code SANS mettre à jour l'infrastructure
# (utile pour hotfix rapide)
github.com/cyberark202/marche-cm/actions
→ Select "🚀 Deploy to Production"
→ "Run workflow"
→ check "skip_terraform"
→ "Run workflow"
```

---

## 📊 Monitoring & Logs

### Logs de déploiement

**GitHub Actions**:
```
https://github.com/cyberark202/marche-cm/actions
→ Workflow "🚀 Deploy to Production"
→ Click le deployment
→ Voir les logs par step
```

**AWS CloudWatch** (sur l'EC2):
```bash
# Voir les logs du déploiement SSM
aws logs tail /aws/ssm/command-invocations --follow --region eu-north-1

# Voir les logs de l'app (Docker)
ssh -i ~/.ssh/neue-key-api.pem ubuntu@cm.digital-get.com
docker compose -f /opt/marche-cm/backend/docker-compose.aws.yml logs -f web
```

**EC2 CloudWatch Agent** (optionnel):
```bash
# Sur l'EC2, examiner les logs système
journalctl -u marche-cm-docker -f
journalctl -u marche-cm-nginx -f
```

---

## 🔄 Rollback

### Automatique (sur échec du déploiement)

Si le déploiement échoue, le workflow exécute automatiquement:
```bash
git fetch origin main:main
git checkout main
bash infra/deploy/_deploy_ssm.sh
```

### Manuel

```bash
# Si rollback automatique échoue:
cd /opt/marche-cm
git fetch origin main:main
git checkout main
bash infra/deploy/_deploy_ssm.sh

# Ou via AWS CLI (SSM send-command)
aws ssm send-command \
  --instance-ids i-09e104c1cd49c757e \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/marche-cm && git checkout main && bash infra/deploy/_deploy_ssm.sh"]' \
  --region eu-north-1
```

---

## 🔒 Sécurité: Checklist

- [ ] ✅ Pas de clé SSH dans GitHub secrets
- [ ] ✅ OIDC configuré (au lieu de credentials statiques)
- [ ] ✅ Secrets dans SSM Parameter Store (chiffrés KMS)
- [ ] ✅ `terraform.tfvars` dans `.gitignore`
- [ ] ✅ EC2 a le rôle IAM `accessRoles3` avec SSM access
- [ ] ✅ SSH port 22 fermé à 0.0.0.0/0 (seulement admin IP)
- [ ] ✅ RDS privée (pas d'accès public)
- [ ] ✅ S3 chiffré + versioning activé

---

## 🧪 Test du déploiement

### 1. Test complet (sans production)

```bash
# Créer une branche test
git checkout -b test/deploy
echo "test" > README.md
git commit -am "Test deploy"
git push origin test/deploy

# Déclencher manuellement
# GitHub Actions → "Run workflow" → Branche test/deploy → Run

# Vérifier dans les logs
```

### 2. Test santé de l'API (post-déploiement)

```bash
# Vérifier l'API est up
curl -v https://cm.digital-get.com/api/health/
# Doit retourner HTTP 200

# Vérifier la base de données
curl -X POST https://cm.digital-get.com/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{}'
# Doit retourner un JWT (ou erreur auth valide, pas 500)
```

### 3. Vérifier les secrets SSM

```bash
# Sur l'EC2, via le rôle d'instance (pas de clés)
ssh -i ~/.ssh/neue-key-api.pem ubuntu@cm.digital-get.com

# L'instance peut lire SSM (via rôle accessRoles3)
aws ssm get-parameter \
  --name "/marche-cm/prod/DB_PASSWORD" \
  --with-decryption \
  --region eu-north-1
```

---

## ⚠️ Troubleshooting

### Le déploiement échoue à "Deploy via SSM"

```bash
# Vérifier que l'EC2 a l'agent SSM
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-09e104c1cd49c757e" \
  --region eu-north-1

# L'instance doit apparaître avec status "Online"

# Si absent, installer sur l'EC2:
ssh -i ~/.ssh/neue-key-api.pem ubuntu@cm.digital-get.com
sudo apt-get install -y amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
```

### SSM Parameter not found

```bash
# Vérifier les permissions IAM de l'instance
aws iam get-role-policy \
  --role-name accessRoles3 \
  --policy-name marche-cm-app-access \
  --region eu-north-1

# Doit avoir ssm:GetParameter + ssm:GetParametersByPath
# (et KMS Decrypt permissions)
```

### Terraform plan échoue

```bash
# Vérifier les credentials AWS
aws sts get-caller-identity --region eu-north-1

# Doit afficher le compte 958924735829

# Vérifier le profil
aws configure list --profile central-market_credentials
```

---

## 📞 Support

**Questions?** Contacter l'équipe infrastructure:
- **Email**: infrastructure@digital-get.com
- **Slack**: #infra-team
- **Docs**: `/wiki deployments`

---

## 📚 Références

- [AWS SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/parameter-store.html)
- [GitHub OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Docker Compose Deployment](../infra/deploy/_deploy_ssm.sh)
