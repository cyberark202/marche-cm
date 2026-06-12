# SYSTEM_MAP.md — Cartographie MarketCM
**Date :** 2026-06-12 · **Méthode :** exploration réelle du dépôt + appels AWS CLI authentifiés (compte 958924735829, eu-north-1)

## 1. Backend Django (backend/)

- **Framework :** Django 5.1.6 + DRF + Channels (Daphne) + Celery — vérifié par exécution (`python -c "import django"` → 5.1.6)
- **Settings :** `config/settings.py` (885 lignes), DB via `DATABASE_URL` (PostgreSQL prod / SQLite fallback), secrets via SSM → `.env` (placeholders `<<...>>` dans le dépôt, secrets externalisés)

### 1.1 Apps métier (18)
| App | Domaine |
|---|---|
| accounts | Auth (OTP login, JWT, register par rôle, KYC acheteur, sessions, PIN wallet, suspension) |
| catalog | Produits, favoris, filtres sauvegardés, vidéos (likes/commentaires) |
| orders | Commandes + `OrderFinanceService.cancel_order` (annulation atomique) |
| wallets | Wallet 3 soldes (available/locked/pending), NotchPay checkout + direct charge, retraits, réconciliation |
| escrow | Holds séquestre + state machine + tâches |
| ledger | **Comptabilité double entrée** (LedgerAccount/Transaction/Entry, soldes matérialisés) |
| logistics | Shipments, transport profiles/quotes, litiges livraison |
| disputes | Litiges commande |
| chat | Messagerie (rooms/messages) |
| notifications | Notifications + FCM |
| realtime | WebSocket consumers (/ws/notifications/, /ws/chat/<id>/, /ws/tracking/<id>/, /ws/dashboard/) + fallback 4404 |
| compliance | KYC applications |
| fraud | Assessments + risk profiles |
| audit | AuditEvent + export |
| analytics | Campagnes groupées, RFQ |
| innovation | Loyalty, escrow-split preview, webhooks partenaires, API keys |
| support | Tickets |

### 1.2 Couche transverse (core/)
`core/permissions` (RBAC, IsGeneralAdmin), `core/locks`, `core/state_machine`, `core/events`, `core/repositories`, `core/services`, `core/observability`, `core/exceptions`

### 1.3 Middleware (ordre vérifié dans settings.py:256)
CorrelationID → Security → WhiteNoise → CORS → SecurityHeaders → RequestSizeLimit → Session → Common → CSRF → Auth → Messages → XFrameOptions → SuspiciousRequest

### 1.4 Surface API (config/urls.py — vérifiée)
- 33 ViewSets routés (`/api/...`) + ~25 routes auth/admin/innovation dédiées
- `AUTH_LOCKDOWN` peut désactiver register/login/refresh/google
- Swagger/Redoc montés **uniquement** si `ENABLE_API_DOCS` (défaut DEBUG) ; schéma protégé par permissions
- `/metrics/` Prometheus protégé par `IsGeneralAdmin` (RBAC, pas is_staff)
- `/api/health/` public — vérifié en prod : HTTP 200

### 1.5 WebSocket (config/asgi.py — vérifié)
ProtocolTypeRouter + AllowedHostsOriginValidator + AuthMiddlewareStack ; patterns realtime + legacy chat/events + catch-all close 4404.

### 1.6 Celery
Broker = `CELERY_BROKER_URL`/`REDIS_URL` ; Beat = DatabaseScheduler (django_celery_beat). Commandes financières : `daily_reconciliation`, `process_payout_retries`, `reconcile_pending_transactions`, `run_financial_ops`.

## 2. Flutter (frontend/)
| App | Chemin | Fichiers .dart | Rôle |
|---|---|---|---|
| Manager/Seller | frontend/app | 86 | Vendeur/grossiste |
| Client | frontend/Clients | 55 | Acheteur |
| Driver | frontend/Driver App/app | 37 | Livreur |
| Admin | frontend/admin/project | 32 | Console admin |

Structure commune : `core/` (réseau Dio, auth, config), `features/` (écrans par domaine), Firebase configuré (Android+Web). Site vitrine React/Vite : `MarketCM_vitrineSite/`.

## 3. AWS (vérifié par AWS CLI le 2026-06-12)
| Ressource | Détail |
|---|---|
| EC2 | `i-09e104c1cd49c757e` t3.large running, IP 16.170.68.148, profile `accessRoles3`, SG `launch-wizard-1` (80/443 ouverts monde) + `ec2-rds-1` |
| RDS | `marchecm-postgres` db.t3.medium, PostgreSQL 18.3, **privé**, **chiffré**, **MultiAZ**, backups 7 j |
| S3 | bucket unique `market-cm` |
| CloudFront | `E1GA5ICIZQJOLK` → origin S3 market-cm, domaine df7t18zqeme69.cloudfront.net (pas d'alias, cert par défaut) |
| ElastiCache | **aucun** — Redis hébergé hors AWS (Render Key Value, IP-allowlist) |
| SSM | 33 paramètres `/marche-cm/prod/*` (DB, JWT, NotchPay, SMTP, chiffrement, CORS) |
| CloudWatch | 6 alarmes (EC2 CPU/status, RDS CPU/mem/storage/connexions) — toutes `OK` |
| IAM | 1 user `central-market`, 1 rôle projet `marche-cm-github-deploy` (OIDC CI/CD), instance profile `accessRoles3` |
| SG | 6 groupes — `rds-ec2-1` restreint 5432 au SG EC2 ✅ ; `SecureGroup-Mcm` et `group-secure-marketcm` **non attachés** (orphelins) |

## 4. Production
- Backend : https://cm.digital-get.com — vérifié HTTP 200, `{"status":"ok","service":"marche-cm-backend"}`
- Stack EC2 : nginx → Gunicorn (HTTP) + Daphne (WS), Celery worker+beat, déploiement GitHub Actions OIDC + SSM (sans SSH)
