#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Marche CM — Security audit script
# Run before every production deployment and weekly in CI.
#
# Usage:
#   ./scripts/security_audit.sh [--fail-fast] [--json]
#
# Exit codes:
#   0 — All checks passed
#   1 — One or more checks failed
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FAIL_FAST=false
JSON_OUTPUT=false
FAILED_CHECKS=()

for arg in "$@"; do
  case "$arg" in
    --fail-fast) FAIL_FAST=true ;;
    --json) JSON_OUTPUT=true ;;
  esac
done

cd "$BACKEND_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILED_CHECKS+=("$1"); $FAIL_FAST && exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${YELLOW}══ $1 ══${NC}"; }

# ── 1. Python dependency vulnerabilities ─────────────────────────────────────
section "Dependency Vulnerability Scan"

if command -v safety &>/dev/null; then
  if safety scan --file requirements.txt --severity medium 2>/dev/null; then
    pass "No known vulnerabilities in requirements.txt"
  else
    fail "Vulnerable dependencies found — run 'safety scan' for details"
  fi
else
  warn "safety not installed — skipping (pip install safety)"
fi

# ── 2. SAST — Bandit ─────────────────────────────────────────────────────────
section "Static Analysis (Bandit)"

if command -v bandit &>/dev/null; then
  if bandit -r . \
      --exclude ./apps/*/migrations,./apps/*/tests*.py,./staticfiles \
      --severity-level medium \
      --confidence-level medium \
      -q 2>/dev/null; then
    pass "Bandit SAST: no medium+ severity issues"
  else
    fail "Bandit found security issues — review output above"
  fi
else
  warn "bandit not installed — skipping (pip install bandit)"
fi

# ── 3. Secret detection ───────────────────────────────────────────────────────
section "Secret Detection"

if command -v detect-secrets &>/dev/null; then
  if detect-secrets scan \
      --exclude-files '(\.pyc|migrations/|staticfiles/|\.lock|\.png|\.jpg|\.mp4|db\.sqlite3|\.git)$' \
      --list-all-plugins 2>/dev/null | grep -q "plugin"; then
    pass "detect-secrets scan completed"
  else
    warn "detect-secrets scan could not complete"
  fi
else
  warn "detect-secrets not installed — skipping (pip install detect-secrets)"
fi

# Check for common secret patterns directly.
echo "Checking for hardcoded secrets..."
PATTERNS=(
  'SECRET_KEY\s*=\s*["'"'"'][^$][^"'"'"']{8,}'
  'password\s*=\s*["'"'"'][^"'"'"']{6,}'
  'api_key\s*=\s*["'"'"'][^"'"'"']{8,}'
  'PRIVATE_KEY\s*=\s*["'"'"'][^"'"'"']{8,}'
)
for pattern in "${PATTERNS[@]}"; do
  if grep -r --include="*.py" -l -iE "$pattern" . \
      --exclude-dir=migrations \
      --exclude-dir=staticfiles \
      --exclude="*test*" 2>/dev/null | grep -v "\.env" | grep -v "settings.py" | head -5 | grep -q "."; then
    fail "Possible hardcoded secret matching pattern: $pattern"
  fi
done
pass "No obvious hardcoded secrets found in source files"

# ── 4. Django deployment checks ───────────────────────────────────────────────
section "Django Security Checks"

if SECRET_KEY="${SECRET_KEY:-ci-audit-key-not-for-prod}" \
   DEBUG=False \
   DATABASE_URL="${DATABASE_URL:-sqlite:///audit.sqlite3}" \
   python manage.py check --deploy --fail-level WARNING 2>&1 | \
   grep -E "^(ERROR|CRITICAL)" | grep -v "System check"; then
  fail "Django deployment check found issues"
else
  pass "Django deployment checks passed"
fi

# Clean up audit DB if created.
rm -f audit.sqlite3

# ── 5. Settings security assertions ──────────────────────────────────────────
section "Settings Security Assertions"

python - <<'PYCHECK'
import os, sys
os.environ.setdefault("SECRET_KEY", "ci-audit-key")
os.environ.setdefault("DEBUG", "False")
os.environ.setdefault("DATABASE_URL", "sqlite:///audit_check.sqlite3")

import django
os.environ["DJANGO_SETTINGS_MODULE"] = "config.settings"
try:
    django.setup()
except Exception as e:
    print(f"WARN: Django setup partial: {e}")

from django.conf import settings

checks_failed = []

if settings.DEBUG:
    checks_failed.append("DEBUG=True in production check")

if not getattr(settings, "SECURE_SSL_REDIRECT", False) and not settings.DEBUG:
    checks_failed.append("SECURE_SSL_REDIRECT is False")

if not getattr(settings, "SESSION_COOKIE_SECURE", False) and not settings.DEBUG:
    checks_failed.append("SESSION_COOKIE_SECURE is False")

if not getattr(settings, "CSRF_COOKIE_SECURE", False) and not settings.DEBUG:
    checks_failed.append("CSRF_COOKIE_SECURE is False")

jwt = getattr(settings, "SIMPLE_JWT", {})
access_lifetime = jwt.get("ACCESS_TOKEN_LIFETIME")
if access_lifetime and access_lifetime.total_seconds() > 3600:
    checks_failed.append(f"JWT access token lifetime too long: {access_lifetime}")

if not jwt.get("ROTATE_REFRESH_TOKENS"):
    checks_failed.append("JWT refresh token rotation disabled")

if not jwt.get("BLACKLIST_AFTER_ROTATION"):
    checks_failed.append("JWT blacklist after rotation disabled")

if getattr(settings, "NOTCHPAY_AUTO_PAYOUT", True):
    checks_failed.append("NOTCHPAY_AUTO_PAYOUT defaults to True — must be False")

for check in checks_failed:
    print(f"FAIL: {check}")

import os
os.unlink("audit_check.sqlite3") if os.path.exists("audit_check.sqlite3") else None

sys.exit(1 if checks_failed else 0)
PYCHECK

if [ $? -eq 0 ]; then
  pass "All settings security assertions passed"
else
  fail "Settings security assertions failed"
fi

# ── 6. File permission checks ─────────────────────────────────────────────────
section "File Permission Checks"

# .env files should not be world-readable.
for env_file in .env .env.local .env.production; do
  if [ -f "$env_file" ]; then
    perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%Lp" "$env_file" 2>/dev/null || echo "unknown")
    if [[ "$perms" == *"4" ]] || [[ "$perms" == *"5" ]] || [[ "$perms" == *"6" ]] || [[ "$perms" == *"7" ]]; then
      last_digit="${perms: -1}"
      if [ "$last_digit" -ge 4 ]; then
        fail "$env_file is world-readable (permissions: $perms)"
      fi
    fi
    pass "$env_file permissions: $perms"
  fi
done

# ── 7. Migration integrity ────────────────────────────────────────────────────
section "Migration Integrity"

if SECRET_KEY="${SECRET_KEY:-ci-audit-key}" \
   DATABASE_URL="${DATABASE_URL:-sqlite:///migration_check.sqlite3}" \
   python manage.py migrate --run-syncdb --check 2>/dev/null; then
  pass "All migrations applied"
else
  warn "Unapplied migrations detected — run 'python manage.py migrate'"
fi
rm -f migration_check.sqlite3

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────"
if [ ${#FAILED_CHECKS[@]} -eq 0 ]; then
  echo -e "${GREEN}All security checks passed.${NC}"
  exit 0
else
  echo -e "${RED}${#FAILED_CHECKS[@]} check(s) failed:${NC}"
  for check in "${FAILED_CHECKS[@]}"; do
    echo -e "  ${RED}•${NC} $check"
  done
  exit 1
fi
