# PRODUCTION DEPLOYMENT GUIDE
**Date**: 2026-06-09  
**Commit**: 45a1bd9 (Implement 5 security + performance improvements)  
**Branch**: aws-infra (protected)  

---

## 🚀 DEPLOYMENT CHECKLIST

### ✅ PRE-DEPLOYMENT (COMPLETED)

- [x] 5 improvements implemented & tested
- [x] 29/29 security tests passing
- [x] Git commit created: 45a1bd9
- [x] Changes pushed to aws-infra branch
- [x] Branch protection configured

### 📋 DEPLOYMENT STEPS

#### **STEP 1: Backend Deployment** (10-15 min)

**SSH to production server:**
```bash
ssh ubuntu@cm.digital-get.com

# Navigate to app directory
cd /opt/marche-cm/backend

# Pull latest changes
git fetch origin aws-infra:aws-infra
git checkout aws-infra
git pull origin aws-infra

# Install dependencies (if needed)
pip install -r requirements.txt

# Apply database migrations
python manage.py migrate

# Restart Django services
sudo systemctl restart marche-cm-django
sudo systemctl restart marche-cm-daphne
```

**Verify:**
```bash
curl https://cm.digital-get.com/api/health/
# Should return: {"status": "OK"}
```

---

#### **STEP 2: JWT Token Rotation Verification** (5 min)

Test that token refresh works with rotation:

```bash
# 1. Get access token
TOKEN=$(curl -s -X POST https://cm.digital-get.com/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"..."}' \
  | jq -r '.refresh')

# 2. Refresh token
curl -X POST https://cm.digital-get.com/api/auth/refresh/ \
  -H "Content-Type: application/json" \
  -d "{\"refresh\":\"$TOKEN\"}"
  
# Expected: New access + refresh tokens issued
# Old refresh token invalidated
```

---

#### **STEP 3: Database Migration** (5-10 min)

Apply composite indexes:

```bash
# SSH to production
ssh ubuntu@cm.digital-get.com

cd /opt/marche-cm/backend

# Apply migration
python manage.py migrate orders 0007

# Verify indexes created
psql -d marche_cm -c "SELECT * FROM pg_indexes WHERE tablename = 'orders_order';"

# Should show:
# idx_order_buyer_status_date
# idx_order_seller_status_date
```

---

#### **STEP 4: AWS Infrastructure (Terraform)** (5-10 min)

Deploy S3 encryption + versioning:

```bash
cd /opt/marche-cm/infra/terraform

# Review changes
terraform plan

# Apply changes
terraform apply

# Verify S3 encryption
aws s3api head-bucket --bucket marche-cm-media \
  --query ServerSideEncryptionConfiguration

# Verify versioning
aws s3api get-bucket-versioning --bucket marche-cm-media
```

---

#### **STEP 5: Cache Invalidation Signals** (0 min)

No action needed — signals active automatically after Django restart.

**Verify:**
```bash
# Monitor logs for cache invalidation
journalctl -u marche-cm-django -f | grep "cache.delete"
```

---

### 🔍 POST-DEPLOYMENT VERIFICATION

| Check | Command | Expected |
|-------|---------|----------|
| API Health | `curl https://cm.digital-get.com/api/health/` | `{"status":"OK"}` |
| JWT Rotation | Refresh token endpoint | New tokens issued |
| Database | `pg_indexes` query | 2 new indexes |
| S3 Encryption | `head-bucket` query | `AES256` |
| S3 Versioning | `get-bucket-versioning` query | `Enabled` |
| Cache Signals | App logs | `cache.delete` events |
| Payment API | Test NotchPay charge | Transaction completes |
| WebSocket | `curl ws://api/ws/chat/` | Connection accepted |

---

### 🛡️ BRANCH PROTECTION (GitHub)

**Branch Rules for `aws-infra`:**

```
✅ Require a pull request before merging
✅ Dismiss stale pull request approvals
✅ Require 1 approval review
✅ Require status checks to pass (CI/CD)
✅ Require branches to be up to date
✅ Enforce all above rules for admins
✅ Restrict who can push (none — PR required)
```

**To merge to main:**
1. Create PR: `aws-infra` → `main`
2. Get 1 approval
3. Merge (not squash — preserve history)

---

### ⚠️ ROLLBACK PLAN

If anything breaks:

```bash
# Revert to previous commit
git revert 45a1bd9

# OR checkout previous version
git checkout 7368eb2  # Previous stable

# Restart services
sudo systemctl restart marche-cm-django marche-cm-daphne

# For database: remove indexes if needed
# (migration is non-destructive, safe to leave)
```

---

### 📊 SUCCESS CRITERIA

✅ All 5 improvements deployed  
✅ Tests passing in production  
✅ No errors in logs (24h check)  
✅ API response time <500ms (P95)  
✅ Payment success rate >99%  
✅ WebSocket connections stable  

---

### 🎯 NEXT STEPS

1. **Immediate**: Follow deployment steps 1-4 above
2. **24h**: Monitor logs for errors
3. **1 week**: Check metrics (latency, error rate)
4. **Future improvements**:
   - Token rotation enforcement (current: optional)
   - S3 KMS encryption (current: AWS-managed)
   - Read replicas for load scaling

---

**Status**: Ready to deploy ✅

**Questions?** Check the AWS_AUDIT.md or IMPLEMENTATION_SUMMARY.md for details.
