# SECURITY_AUDIT.md — Phase 11 (statique + dynamique passive)

> Méthode : scan statique du code + sondes dynamiques **passives** (read-only) sur prod.
> Périmètre validé : pentest **passif** (pas d'attaque active). Date : 2026-06-18.

## OWASP Top 10 — synthèse
| Catégorie | Preuve | Verdict |
|---|---|---|
| **A01 Broken Access Control / IDOR** | 7/7 endpoints protégés (`wallets, orders, users, ledger, disputes, escrow, kyc`) → **401** sans token | **PASS** |
| **A02 Cryptographic Failures** | TLS Let's Encrypt valide, HSTS preload 2 ans `includeSubDomains` ; secrets Fernet/KMS | **PASS** |
| **A03 Injection (SQLi/RCE)** | Aucun `.raw()/.extra()/cursor.execute` hors tests ; aucun `eval/exec/os.system/subprocess` dans `apps/` | **PASS** |
| **A04 Insecure Design (escrow)** | Double-entrée + invariants prouvés (cf. ESCROW_AUDIT) | **PASS** |
| **A05 Security Misconfiguration** | `/admin/` 404, `/api/schema/` 404, CSP `default-src 'none'`, X-Frame DENY, nosniff | **PASS** |
| **A06 Vulnerable Components** | non scanné ici (pas de `pip-audit`/`osv`) | **NOT VERIFIED** |
| **A07 Auth Failures** | login POST `{}` → 400, GET → 405 ; OTP/MFA (sensitive-action), JWT refresh dédié | **PASS** |
| **A08 Integrity Failures (webhooks)** | webhook HMAC `compare_digest` + timestamp anti-rejeu + montant exact + idempotence (cf. infra) | **PASS** |
| **A09 Logging/Monitoring** | `security.events` logger (suspicious_request scoring observé en test) ; 6 alarmes CloudWatch | **PASS** (PARTIAL: health superficiel I-1) |
| **A10 SSRF** | pas de fetch d'URL utilisateur identifié ; non testé activement | **NOT VERIFIED** |

## Preuves dynamiques passives (prod)
- `.env` / `.git/config` / `/static/.env` / `/api/settings/` → **404** (pas de fuite secret/config).
- Endpoints sensibles → **401** systématique (pas de fuite données non authentifiée).
- **Rate-limiting actif** : 429 dès ~20 req concurrentes/IP (anti-brute-force/anti-DoS).
- `POST /api/auth/login/` sans body → 400 (pas de 500/stacktrace).

## Preuves statiques clés
- **Webhooks paiement** (`AllowAny` légitime) protégés par HMAC SHA-256 `compare_digest`,
  fail-closed si secret absent, timestamp obligatoire (option), 2ᵉ facteur token (`wallets/views.py:267-336`).
- `AllowAny` restant = catalogue public + endpoints auth (register/login/reset) — attendu, pas de surface data.
- `/metrics/` Prometheus gardé par RBAC `IsGeneralAdmin` (pas `is_staff`).
- Suite sécurité exécutée : `accounts/tests_security.py` (29) + `wallets/tests_security.py` (35) = **64 tests sécurité OK**.

## Findings
- **S-1 (MOYEN) — Dépendances non auditées.** Pas de `pip-audit`/`flutter pub outdated` dans cette passe.
  *Reco* : intégrer `pip-audit` + Dependabot/OSV au CI. (A06 = NOT VERIFIED)
- **S-2 (BAS) — SSRF non testé activement.** Pas de vecteur identifié statiquement mais non prouvé. (A10)
- **S-3 (INFO) — Secret NotchPay/Fernet historiquement committé** (mémoire projet, audit API 2026-06-10)
  → **rotation à confirmer**. Vérifier qu'aucun secret live ne subsiste dans l'historique git actif.

## Statut Phase 11
**PASS** sur le cœur OWASP exploitable (A01/A03/A05/A07/A08 prouvés) ;
**NOT VERIFIED** sur A06 (deps) et A10 (SSRF) — pentest actif hors périmètre.
