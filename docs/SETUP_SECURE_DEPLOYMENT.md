# 🔧 Configuration initiale du déploiement sécurisé

**Status**: Guide étape par étape  
**Durée estimée**: 30 minutes  
**Prérequis**: accès AWS + GitHub repo

---

## 📋 Checklist de configuration

### Phase 1: Préparation locale

- [ ] 1.1. Installer les outils
- [ ] 1.2. Générer les clés JWT
- [ ] 1.3. Créer `terraform.tfvars` (LOCAL ONLY)

### Phase 2: Infrastructure AWS (Terraform)

- [ ] 2.1. Initialiser Terraform
- [ ] 2.2. Planifier la déploiement
- [ ] 2.3. Appliquer (crée SSM Parameter Store)

### Phase 3: Configuration GitHub Actions

- [ ] 3.1. Copier l'ARN du rôle OIDC
- [ ] 3.2. Ajouter `AWS_DEPLOY_ROLE_ARN` secret
- [ ] 3.3. Ajouter `SLACK_WEBHOOK` (optionnel)

### Phase 4: Validation

- [ ] 4.1. Vérifier SSM Parameter Store
- [ ] 4.2. Vérifier permissions IAM
- [ ] 4.3. Test déploiement de code

---

## 🔨 Mise en place détaillée

### Phase 1: Préparation locale

#### 1.1. Installer les outils

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-win-x86_64.zip" -o "awscliv2.zip"
# Puis extraire et installer

# Terraform
choco install terraform  # ou télécharger depuis terraform.io

# Vérifier
aws --version
terraform --version
```

#### 1.2. Générer les clés JWT RSA

```bash
# Ouvrir PowerShell ou Git Bash

# Générer la paire (4096-bit, pas de passphrase)
ssh-keygen -t rsa -b 4096 -N "" -m pem -f $env:USERPROFILE/.ssh/jwt_key

# Vérifier
cat $env:USERPROFILE/.ssh/jwt_key      # Clé privée
cat $env:USERPROFILE/.ssh/jwt_key.pub  # Clé publique

# Copier pour l'étape 1.3
```

#### 1.3. Créer `terraform.tfvars` (LOCAL ONLY)

```bash
# Aller dans le dossier infra/terraform
cd infra\terraform

# Créer le fichier terraform.tfvars
cat > terraform.tfvars << 'EOF'
aws_region  = "eu-north-1"
aws_profile = "central-market_credentials"
environment = "prod"

# ──────────────────────────────────────────────────────────────────
# Base de données PostgreSQL
# ──────────────────────────────────────────────────────────────────
db_password = "VotreMDPForte!@#$%^&*()"
db_user     = "marchecm_admin"
db_name     = "marche_cm_db"

# ──────────────────────────────────────────────────────────────────
# JWT (généré en 1.2)
# ──────────────────────────────────────────────────────────────────
jwt_signing_key   = file("~/.ssh/jwt_key")
jwt_verifying_key = file("~/.ssh/jwt_key.pub")

# ──────────────────────────────────────────────────────────────────
# NotchPay (live mode)
# ──────────────────────────────────────────────────────────────────
notchpay_api_key    = "pk_live_xxxxx"
notchpay_secret_key = "sk_live_xxxxx"

# ──────────────────────────────────────────────────────────────────
# Email (SendGrid ou Mailgun)
# ──────────────────────────────────────────────────────────────────
email_backend_api_key = "SG.xxxxxxxxxxxxx"

# ──────────────────────────────────────────────────────────────────
# Redis & Celery
# ──────────────────────────────────────────────────────────────────
redis_url      = "redis://redis.xxxxx.ng.0001.eun1.cache.amazonaws.com:6379/0"
celery_broker_url = "redis://redis.xxxxx.ng.0001.eun1.cache.amazonaws.com:6379/1"

# ──────────────────────────────────────────────────────────────────
# Django / CORS
# ──────────────────────────────────────────────────────────────────
allowed_hosts        = "cm.digital-get.com,admin.digital-get.com"
cors_allowed_origins = "https://cm.digital-get.com"

EOF

# Vérifier le fichier
cat terraform.tfvars
```

**⚠️ IMPORTANT**:
- `terraform.tfvars` doit RESTER LOCAL
- Ajouter à `.gitignore` (déjà fait): `**/*.tfvars`
- Sauvegarder dans un coffre-fort (1Password, Vault)

---

### Phase 2: Infrastructure AWS (Terraform)

#### 2.1. Initialiser Terraform

```bash
# Dans le dossier infra/terraform

# Initialiser (télécharge les providers)
terraform init

# Doit afficher:
# ✓ Terraform has been successfully initialized!
```

#### 2.2. Planifier le déploiement

```bash
# Voir le plan AVANT d'appliquer
terraform plan

# Outputs clés:
# - aws_ssm_parameter.db_password (chiffré KMS)
# - aws_ssm_parameter.jwt_signing_key (SecureString)
# - aws_kms_key.ssm_secrets (créée)
# - aws_iam_role.github_deploy (pour OIDC)
```

#### 2.3. Appliquer

```bash
# Appliquer les changements
terraform apply

# Vérifier au lancement:
terraform apply

# Outputs importants:
# 1. github_deploy_role_arn ← À copier pour GitHub
# 2. kms_key_id ← ID de la clé KMS
```

**Résultat**: SSM Parameter Store contient maintenant tous les secrets chiffrés!

---

### Phase 3: Configuration GitHub Actions

#### 3.1. Copier l'ARN du rôle OIDC

```bash
# Terraform vient d'afficher l'output (en 2.3)
# Sinon, récupérer avec:
terraform output github_deploy_role_arn

# Copier l'ARN (ressemble à):
# arn:aws:iam::958924735829:role/marche-cm-github-deploy
```

#### 3.2. Ajouter le secret AWS_DEPLOY_ROLE_ARN

1. Aller à **GitHub**:
   ```
   github.com/cyberark202/marche-cm
   → Settings
   → Secrets and variables
   → Actions
   → New repository secret
   ```

2. Remplir:
   - **Name**: `AWS_DEPLOY_ROLE_ARN`
   - **Value**: l'ARN copié en 3.1
   - **Protection**: Leave unprotected (utilisation dans tous les workflows)

3. Click **Add secret**

#### 3.3. Ajouter le secret SLACK_WEBHOOK (optionnel)

1. Créer un webhook Slack (optionnel, pour notifications):
   ```
   api.slack.com/apps
   → Create New App
   → Incoming Webhooks
   → Copier l'URL
   ```

2. Ajouter à GitHub:
   ```
   Settings → Secrets and variables → Actions
   → New repository secret
   → Name: SLACK_WEBHOOK
   → Value: https://hooks.slack.com/...
   ```

---

### Phase 4: Validation

#### 4.1. Vérifier SSM Parameter Store

```bash
# Lister tous les secrets
aws ssm get-parameters-by-path \
  --path "/marche-cm/prod" \
  --recursive \
  --region eu-north-1 \
  --output table

# Doit afficher 15+ paramètres (DB, JWT, NotchPay, etc.)
```

#### 4.2. Vérifier les permissions IAM

```bash
# Vérifier le rôle EC2 a accès SSM
aws iam get-role-policy \
  --role-name accessRoles3 \
  --policy-name marche-cm-app-access \
  --region eu-north-1 \
  --query Policy.PolicyDocument

# Doit avoir:
# - ssm:GetParameter
# - ssm:GetParametersByPath
# - kms:Decrypt
```

#### 4.3. Test déploiement de code

```bash
# Créer une branche test
git checkout -b test/first-deploy
echo "# Test Deploy" >> README.md
git commit -am "Test first secure deploy"
git push origin test/first-deploy

# Déclencher le workflow:
# GitHub.com/cyberark202/marche-cm
# → Actions
# → "🚀 Deploy to Production"
# → "Run workflow"
# → Branche: test/first-deploy
# → "Run workflow"
```

Vérifier dans les logs:
- ✅ `Build` complété
- ✅ `Deploy` via SSM réussi (CommandId affiché)
- ✅ `Verify` health check OK
- ✅ Pas d'erreurs "SSH_PRIVATE_KEY not found"

---

## 🔍 Vérification finale

### Checklist finale

```bash
# 1. Terraform state
terraform state list | head -10
# Doit afficher: aws_ssm_parameter.*, aws_kms_key.*, aws_iam_role.*

# 2. SSM Parameter Store
aws ssm get-parameters-by-path \
  --path "/marche-cm/prod" \
  --region eu-north-1 \
  | jq '.Parameters | length'
# Doit afficher: 15+

# 3. IAM Role OIDC
aws iam get-role --role-name marche-cm-github-deploy \
  | jq '.Role.AssumeRolePolicyDocument'
# Doit contenir: token.actions.githubusercontent.com

# 4. GitHub Secrets
# Vérifier via GitHub UI que AWS_DEPLOY_ROLE_ARN est défini
```

---

## 🚀 Utilisation quotidienne

### Déployer une change

```bash
# Normal (depuis main)
git commit -am "Fix: JWT token rotation"
git push origin main
# Workflow se lance automatiquement

# Depuis une branche (manuel)
git checkout feature/xyz
git push origin feature/xyz
# GitHub Actions → "Run workflow" → branche feature/xyz
```

### Mettre à jour un secret

```bash
# Avec AWS CLI
aws ssm put-parameter \
  --name "/marche-cm/prod/NOTCHPAY_API_KEY" \
  --value "pk_live_nouveaux" \
  --type SecureString \
  --key-id alias/marche-cm-ssm-secrets \
  --overwrite \
  --region eu-north-1

# Puis redéployer
git commit -am "chore: redeploy for secret update"
git push origin main
```

### Ajouter un nouveau secret

```bash
# 1. Ajouter dans Terraform (infra/terraform/ssm_secrets.tf)
resource "aws_ssm_parameter" "mon_secret" {
  name            = "${local.ssm_prefix}/MON_SECRET"
  type            = "SecureString"
  value           = var.mon_secret
  key_id          = aws_kms_key.ssm_secrets.id
}

# 2. Ajouter la variable (infra/terraform/variables.tf)
variable "mon_secret" {
  type        = string
  sensitive   = true
  default     = ""
}

# 3. Ajouter dans terraform.tfvars
mon_secret = "valeur-secrete"

# 4. Appliquer
terraform plan
terraform apply

# 5. Utiliser dans le code (fetch_env.sh)
# Sera automatiquement chargé depuis SSM
```

---

## ⚠️ Sécurité: Points critiques

### ❌ NE PAS faire

```bash
# ❌ JAMAIS committer terraform.tfvars
git add terraform.tfvars
git commit -m "Add tfvars"  # NON!

# ❌ JAMAIS mettre des secrets dans GitHub secrets
# Les secrets vont dans SSM Parameter Store

# ❌ JAMAIS utiliser SSH avec clés privées en GitHub Actions
# Utiliser OIDC (déjà configuré)
```

### ✅ À faire

```bash
# ✅ Committer la config (sans les valeurs)
git add infra/terraform/*.tf
git add .github/workflows/deploy-production.yml
git commit -m "ci: update deployment config"

# ✅ Secrets dans SSH keychain local
# Sauvegarder terraform.tfvars dans 1Password/Vault

# ✅ Audit régulier
aws ssm get-parameters-by-path --path "/marche-cm/prod" --recursive | jq '.Parameters[] | {Name, LastModifiedDate}' | head -20
```

---

## 📞 Aide

```bash
# Vérifier terraform.tfvars est ignoré
git status
# Ne doit PAS afficher terraform.tfvars

# Vérifier OIDC
aws iam list-open-id-connect-providers \
  | grep token.actions.githubusercontent.com

# Voir les déploiements GitHub
gh run list --workflow=deploy-production.yml
```

---

**Félicitations! 🎉** Vous avez configuré un déploiement sécurisé 100% sans clés privées exposées.
