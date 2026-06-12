# SECURITY_AUDIT (2026-06-12) — Audit sécurité MarketCM
**Date :** 2026-06-12 · **Preuves :** sondes HTTP réelles sur `https://cm.digital-get.com`, lecture du code, AWS CLI, suites `tests_security` vertes (accounts 29 + wallets 35), suite complète 319/319 OK.
> Remplace/complète le `SECURITY_AUDIT.md` du 2026-06-08 (conservé). Ce document n'inclut que ce qui a été **exécuté** aujourd'hui.

## 1. Vulnérabilités CRITIQUES trouvées & corrigées

### 🔴 SEC-CRIT-001 — Exposition publique du code source et des documents KYC (CORRIGÉ)
- **Preuve avant** : bucket policy CloudFront sur `market-cm/*` entier →
  - `https://df7t18zqeme69.cloudfront.net/deploy/code.tar.gz` → **HTTP 200** (base de code backend, 354 KB, téléchargeable anonymement).
  - `https://df7t18zqeme69.cloudfront.net/compliance/<doc>.jpg` → **HTTP 200** (documents d'identité KYC réels).
- **Impact** : divulgation du code + **fuite de données personnelles sensibles** (identités).
- **Correctif appliqué & vérifié** : bucket policy restreinte aux seuls préfixes publics `products/*` et `avatars/*` ; invalidation CloudFront. **Re-test : compliance → 403, deploy → 403, produit public → 200.** ✅

## 2. Vulnérabilités MOYENNES / défense en profondeur
### 🟠 SEC-MED-001 — Bypass global de rate-limiting via header secret
`config/throttles.py:77` : header `x-loadtest-bypass-token == LOADTEST_BYPASS_TOKEN` (présent en SSM prod) **désactive tout le rate-limiting**. Si le token fuite → anti-bruteforce contourné. **Recommandation** : blanchir le paramètre SSM hors campagne + purger l'historique git. Signalé (action exploitant).

### 🟠 SEC-MED-002 — IAM user humain `central-market` en AdministratorAccess
Surface large si la clé CLI fuite. Recommandation : scoping + MFA. Signalé.

### 🟠 SEC-MED-003 — Volume EBS racine non chiffré
`vol-0806f94cad0e69433` non chiffré (RDS/S3 le sont). Remédiation via snapshot chiffré (interruption). Signalé.

## 3. Contrôles vérifiés CONFORMES (sondes live)
| Contrôle | Test | Résultat |
|---|---|---|
| Broken Access Control / IDOR | 8 endpoints sensibles anonymes | **401** partout ✅ |
| Brute force login | 15 tentatives | **429 dès la 5e** ✅ |
| Host header injection | `Host: evil.com` | **400** ✅ |
| Path traversal | `/media/../../etc/passwd` | **404** ✅ |
| SQL injection | `?search=' OR 1=1--` | 200 sans erreur (ORM paramétré) ✅ |
| TRACE (XST) | `TRACE /api/health/` | **405** ✅ |
| Fuite version serveur | headers | aucune (`Server: nginx`) ✅ |
| HTTP→HTTPS | `http://` | **301** ✅ |
| HSTS | header | `max-age=63072000; includeSubDomains; preload` ✅ |
| CSP | header | `default-src 'none'` strict ✅ |
| X-Frame / X-Content-Type | headers | `DENY` / `nosniff` ✅ |
| Swagger/Redoc prod | `/api/schema/swagger/` | **404** ✅ |
| Django admin | `/admin/` | **404** ✅ |
| Metrics Prometheus | `/metrics/` | **404** anonyme (RBAC) ✅ |
| WebSocket hijacking | upgrade sans token | **403** ✅ |

## 4. Contrôles vérifiés par code
- **Uploads / magic bytes** : `apps/accounts/upload_security.py` (`_peek_magic_bytes`) valide les octets de tête + extension + taille. ✅
- **Mass assignment** : `is_active` read-only forcé serveur (test dédié). ✅
- **Secrets** : SSM SecureString + KMS conditionné `ViaService=ssm` ; placeholders dans le dépôt. ✅ (⚠️ historique git — SEC-MED-001).
- **JWT** : RS256, access 15 min / refresh 7 j. ✅
- **Middleware sécurité** : CorrelationID, SecurityHeaders, RequestSizeLimit, SuspiciousRequest (scoring live observé). ✅

## 5. Surface d'endpoints
Aucun endpoint de debug/dangereux exposé. `AUTH_LOCKDOWN` disponible. Catch-all WS ferme proprement (4404).

## 6. Synthèse corrections
| ID | Sévérité | État |
|---|---|---|
| SEC-CRIT-001 exposition S3/CloudFront (code + KYC) | Critique | ✅ CORRIGÉ & re-testé |
| IAM S3Express policy superflue | Faible | ✅ détachée & re-testée |
| SEC-MED-001 bypass rate-limit token | Moyenne | ⚠️ signalé |
| SEC-MED-002 IAM admin humain | Moyenne | ⚠️ signalé |
| SEC-MED-003 EBS non chiffré | Moyenne | ⚠️ signalé |
