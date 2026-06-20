# SYSTEM_MAP.md — Phase 1 : Inventaire réel (Zero-Trust)

> Méthode : découverte par exécution/scan réel du dépôt (`grep`, `glob`, `manage.py check`),
> pas par supposition. Chaque chiffre est traçable à la commande qui l'a produit.
> Date : 2026-06-18 · Branche : `aws-infra` · HEAD : `fbbd94e`

## 0. Preuve de démarrage
- `python manage.py check` → **`System check identified no issues (0 silenced)`** ✅
- DB locale par défaut = **sqlite3** (`DB_ENGINE` défaut `sqlite`, `config/settings.py:296`) → tests exécutables sans RDS.

## 1. Apps Django (16) — Modular Monolith DDD
catalog, audit, accounts, analytics, compliance, disputes, chat, escrow, fraud,
innovation, ledger, wallets, support, notifications, logistics, orders.

## 2. Modèles (123 classes `models.Model`)
| App | #Modèles | App | #Modèles |
|---|---|---|---|
| wallets | 17 | logistics | 16 |
| innovation | 11 | accounts | 10 |
| catalog | 9 | orders | 9 |
| disputes | 8 | compliance | 7 |
| ledger | 7 | escrow | 6 |
| fraud | 6 | chat | 5 |
| analytics | 4 | support | 4 |
| audit | 2 | notifications | 2 |

Total : **123** (`grep ^class …Model **/models.py`).

## 3. Surface API HTTP (`config/urls.py`)
- **33 ViewSets REST** enregistrés sur `DefaultRouter` (users, products, orders, wallets,
  escrow/holds, disputes, ledger/accounts, ledger/transactions, compliance/kyc, fraud/*, chat/*, …).
- **~40 routes explicites** dont l'auth (register / register-seller / register-driver /
  login / login/verify / refresh / logout / me / profile / password-change /
  password/reset/request|confirm / kyc/submit / wallet-pin / sensitive-action /
  sessions / google / verify-email / fcm-token), admin (dashboard, audit/export),
  innovation (escrow-split, rfq-compare, shipment-timeline, dispute escalate, …),
  health, ui-config.
- Auth gérée par **lockdown switch** : si `settings.AUTH_LOCKDOWN`, les endpoints d'inscription/login
  renvoient `AuthDisabledView`.
- OpenAPI/Swagger : montés **seulement si** `settings.ENABLE_API_DOCS` (404 en prod) + schéma auth-gated.
- `/metrics/` Prometheus : permission `IsGeneralAdmin` (RBAC, pas `is_staff`).

## 4. WebSocket (Channels)
- Consumers : `chat/consumers.py`, `notifications/consumers.py`, `realtime/consumers.py`.
- Routing : `chat/routing.py`, `notifications/routing.py`, `realtime/routing.py`.

## 5. Celery
- **11 tasks** dans 8 modules : accounts(1), audit(1), escrow(1), wallets(3),
  ledger(1), disputes(1), notifications(2), core/events(1).
- Broker/result : `REDIS_URL` (`settings_celery.py`).
- Beat : **`DatabaseScheduler`** (`django_celery_beat`) → planning stocké en DB (à énumérer en prod, Phase 2).

## 6. Signaux Django
- `wallets/signals.py` : 4 récepteurs (`@receiver`/`post_save`…). Pas d'autres `signals.py`.

## 7. Ressources AWS (Terraform `infra/terraform/*.tf`)
| Type | Détail |
|---|---|
| Réseau | VPC, **4 `aws_subnet`**, **5 `aws_security_group`**, `aws_eip` (NAT/instance) |
| Compute | **1 `aws_instance`** (EC2), IAM role + instance profile |
| Data | **1 `aws_db_instance`** (RDS), `aws_db_subnet_group` |
| CDN | `aws_cloudfront_distribution` + `aws_cloudfront_origin_access_control` (OAC) |
| Secrets | `aws_kms_key` + alias, **~18 `aws_ssm_parameter`** |
| Observabilité | `aws_sns_topic` + subscription, **6 `aws_cloudwatch_metric_alarm`** |
| CI/CD | `aws_iam_openid_connect_provider` (OIDC) + roles/policies |
| Coûts | `aws_budgets_budget` |

> Note : S3 bucket non déclaré dans `*.tf` scannés → soit importé hors-Terraform, soit via `imports.tf`. À confirmer Phase 2 (read-only).

## 8. Statut Phase 1
**PASS** — inventaire produit par scan réel ; aucune affirmation non sourcée.
