# Checklist Render - Deploiement Production

## 0) Validation avant deploy
Lancer la suite backend depuis le dossier `backend`:

```bash
cd backend
python manage.py test
```

Reference actuelle: **26 tests OK**.

## 1) Services Render a avoir
- Web Service Python (ASGI): `daphne -b 0.0.0.0 -p $PORT config.asgi:application`
- PostgreSQL managé
- Redis (Channels + cache)

## 2) Variables d'environnement critiques

### Securite HTTP
- `SECRET_KEY` (obligatoire)
- `DATA_ENCRYPTION_KEY` (obligatoire en production pour le chiffrement at-rest des PII)
- `DATA_ENCRYPTION_FALLBACK_KEYS` (optionnel pendant rotation de cle)
- `DEBUG=False`
- `ALLOWED_HOSTS` (inclure domaine Render + domaine custom)
- `CSRF_TRUSTED_ORIGINS` (https uniquement)
- `USE_X_FORWARDED_PROTO=True`
- `SECURE_SSL_REDIRECT=True`
- `SESSION_COOKIE_SECURE=True`
- `CSRF_COOKIE_SECURE=True`
- `SECURE_HSTS_SECONDS=31536000`
- `SECURE_HSTS_INCLUDE_SUBDOMAINS=True`
- `SECURE_HSTS_PRELOAD=True`

### URL publique backend
- `BACKEND_PUBLIC_URL=https://<service>.onrender.com`
- `RENDER_EXTERNAL_URL` et `RENDER_EXTERNAL_HOSTNAME` sont fournis par Render (utilises automatiquement dans `settings.py`).

### Base de donnees / cache / temps reel
- `DATABASE_URL` (depuis service Postgres Render)
- `REDIS_URL` (depuis service Redis Render)
- `CACHE_URL` (meme Redis possible)
- Optionnel tuning:
  - `DB_CONN_MAX_AGE`
  - `DB_CONNECT_TIMEOUT`
  - `CHANNEL_CAPACITY`
  - `CHANNEL_EXPIRY_SECONDS`
  - `CHANNEL_GROUP_EXPIRY_SECONDS`
  - `CHANNEL_REDIS_PREFIX`

### Wallet / NotchPay
- `NOTCHPAY_ENABLED=True`
- `NOTCHPAY_PUBLIC_KEY` (ou `NOTCHPAY_TEST_PUBLIC_KEY` / `NOTCHPAY_LIVE_PUBLIC_KEY`)
- `NOTCHPAY_PRIVATE_KEY` (ou `NOTCHPAY_TEST_PRIVATE_KEY` / `NOTCHPAY_LIVE_PRIVATE_KEY`)
- `NOTCHPAY_API_BASE=https://api.notchpay.co`
- `NOTCHPAY_CURRENCY=XAF`
- `NOTCHPAY_WEBHOOK_TOKEN` (optionnel, defense en profondeur)
- `NOTCHPAY_CHECKOUT_WEBHOOK_SECRET` (**obligatoire en production**)
- `NOTCHPAY_DISBURSE_WEBHOOK_SECRET` (**obligatoire en production**)
- `NOTCHPAY_WITHDRAW_CHANNEL_MTN=cm.mtn`
- `NOTCHPAY_WITHDRAW_CHANNEL_ORANGE=cm.orange`
- `NOTCHPAY_MTN_NUMBER`, `NOTCHPAY_ORANGE_NUMBER` (si auto-payout actif)
- `NOTCHPAY_AUTO_PAYOUT` (`False` tant que flux non valide en production)

### FinOps (wallet/escrow/reconciliation)
- `RECONCILIATION_REQUIRE_PROVIDER_BALANCE=True`
- `FINOPS_PROVIDER_BALANCE_URL` (endpoint solde reel provider)
- `FINOPS_PROVIDER_BALANCE_AUTH_TOKEN` (token API provider)
- `FINOPS_PROVIDER_BALANCE_JSON_PATH` (ex: `data.balance`)
- `FINOPS_ALERT_EMAILS` (liste comma-separated)
- `FINOPS_ALERT_WEBHOOK_URL` (Slack/Teams/webhook ops)

### Auth / Email / Google (selon besoin)
- `GOOGLE_CLIENT_ID` (si login Google actif)
- `EMAIL_BACKEND`, `DEFAULT_FROM_EMAIL`, `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `EMAIL_USE_TLS`
- `AUTH_LOCKDOWN` (mettre `True` temporairement si maintenance/auth stoppee)

## 3) Build / migrate / healthcheck Render
- Build command:
  - `pip install -r requirements.txt && python manage.py collectstatic --noinput`
- Pre-deploy command:
  - `python manage.py migrate --noinput`
- Start command:
  - `daphne -b 0.0.0.0 -p $PORT config.asgi:application`
- Healthcheck path:
  - `/api/health/`

## 4) Workers et scalabilite
- Etat actuel du code: pas de worker asynchrone obligatoire (pas de Celery/RQ en prod ici).
- Pour monter en charge:
  - scaler horizontalement le Web Service (2+ instances),
  - conserver Redis externe pour Channels,
  - augmenter le plan Postgres.
- Si vous ajoutez des taches asynchrones plus tard (emails massifs, retries webhooks, batch analytics), creer un **Background Worker** dedie.

## 5) Webhooks apres deploy

### Webhooks entrants NotchPay
- Checkout URL: `POST /api/wallets/notchpay/checkout/webhook/`
- Disburse URL: `POST /api/wallets/notchpay/disburse/webhook/`
- Header signature attendu: `X-Notch-Signature`
- Signature calculee en HMAC SHA-256 avec:
  - `NOTCHPAY_CHECKOUT_WEBHOOK_SECRET` (checkout)
  - `NOTCHPAY_DISBURSE_WEBHOOK_SECRET` (disburse)
- Optionnel: header token applicatif `X-NotchPay-Token: <NOTCHPAY_WEBHOOK_TOKEN>`

### Webhooks sortants partenaires (feature innovation)
- Creation via `/api/webhook-subscriptions/`
- Contraintes backend:
  - endpoint HTTPS public uniquement,
  - topics limites (`orders`, `shipments`, `wallets`, `analytics`, `compliance`),
  - cooldown sur `send_test` (60s),
  - comptes business verifies requis.

## 5.b) Jobs FinOps a planifier
- Retry payouts toutes les 3 minutes:
  - `python manage.py run_financial_ops --skip-reconciliation --retries-limit 200 --send-alerts`
- Reconciliation quotidienne (00:10):
  - `python manage.py run_financial_ops --skip-retries --strict-provider-balance --send-alerts --fail-on-alert`

## 6) Smoke tests post-deploy
- `GET /api/health/` -> 200
- Auth:
  - `POST /api/auth/register/`
  - `POST /api/auth/login/`
  - `GET /api/auth/me/`
- Wallet:
  - `POST /api/wallets/request_otp/`
  - `POST /api/wallets/topup/`
  - webhook NotchPay checkout/disburse (signature valide)
- Innovation:
  - `POST /api/partner-api-keys/`
  - `POST /api/webhook-subscriptions/`
  - `POST /api/webhook-subscriptions/{id}/send_test/`

## 7) Commandes utiles CI/CD
```bash
cd backend
python manage.py check
python manage.py test
```
