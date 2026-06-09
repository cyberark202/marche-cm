# GitHub Actions CI/CD Setup Guide
**Date**: 2026-06-09  
**Workflow**: `.github/workflows/deploy-production.yml`  
**Trigger**: Automatic on push to `aws-infra`  

---

## 🚀 SETUP STEPS (5 minutes)

### Step 1: Add SSH Private Key to GitHub Secrets

1. **Get your SSH private key** from your local machine:
   ```bash
   cat ~/.ssh/id_rsa
   ```

2. **Go to GitHub repo** → Settings → Secrets and variables → Actions

3. **Create new secret** `SSH_PRIVATE_KEY`:
   - Name: `SSH_PRIVATE_KEY`
   - Value: (paste your private key content)
   - Click "Add secret"

### Step 2: Add AWS Role ARN (for Terraform)

1. **Get your AWS role ARN** from AWS IAM:
   ```bash
   aws iam get-role --role-name GithubActionsDeployRole --query 'Role.Arn'
   ```
   Should return: `arn:aws:iam::958924735829:role/GithubActionsDeployRole`

2. **Create new secret** `AWS_ROLE_ARN`:
   - Name: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::958924735829:role/GithubActionsDeployRole`
   - Click "Add secret"

### Step 3: (Optional) Add Slack Webhook for notifications

1. **Get Slack webhook** from your Slack workspace settings

2. **Create new secret** `SLACK_WEBHOOK`:
   - Name: `SLACK_WEBHOOK`
   - Value: (your Slack webhook URL)
   - Click "Add secret"

---

## ✅ VERIFY SETUP

```bash
# Check that secrets are configured
gh secret list -R your-repo/marche-cm

# Should show:
# SSH_PRIVATE_KEY    
# AWS_ROLE_ARN       
# SLACK_WEBHOOK      (optional)
```

---

## 🎯 DEPLOYMENT FLOW

### Automatic Trigger:
```
git push origin aws-infra
    ↓
GitHub Actions workflow triggered
    ↓
Step 1: Deploy Backend
  • Pull latest code
  • Install dependencies
  • Apply migrations
  • Restart services
  • Health check
    ↓
Step 2: Deploy AWS (if backend succeeds)
  • Terraform plan
  • Terraform apply (S3 encryption)
  • Verify changes
    ↓
Step 3: Post-deployment verification
  • API health check
  • Summary report
  • Slack notification (optional)
    ↓
✅ DEPLOYMENT COMPLETE
```

### Automatic Rollback (if failure):
```
Deployment fails
    ↓
Automatic rollback triggered
    ↓
git revert to previous commit
    ↓
Services restarted
    ↓
Alert sent to GitHub / Slack
```

---

## 📊 WORKFLOW DETAILS

### File: `.github/workflows/deploy-production.yml`

**Triggers on**:
- Push to `aws-infra` branch

**Jobs**:

1. **deploy-backend** (10-15 min)
   - SSH to production server
   - Git pull latest code
   - Install Python dependencies
   - Apply database migrations (including 0007_add_composite_indexes)
   - Restart Django/Daphne services
   - Verify health endpoint

2. **deploy-aws-infrastructure** (5-10 min, runs after backend succeeds)
   - Assume AWS role
   - Terraform init
   - Terraform plan
   - Terraform apply (S3 encryption + versioning)
   - Verify changes

3. **verification** (1-2 min, final checks)
   - API health check (with retry)
   - Deployment summary
   - Slack notification (optional)

4. **rollback** (on failure only)
   - Automatic rollback to previous commit
   - Service restart
   - Failure alert

---

## 🔐 SECURITY FEATURES

✅ **Secrets Management**:
- SSH key stored securely in GitHub Secrets
- AWS credentials via OIDC (no long-lived keys)
- Slack webhook optional

✅ **Branch Protection**:
- aws-infra requires PR review before merge
- CI/CD status checks required
- Only authorized users can push

✅ **Audit Trail**:
- All deployments logged in GitHub Actions
- Commits tracked with Co-Authored-By
- Rollback events logged

✅ **Environment Protection**:
- Production environment requires explicit approval
- Deployment logs retained for 90 days
- Secrets masked in logs

---

## 📝 MANUAL DEPLOYMENT (Fallback)

If GitHub Actions fails, you can deploy manually:

```bash
# SSH to production
ssh ubuntu@cm.digital-get.com

# 1. Backend deployment
cd /opt/marche-cm/backend
git pull origin aws-infra
python manage.py migrate orders 0007
sudo systemctl restart marche-cm-django marche-cm-daphne

# 2. AWS infrastructure
cd ../infra/terraform
terraform plan
terraform apply

# 3. Verify
curl https://cm.digital-get.com/api/health/
```

---

## 🎯 NEXT: PUSH TO TRIGGER DEPLOYMENT

```bash
# Make sure everything is committed
git status
# (should show clean working tree)

# Push to aws-infra to trigger automatic deployment
git push origin aws-infra

# Watch deployment in real-time
gh run watch
# or go to: https://github.com/your-repo/marche-cm/actions
```

---

## ✅ SUCCESS INDICATORS

✅ **GitHub Actions page shows green checkmark**
✅ **All jobs passed**: `deploy-backend`, `deploy-aws-infrastructure`, `verification`
✅ **Slack notification** (if configured): Deployment successful
✅ **API responding**: `curl https://cm.digital-get.com/api/health/`
✅ **Database indexes created**: Visible in logs
✅ **AWS S3 encrypted**: Verified by Terraform output

---

## ⚠️ TROUBLESHOOTING

### Deployment stuck or failing?

1. **Check GitHub Actions logs**:
   - Go to Actions tab in GitHub
   - Click on the failed run
   - Expand the failed step to see error

2. **Common issues**:
   - ❌ SSH key invalid → Re-generate and add to GitHub Secrets
   - ❌ AWS credentials invalid → Check AWS_ROLE_ARN secret
   - ❌ Migration failed → Check database state manually
   - ❌ Service restart failed → SSH and restart manually

3. **Manual rollback**:
   ```bash
   ssh ubuntu@cm.digital-get.com
   cd /opt/marche-cm/backend
   git reset --hard HEAD~1
   python manage.py migrate
   sudo systemctl restart marche-cm-django
   ```

---

## 📊 COST & PERFORMANCE

**GitHub Actions cost**: Free (public repos) or included in GitHub Pro/Enterprise  
**Deployment time**: ~25 min total (15 min backend + 10 min AWS)  
**Downtime**: 0 min (services restarted in background)  

---

**Status**: 🟢 **Ready to Deploy**

**Next action**: `git push origin aws-infra` to trigger automatic deployment!
