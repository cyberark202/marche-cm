# Déploiement v1 production — Marché CM

Date : 2026-05-30
Portée : mise en production de la **première version** : backend (API + temps réel + workers) et les **4 applications** Flutter (`Clients` acheteur, `app` multi-rôles, `Driver App` livreur, `admin` console).

> Le détail backend Render existe déjà dans `RENDER_DEPLOIEMENT.md` et `RENDER_DEPLOY_CHECKLIST.md`. Ce document orchestre l'ensemble **bout en bout** et ajoute la partie **apps mobiles** (non couverte ailleurs).

---

## 0. Pré-requis & ordre de déploiement

```
1. Provisionner infra (Postgres, Redis, S3/stockage, SMTP, NotchPay live)
2. Déployer le backend (migrations + collectstatic + healthcheck)
3. Configurer webhooks NotchPay → URL backend
4. Smoke test API (health, login, wallet, webhook signé)
5. Builder + publier les 4 apps avec API_BASE_URL = URL backend prod
6. Smoke test apps (login par rôle, paiement test, KYC, litige)
7. Bascule DNS / ouverture publique
```

---

## 1. Infrastructure (managé recommandé : Render)

| Composant | Service | Notes |
|---|---|---|
| API ASGI | Web Service Python | `daphne -b 0.0.0.0 -p $PORT config.asgi:application` |
| Worker Celery | Background Worker | `celery -A config worker -l info` |
| Beat Celery | Cron/Worker | `celery -A config beat -l info` (réconciliation auto, retries payout) |
| PostgreSQL | Managé | `DATABASE_URL` |
| Redis | Managé | `REDIS_URL` — **obligatoire** (throttle + channels distribués, cf. pen-test §3.1) |
| Stockage médias | S3/compatible | `DEFAULT_FILE_STORAGE` + `AWS_*` (preuves livraison, KYC) — `REQUIRE_REMOTE_PROOF_STORAGE=True` en prod |
| Email | SMTP | OTP step-up + notifications (cf. pen-test §3.2) |

L'image est buildée via `backend/Dockerfile` (multi-stage Python 3.12-slim, `collectstatic` au build, healthcheck `/api/health/`, CMD `daphne`).

---

## 2. Variables d'environnement backend (critiques)

Reprendre intégralement `RENDER_DEPLOY_CHECKLIST.md`. Bloc minimal **bloquant** :

```env
DEBUG=False
SECRET_KEY=<aléatoire ≥50 chars>
ALLOWED_HOSTS=api.marche-cm.com,<service>.onrender.com
BACKEND_PUBLIC_URL=https://api.marche-cm.com
USE_X_FORWARDED_PROTO=True
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
SECURE_HSTS_SECONDS=31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
SECURE_HSTS_PRELOAD=True
CSRF_TRUSTED_ORIGINS=https://api.marche-cm.com

DATABASE_URL=postgres://...
REDIS_URL=redis://...
CACHE_URL=redis://...

DATA_ENCRYPTION_KEY=<clé Fernet>
JWT_ALGORITHM=RS256
JWT_SIGNING_KEY=<clé privée RSA PEM>

EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=...
EMAIL_HOST_USER=...
EMAIL_HOST_PASSWORD=...
DEFAULT_FROM_EMAIL=no-reply@marche-cm.com

CORS_ALLOW_ALL_ORIGINS=False
CORS_ALLOWED_ORIGINS=https://app.marche-cm.com

NOTCHPAY_ENABLED=True
NOTCHPAY_MODE=live
NOTCHPAY_LIVE_PUBLIC_KEY=...
NOTCHPAY_LIVE_PRIVATE_KEY=...
NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=<obligatoire>
NOTCHPAY_DISBURSE_WEBHOOK_SECRET=<obligatoire>
```

> Ne **jamais** définir `ENABLE_DEBUG_BYPASS`, `DEBUG_BYPASS_TOKEN`, `DEVICE_FINGERPRINT_SECRET` en prod. `marche-cm.env` ne doit contenir aucun secret réel (cf. pen-test §4.4).

---

## 3. Procédure backend

```bash
# 1. Migrations
python manage.py migrate --noinput
# 2. Static
python manage.py collectstatic --noinput
# 3. (Optionnel) seed initial / superuser RBAC GENERAL_ADMIN
python manage.py createsuperuser   # puis affecter le rôle GENERAL_ADMIN
# 4. Healthcheck
curl -fsS https://api.marche-cm.com/api/health/
# 5. Audit sécurité env
bash scripts/security_audit.sh
```

Tests avant deploy : `cd backend && python manage.py test` (doit être vert).

Webhooks NotchPay (dashboard fournisseur) :
- Checkout → `https://api.marche-cm.com/api/wallets/notchpay/checkout/webhook/`
- Disburse → `https://api.marche-cm.com/api/wallets/notchpay/disburse/webhook/`
- Renseigner les secrets correspondants côté env (sinon **rejet 403** — comportement voulu).

---

## 4. Applications Flutter (4 builds)

Toutes les apps lisent l'URL backend via `--dart-define=API_BASE_URL=...` (sinon défaut `https://marche-cm.onrender.com`). **HTTPS obligatoire en release** (crash fast sinon).

| App | Dossier | Package | Cible store | Firebase |
|---|---|---|---|---|
| Acheteur | `frontend/Clients` | `clients_app` | Play / App Store | Non |
| Multi-rôles (vendeur/grossiste/transitaire) | `frontend/app` | `marche_cm` | Play / App Store | Oui (FCM) |
| Livreur | `frontend/Driver App/app` | `driver_app` | Play / App Store | Oui (FCM) |
| Admin | `frontend/admin/project` | `project` *(à renommer `marche_cm_admin`)* | Distribution interne (pas de store public) | Non |

### 4.1 Pré-build (chaque app)
```bash
flutter pub get
flutter analyze        # doit être vert (vérifié : les 4 apps = 0 issue)
flutter test           # smoke tests verts
```

### 4.2 Build Android (release)
```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.marche-cm.com \
  --dart-define=GOOGLE_CLIENT_ID=<oauth_android>      # app/Clients si Google Sign-In
```
- Signature : configurer `key.properties` + keystore (par app, ne pas réutiliser).
- `app`/`Driver App` : fournir `google-services.json` (FCM) avant build.
- Icônes : `flutter pub run flutter_launcher_icons` (config présente dans `app/pubspec.yaml`).

### 4.3 Build iOS (release)
```bash
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.marche-cm.com
```
- `app`/`Driver App` : `GoogleService-Info.plist` (FCM) + APNs.
- Provisioning profiles + certificats par bundle id.

### 4.4 Admin (distribution interne)
La console admin n'est **pas** destinée aux stores publics. Distribuer en interne (Android APK signé via MDM/Firebase App Distribution ; iOS via TestFlight interne ou Ad-Hoc). Renommer le package `project` → `marche_cm_admin` avant build (mettre à jour `package:project/...` dans `test/`).

---

## 5. Smoke tests post-déploiement

### Backend
- [ ] `/api/health/` 200
- [ ] `POST /api/auth/login/` (compte test par rôle) → tokens
- [ ] `GET /api/auth/me/` → rôle correct
- [ ] Webhook checkout signé → 200 ; non signé → 403
- [ ] `GET /metrics/` réservé `GENERAL_ADMIN`

### Apps (par rôle)
- [ ] **Acheteur** : login, catalogue, panier, recharge wallet (test NotchPay), commande, suivi, chat.
- [ ] **Vendeur** : dashboard, produit, commande reçue, RFQ, revenus.
- [ ] **Livreur** : demandes, devis, course, preuve livraison (photo + code 4 chiffres).
- [ ] **Admin** : login (GENERAL_ADMIN only), dashboard, KYC review, arbitrage litige, **réconciliation avec step-up 2FA**, export audit CSV.
- [ ] **KYC** : flux CNI recto + verso + **signature** + soumission → document `PENDING` visible côté admin.

---

## 6. Rollback & observabilité

- **Rollback backend** : redeploy de l'image précédente (Render keep N builds) ; migrations réversibles — éviter les migrations destructives non backwards-compatibles pour v1.
- **Rollback apps** : conserver l'AAB/IPA précédent ; staged rollout Play (10 % → 100 %).
- **Observabilité** : Prometheus `/metrics/` (latence/erreurs), logs structurés, alertes FinOps (`FINOPS_ALERT_*`) sur écarts de réconciliation et backlog de retries payout.

---

## 7. Go / No-Go v1

**GO** si : checklist sécurité (`PENTEST_BACKEND.md` §6) cochée, Redis + SMTP + RS256 + secrets webhooks en place, 4 apps `analyze`+`test` verts buildées avec l'URL prod, smoke tests §5 OK, campagne d'abus métier (pen-test §5) passée sur staging.

**NO-GO** tant que : `REDIS_URL` absent, `EMAIL_BACKEND=console`, secrets webhooks manquants, ou tests d'abus escrow/IDOR non validés.
