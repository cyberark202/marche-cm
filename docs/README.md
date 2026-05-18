# Marche CM - Flutter + Django

Plateforme marketplace B2B/B2C avec wallet, logistique et temps reel. Le repo contient le backend Django + Channels et l'app mobile Flutter, avec ecrans par role et flux metier complets (catalogue, commandes, sequestre, livraison, wallet, chat, conformite).

## Roles utilisateurs
- `GENERAL_ADMIN` (admin general): gouvernance globale, audit, reconciliation wallet, decisions litiges, gestion des comptes.
- `SUPPLIER` (fournisseur): publie des produits, repond aux demandes, vend aux acheteurs.
- `WHOLESALER` (grossiste): publie des produits, vend en gros, traite des commandes B2B/B2C.
- `TRANSIT_AGENT` (transitaire): propose des devis, gere les expeditions, preuves de livraison, litiges, notation.
- `BUYER` (acheteur): consulte le catalogue, passe commande, suit la livraison, ouvre un litige si besoin.

## Relations entre utilisateurs
- Acheteur <-> Fournisseur/Grossiste: consultation catalogue, commande, chat, confirmation de livraison.
- Fournisseur/Grossiste <-> Transitaire: demandes de devis, selection du transitaire, suivi expedition.
- Acheteur <-> Transitaire: suivi livraison, preuve de livraison, notation, ouverture/gestion litige.
- Admin general <-> Tous: supervision, export audit, reconciliation wallet, validation/rejet litiges, controle conformite.
- Fournisseur/Grossiste/Transitaire -> Admin general: soumission de documents KYC/conformite pour verification.
- RFQ B2B: un demandeur publie une RFQ, les vendeurs repondent avec des offres.

## Fonctionnalites principales
- Gestion des roles et ecrans dedies par role.
- Authentification email avec verification, login en 2 etapes (code email), et Google Sign-In.
- Catalogue produits: images/videos, prix min/max, quantite min/max, marque, categorie.
- Commandes: quantite, regroupage, choix transitaire prefere.
- Sequestre (escrow) avec statut `HELD` puis `RELEASED` apres confirmation livraison.
- Wallet interne:
  - Recharge/retrait avec OTP + PIN.
  - Statuts `PENDING/SUCCESS/FAILED`, idempotence, reconciliation admin.
  - Integrations NotchPay (payments + transfers + webhooks).
  - Moyens: Mobile Money, Orange Money, Visa, MasterCard.
- Logistique:
  - Profils transport.
  - Devis d'expedition, acceptation, mise a jour statut.
  - Preuves de livraison, litiges, notation transitaire.
- Conformite/KYC: documents, types de certification, review admin.
- Chat temps reel (WebSocket) + etats messages `SENT/DELIVERED/READ`.
- Campagnes/ads image/video (reservees a certains roles).
- Notifications temps reel multi-domaines (produits, commandes, logistique, wallet, compliance).

## Arborescence
- `backend/`: API Django + Channels.
- `frontend/`: app Flutter (structure par features).

## Documents juridiques
- `LEGAL/CONDITIONS_UTILISATION.md`: Conditions d'utilisation de la plateforme.
- `LEGAL/POLITIQUE_CONFIDENTIALITE.md`: Politique de confidentialite (collecte, traitement, droits).

## Demarrage backend
```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
python manage.py makemigrations
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

## Guide NotchPay
- Voir [`backend/NOTCHPAY_SETUP.md`](backend/NOTCHPAY_SETUP.md) pour la configuration dashboard + variables `.env`.

## Configuration production (PostgreSQL + Redis)
Le backend supporte:
- PostgreSQL via `DATABASE_URL` (ou `DB_ENGINE=postgres` + `DB_*`)
- Redis pour Channels via `REDIS_URL`
- Cache Redis optionnel via `CACHE_URL` (ou fallback automatique sur `REDIS_URL`)
- Chiffrement applicatif des champs PII utilisateur (`phone_number`, `city`, `location_label`) via `DATA_ENCRYPTION_KEY` (+ rotation possible via `DATA_ENCRYPTION_FALLBACK_KEYS`)

Exemple `.env` production:
```env
DEBUG=False
ALLOWED_HOSTS=api.example.com
CSRF_TRUSTED_ORIGINS=https://api.example.com
USE_X_FORWARDED_PROTO=True
DATA_ENCRYPTION_KEY=replace-with-a-long-random-secret
DATA_ENCRYPTION_FALLBACK_KEYS=

DATABASE_URL=postgresql://marche_user:strongpass@127.0.0.1:5432/marche_cm
REDIS_URL=redis://127.0.0.1:6379/0
CACHE_URL=redis://127.0.0.1:6379/1
```

Démarrage ASGI recommandé:
```bash
cd backend
python manage.py migrate
daphne -b 0.0.0.0 -p 8000 config.asgi:application
```

Lancer l'infra locale Postgres + Redis:
```bash
cd backend
docker compose -f docker-compose.infra.yml up -d
```

## Deploiement propre sur Render (recommande)
Le repo contient un blueprint Render pret a l'emploi: `render.yaml` (a la racine).
Checklist detaillee production (env vars, workers, healthchecks, webhooks): `RENDER_DEPLOY_CHECKLIST.md`.

### 1) Preparer le depot
```bash
git add .
git commit -m "Add Render production config"
git push origin main
```

### 2) Creer les services sur Render via Blueprint
1. Dans Render, cliquez **New +** > **Blueprint**.
2. Connectez votre repo.
3. Render detecte `render.yaml` et cree:
- `marche-cm-api` (Web Service Python, Daphne ASGI)
- `marche-cm-db` (PostgreSQL)
- `marche-cm-redis` (Key Value Redis)

### 3) Variables a verifier dans Render (service web)
- `DEBUG=False`
- `ALLOWED_HOSTS=.onrender.com` (ajoutez votre domaine custom si besoin)
- `CSRF_TRUSTED_ORIGINS=https://*.onrender.com` (ajoutez domaine custom en https)
- `DATA_ENCRYPTION_KEY` (secret de chiffrement at-rest, ne jamais changer sans plan de rotation)
- `DATA_ENCRYPTION_FALLBACK_KEYS` (optionnel, liste comma-separated des anciennes cles pour decryption pendant rotation)
- `DATABASE_URL` (injecte depuis la DB Render)
- `REDIS_URL` et `CACHE_URL` (injectes depuis Redis Render)

### 4) Build, migration et lancement
Le blueprint configure deja:
- Build: `pip install -r requirements.txt && python manage.py collectstatic --noinput`
- Pre-deploy: `python manage.py migrate --noinput`
- Start: `daphne -b 0.0.0.0 -p $PORT config.asgi:application`
- Healthcheck: `/api/health/`

### 5) Connecter le frontend Flutter
Utilisez l'URL Render du backend:
```bash
flutter run --dart-define=API_BASE_URL=https://<votre-service>.onrender.com
```

### 6) Important pour les fichiers uploades
Render a un filesystem ephemere. Les uploads (`media/`) ne sont pas persistants entre redeploiements.
Pour un environnement production, branchez un stockage objet (S3/Cloudinary/R2) pour `MEDIA_ROOT`.

### SSL/TLS (Render)
- Sur Render, le certificat SSL public est gere automatiquement pour `*.onrender.com`.
- Pour un domaine custom, ajoutez le domaine dans Render (`Custom Domains`) puis attendez l'emission automatique du certificat TLS.
- Gardez `SECURE_SSL_REDIRECT=True`, `SESSION_COOKIE_SECURE=True`, `CSRF_COOKIE_SECURE=True`, `USE_X_FORWARDED_PROTO=True`.

### SSL local (certificat de dev auto-signe)
Generer un certificat local:
```bash
cd backend
python scripts/generate_dev_ssl_cert.py
```

Lancer Daphne en HTTPS local:
```bash
daphne -e "ssl:8443:privateKey=certs/dev-localhost.key.pem:certKey=certs/dev-localhost.crt.pem" config.asgi:application
```

### Rotation de cle de chiffrement PII (sans downtime)
1. Definir la nouvelle cle dans `DATA_ENCRYPTION_KEY`.
2. Mettre l'ancienne cle dans `DATA_ENCRYPTION_FALLBACK_KEYS`.
3. Executer:
```bash
cd backend
python manage.py rotate_encrypted_user_pii
```
4. Verifier les logs/tests.
5. Retirer ensuite l'ancienne cle de `DATA_ENCRYPTION_FALLBACK_KEYS`.

## API (principaux endpoints)
- `GET /api/users/` et `GET /api/users/online/`
- `POST /api/users/create_managed_user/` (admin general)
- `GET/POST /api/compliance-documents/` et `POST /api/compliance-documents/{id}/review/`
- `GET/POST /api/products/`
- `GET/POST /api/orders/`
- `POST /api/orders/{id}/confirm_delivery/`
- `GET /api/wallets/`
- `POST /api/wallets/request_otp/`
- `POST /api/wallets/topup/`
- `POST /api/wallets/withdraw/`
- `POST /api/wallets/notchpay/checkout/webhook/`
- `POST /api/wallets/notchpay/disburse/webhook/`
- `POST /api/wallets/reconcile/` (admin)
- `GET /api/wallets/transactions/`
- `GET/POST /api/chat/rooms/`
- `GET/POST /api/chat/messages/`
- `POST /api/chat/messages/{id}/mark_delivered/`
- `POST /api/chat/messages/{id}/mark_read/`
- `GET/POST /api/campaigns/`
- `GET/POST /api/rfqs/`
- `GET/POST /api/rfq-offers/`
- `GET/POST /api/transport-profiles/`
- `GET/POST /api/shipments/`
- `POST /api/shipments/{id}/post_quote/`
- `POST /api/shipments/{id}/accept_quote/`
- `POST /api/shipments/{id}/update_status/`
- `POST /api/shipments/{id}/submit_proof/`
- `POST /api/shipments/{id}/validate_delivery/`
- `POST /api/shipments/{id}/open_dispute/`
- `POST /api/shipments/{id}/rate_transit_agent/`
- `GET /api/transport-quotes/`
- `GET/POST /api/shipment-disputes/`
- `POST /api/shipment-disputes/{id}/decide/` (admin)

Auth/Admin:
- `POST /api/auth/logout/` (revoke refresh token)
- `POST /api/auth/wallet-pin/`
- `GET /api/admin/dashboard/`
- `GET /api/admin/audit/export/`
- `GET /api/health/`

WebSocket:
- `ws://localhost:8000/ws/chat/<room_id>/`
- `ws://localhost:8000/ws/events/?topics=products,orders,chat,logistics,analytics,profiles,wallets,compliance`

## Demarrage frontend
```bash
cd frontend/app
flutter pub get
flutter run
```

Si l'API Django est sur une autre machine/IP:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
```

## Auth Google + Validation Email
- Endpoints auth:
  - `POST /api/auth/register/` (cree compte `is_active=False` + envoi email validation)
  - `GET /api/auth/verify-email/?token=...` (active le compte)
  - `POST /api/auth/login/` (etape 1: `email + password`, envoie un code 6 chiffres par email)
  - `POST /api/auth/login/verify/` (etape 2: `challenge_token + code`, retourne JWT)
  - `POST /api/auth/google/` (login/signup via token Google)
  - `GET /api/auth/me/`

### 1) Config backend `.env`
Dans `backend/.env` (copie de `.env.example`):
```env
BACKEND_PUBLIC_URL=http://127.0.0.1:8000
GOOGLE_CLIENT_ID=xxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com

EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
DEFAULT_FROM_EMAIL=no-reply@marche-cm.local
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=votre_email@gmail.com
EMAIL_HOST_PASSWORD=votre_mot_de_passe_app
```

Note:
- En local dev, vous pouvez garder `EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend` pour afficher le lien de validation dans la console Django.

### 2) Config Google Cloud
Creer dans Google Cloud Console:
- OAuth 2.0 Client ID de type **Web** (pour le backend, verification du token): valeur dans `GOOGLE_CLIENT_ID`.
- OAuth 2.0 Client ID de type **Android**:
  - package: `com.example.app` (ou votre package final)
  - SHA-1 debug/release selon build.
- OAuth 2.0 Client ID de type **iOS** (si iOS cible).

### 3) Lancer Flutter avec les IDs Google
Android emulator:
```bash
flutter run ^
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 ^
  --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com
```

Pour iOS ajoutez aussi:
```bash
--dart-define=GOOGLE_CLIENT_ID=xxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com
```

### 4) iOS URL Scheme (obligatoire Google Sign-In iOS)
Dans `ios/Runner/Info.plist`, ajouter le `CFBundleURLTypes` avec la valeur `REVERSED_CLIENT_ID` du fichier `GoogleService-Info.plist`.

## Regles metier a finaliser ensuite
- Repartition escrow en 3 parties (vendeur, transitaire, commission plateforme).
- Workflow UX mobile complet (offline/retry, accessibilite avancee, i18n complete).
- Monitoring/alerting externe (Sentry/Prometheus/Grafana) selon votre stack infra.

## Exploitation FinOps (wallet/escrow)
- Commande unique d'exploitation:
```bash
cd backend
python manage.py run_financial_ops --send-alerts
```
- Retry payouts uniquement (recommande toutes les 3 minutes):
```bash
python manage.py run_financial_ops --skip-reconciliation --retries-limit 200 --send-alerts
```
- Reconciliation stricte uniquement (recommande 00:10 chaque nuit):
```bash
python manage.py run_financial_ops --skip-retries --strict-provider-balance --send-alerts --fail-on-alert
```

Variables d'environnement FinOps:
- `FINOPS_PROVIDER_BALANCE_URL`, `FINOPS_PROVIDER_BALANCE_AUTH_TOKEN`, `FINOPS_PROVIDER_BALANCE_JSON_PATH`
- `FINOPS_PROVIDER_REAL_BALANCE` (fallback manuel temporaire)
- `FINOPS_ALERT_EMAILS`, `FINOPS_ALERT_WEBHOOK_URL`

## Temps reel (WebSocket)
- Flux global `ws/events` branche dans les ecrans Produits, Video, Chat, Commande, Profils.
- Flux logistique live (devis, statut expedition, preuve, litige, notation) dans l'espace transitaire.
- Les pages secondaires (RFQ, Offres, Campagnes, Conformite, Profil transport, Litiges) se rafraichissent automatiquement sur evenement WebSocket.
"# marche-cm" 
