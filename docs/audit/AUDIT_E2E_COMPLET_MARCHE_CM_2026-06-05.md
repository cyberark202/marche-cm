# AUDIT E2E COMPLET MARCHÉ CM

Date : 2026-06-05  
Backend cible demandé : `https://cm.digital-get.com`  
Backend réellement câblé par défaut dans les apps Flutter : `https://marche-cm.onrender.com`  
Périmètre audité : backend Django, app Flutter principale `frontend/app`, app clients `frontend/Clients`, app livreur `frontend/Driver App/app`, console admin `frontend/admin/project`, PostgreSQL/RDS, Redis/Channels/Celery, S3/R2/AWS, NotchPay, tests et rapports QA existants.

Ce rapport est fondé sur :

- scan statique du dépôt avec `rg`;
- introspection Django via `backend/dump_urls.py` et `compare.py`;
- lecture des rapports existants `RAPPORT_QA_E2E.md`, `resultats/QA_E2E_V2_REPORT.md`, `resultats/LOAD_TEST_REPORT.md`, `qa_e2e/SCREEN_BACKEND_ALIGNMENT.md`;
- lecture des configurations Django, ASGI, Terraform, Docker Compose et Flutter;
- exécution de `python manage.py check` avec variables locales d'audit.

Limites vérifiées :

- le script `qa_e2e/check_screen_backend_alignment.py` échoue dans l'environnement local car `JWT_ALGORITHM=RS256` est chargé sans paire `JWT_SIGNING_KEY` / `JWT_VERIFYING_KEY` valide. La comparaison `compare.py` a tout de même été exécutée avec variables d'audit et produit les écarts API actuels.
- aucun accès read-only direct AWS live n'a été relancé depuis cet audit; l'analyse infra s'appuie sur `infra/terraform/INVENTORY.md`, `generated.tf`, `observability.tf` et les documents de déploiement datés du 2026-06-04.
- le domaine demandé `cm.digital-get.com` n'est pas celui hardcodé par défaut dans les apps; ce point est un risque de production à part entière.

---

## PHASE 1 - INVENTAIRE

### 1.1 Backend Django

Racine : `backend/`  
Frameworks : Django 5.1 / DRF / SimpleJWT / Channels / Celery / django-celery-beat / django-celery-results / drf-spectacular / Redis channel layer / PostgreSQL ou SQLite local.

Applications Django détectées :

| App | Responsabilité | Modèles majeurs | API |
|---|---|---|---|
| `apps.accounts` | utilisateurs, rôles, auth, MFA, sessions, KYC legacy, FCM, admin dashboard | `User`, `AuditLog`, `ComplianceDocument`, `SensitiveActionChallenge`, `UserMFAConfig`, `TrustedDevice`, `FCMToken` | auth, users, compliance-documents, admin dashboard |
| `apps.catalog` | catalogue produits, catégories, favoris, vidéos, recommandations | `ProductCategory`, `Product`, `ProductStatsSnapshot`, `BuyerPreferenceProfile`, `BuyerProductInteraction`, `ProductFavorite`, `VideoLike`, `VideoComment`, `SavedProductFilter` | products, favorites, filters, video likes/comments |
| `apps.orders` | commandes, escrow commande, preuves logistiques, avis | `Order`, `OrderEscrow`, `LogisticsVerification`, `OrderReview` | orders, sales-summary, confirm_delivery, review |
| `apps.wallets` | wallet, transactions, webhooks NotchPay/PayDunya, ledger wallet, reconciliation | `Wallet`, `WalletTransaction`, `WalletOtpChallenge`, `WalletWebhookEvent`, `WalletLedgerEntry`, `PayoutRetryJob`, `DailyReconciliationReport`, `FraudEvent`, `IdempotencyRecord`, `WalletTransactionStateLog` | wallets, topup, withdraw, reconcile, webhooks, transactions |
| `apps.chat` | salons, messages, accusés | `ChatRoom`, `Message`, `MessageReceipt` | chat/rooms, chat/messages |
| `apps.analytics` | campagnes groupées, RFQ, offres RFQ | `GroupCampaign`, `RequestForQuotation`, `RFQOffer` | campaigns, rfqs, rfq-offers |
| `apps.logistics` | profils transport, expéditions, devis, litiges logistiques, preuves, custody chain | `TransportProfile`, `Shipment`, `TransportQuote`, `ShipmentEvent`, `DeliveryProof`, `CustodyEvent`, `ShipmentDispute`, `DisputeEvidence`, `TransitAgentRating` | shipments, transport-profiles, transport-quotes, shipment-disputes |
| `apps.notifications` | notifications REST et realtime legacy | `Notification`, `PresenceSession` | notifications, `/ws/events/` |
| `apps.innovation` | alertes prix, counter-offers, approval wallet, loyalty, partner API, webhooks partenaires | `PriceAlert`, `RFQCounterOffer`, `WalletApprovalRequest`, `LoyaltyAccount`, `LoyaltyTransaction`, `PartnerApiKey`, `WebhookSubscription` | innovation, price-alerts, wallet-approval-requests, loyalty, partner keys |
| `apps.support` | tickets support | `SupportTicket`, `SupportTicketMessage` | support/tickets |
| `apps.escrow` | escrow générique, transitions et releases | `EscrowHold`, `EscrowRelease`, `EscrowTransition` | escrow/holds |
| `apps.disputes` | litiges génériques et preuves | `DisputeCase`, `DisputeEvent`, `DisputeEvidence`, `DisputeDecision` | disputes |
| `apps.ledger` | comptabilité double entrée | `LedgerAccount`, `LedgerTransaction`, `LedgerEntry` | ledger/accounts, ledger/transactions |
| `apps.audit` | événements audit platform | `AuditEvent` | audit/events |
| `apps.fraud` | scoring fraude, risk profile, blacklist | `FraudAssessment`, `UserRiskProfile`, `BlacklistEntry` | fraud/assessments, fraud/risk-profiles |
| `apps.compliance` | KYC nouvelle génération, documents, AML, sanctions | `KYCApplication`, `KYCDocument`, `AMLScreening`, `SanctionsList` | compliance/kyc |
| `apps.realtime` | WebSocket central | consumers notifications/chat/tracking/dashboard/fallback | `/ws/notifications/`, `/ws/chat/{id}/`, `/ws/tracking/{id}/`, `/ws/dashboard/` |
| `core.events` | outbox event bus | `OutboxEvent` | tâches async |

### 1.2 URL routing backend

Routes explicites dans `backend/config/urls.py` :

| Domaine | Routes |
|---|---|
| Santé/docs | `GET /api/health/`, `/api/schema/`, `/api/schema/swagger/`, `/api/schema/redoc/`, `/metrics/` |
| Auth | `/api/auth/register/`, `/api/auth/register/seller/`, `/api/auth/register/driver/`, `/api/auth/login/`, `/api/auth/login/verify/`, `/api/auth/refresh/`, `/api/auth/logout/`, `/api/auth/me/`, `/api/auth/profile/`, `/api/auth/location/resolve/`, `/api/auth/wallet-pin/`, `/api/auth/sensitive-action/request/`, `/api/auth/sessions/`, `/api/auth/password-change/`, `/api/auth/kyc/submit/`, `/api/auth/fcm-token/`, `/api/auth/verify-email/`, `/api/auth/google/` |
| Admin | `/api/admin/dashboard/`, `/api/admin/audit/export/`, `/api/users/`, `/api/users/online/`, `/api/users/create_managed_user/`, `/api/users/{id}/suspend/`, `/api/users/{id}/unsuspend/`, `/api/users/{id}/verification-status/` |
| Produits | `/api/products/`, `/api/products/{id}/`, `/api/products/mine/`, `/api/products/contact-seller/`, `/api/products/track-view/`, `/api/products/recommended/`, `/api/products/image-search/`, `/api/products/{id}/reviews/`, `/api/product-favorites/`, `/api/product-favorites/toggle/`, `/api/product-filters/`, `/api/video-likes/toggle/`, `/api/video-comments/` |
| Commandes | `/api/orders/`, `/api/orders/{id}/`, `/api/orders/sales-summary/`, `/api/orders/{id}/confirm_delivery/`, `/api/orders/{id}/review/` |
| Wallet | `/api/wallets/`, `/api/wallets/topup/`, `/api/wallets/withdraw/`, `/api/wallets/reconcile/`, `/api/wallets/request_otp/`, `/api/wallets/transactions/`, `/api/wallets/transactions/{external_id}/status/`, webhooks checkout/disburse NotchPay et PayDunya |
| Chat | `/api/chat/rooms/`, `/api/chat/messages/`, `/api/chat/messages/{id}/mark_delivered/`, `/api/chat/messages/{id}/mark_read/` |
| Logistique | `/api/transport-profiles/`, `/api/shipments/`, `/api/shipments/{id}/post_quote/`, `/api/shipments/{id}/accept_quote/`, `/api/shipments/{id}/update_status/`, `/api/shipments/{id}/submit_proof/`, `/api/shipments/{id}/validate_delivery/`, `/api/shipments/{id}/open_dispute/`, `/api/shipments/{id}/log-custody/`, `/api/shipments/{id}/supplier/confirm/`, `/api/shipments/{id}/supplier/proof/`, `/api/shipments/{id}/supplier/admin-validate/`, `/api/shipments/{id}/rate_transit_agent/` |
| Litiges logistiques | `/api/shipment-disputes/`, `/api/shipment-disputes/{id}/`, `/api/shipment-disputes/{id}/add-evidence/`, `/api/shipment-disputes/{id}/appeal/`, `/api/shipment-disputes/{id}/resolve-appeal/`, `/api/shipment-disputes/{id}/request-inspection/`, `/api/shipment-disputes/{id}/inspection-report/`, `/api/shipment-disputes/{id}/guarantee-fund/`, `/api/shipment-disputes/{id}/custody-chain/` |
| RFQ/B2B | `/api/campaigns/`, `/api/rfqs/`, `/api/rfq-offers/`, `/api/rfq-counter-offers/`, `/api/rfq-counter-offers/{id}/decide/`, `/api/innovation/rfq-compare/` |
| Innovation | `/api/loyalty/account/`, `/api/innovation/escrow-split/`, `/api/innovation/shipment-timeline/`, `/api/innovation/disputes/{id}/escalate/`, `/api/innovation/onboarding/checklist/`, `/api/innovation/seller-dashboard/`, `/api/innovation/recommendations/reasons/`, `/api/innovation/notifications/smart-run/`, `/api/price-alerts/`, `/api/price-alerts/evaluate/`, `/api/wallet-approval-requests/`, `/api/partner-api-keys/`, `/api/webhook-subscriptions/` |
| Support/audit/compliance/fraud/ledger | `/api/support/tickets/`, `/api/audit/events/`, `/api/compliance/kyc/`, `/api/fraud/assessments/`, `/api/fraud/risk-profiles/`, `/api/ledger/accounts/`, `/api/ledger/transactions/` |

### 1.3 WebSockets

Configuration ASGI :

- `AllowedHostsOriginValidator(AuthMiddlewareStack(URLRouter(...)))`
- Auth JWT custom dans `config/websocket_auth.py`
- token recommandé via `Sec-WebSocket-Protocol: bearer, <jwt>`
- query string `?token=` bloquée en production sauf `WS_ALLOW_TOKEN_QUERY_STRING=True`
- fallback `/ws/*` inconnu avec fermeture `4404`

Routes actives :

| Route | Consumer | Auth | Usage |
|---|---|---|---|
| `/ws/notifications/` | `NotificationConsumer` | JWT/session | notifications utilisateur par groupe `notification_{id}` |
| `/ws/chat/{room_id}/` | `ChatConsumer` | JWT + participant room | chat, typing, read receipts |
| `/ws/tracking/{shipment_id}/` | `TrackingConsumer` | JWT + participant shipment | tracking GPS livreur |
| `/ws/dashboard/` | `DashboardConsumer` | JWT + `GENERAL_ADMIN` | dashboard admin |
| `/ws/events/` | `EventsConsumer` | route legacy notifications | événement partagé front |
| `/ws/*` | `FallbackWebSocketConsumer` | none | rejet propre `4404` |

### 1.4 Celery, Redis, outbox

Fichiers :

- `backend/celery_app.py`
- `backend/config/settings_celery.py`
- `core/events/tasks.py`
- `apps/notifications/tasks.py`
- `apps/ledger/tasks.py`
- management commands wallet/reconciliation.

Configuration :

- `CELERY_BROKER_URL` par défaut dérivé de `REDIS_URL` DB 1.
- `CELERY_RESULT_BACKEND` par défaut dérivé de `REDIS_URL` DB 2.
- Channels Redis DB configurable via `REDIS_URL`.
- fallback `InMemoryChannelLayer` si `REDIS_URL` absent.

Risque : Redis est à la fois channel layer, cache et broker Celery selon l'environnement. À 100 000 utilisateurs, il faut séparer au minimum channel layer, cache applicatif, locks et broker, ou dimensionner un Redis cluster/ElastiCache avec eviction policy maîtrisée.

### 1.5 Frontend principal `frontend/app`

Rôle : application multi-rôles acheteur/fournisseur/grossiste/transitaire, sans admin dédié.

Composants détectés :

| Zone | Fichiers |
|---|---|
| API core | `lib/core/api_service.dart`, `lib/core/security/secure_dio_client.dart`, `lib/core/auth_token_manager.dart`, `lib/core/token_repository.dart` |
| Config | `lib/core/app_config.dart` |
| Realtime | `lib/core/websocket_service.dart`, `lib/core/realtime_events_service.dart`, `lib/core/push_notification_service.dart` |
| Auth | `features/auth/auth_api_service.dart`, `session_store.dart`, `sensitive_action_service.dart`, `seller_register_page.dart`, `auth_page.dart` |
| Acheteur | `buyer_home_page.dart`, `buyer_catalog_page.dart`, `buyer_kyc_page.dart`, `buyer_profile_page.dart`, `notifications_page.dart` |
| Vendeur | `supplier_dashboard_page.dart`, `supplier_products_page.dart`, `supplier_product_edit_page.dart`, `supplier_orders_received_page.dart`, `supplier_order_detail_page.dart`, `supplier_stats_page.dart`, `supplier_revenue_page.dart` |
| Grossiste/B2B | `wholesaler_dashboard_page.dart`, `business/rfqs_page.dart`, `rfq_offers_page.dart`, `campaigns_page.dart` |
| Commandes | `orders_page.dart`, `sales_summary_page.dart` |
| Wallet | `wallet_page.dart`, `wallet_send_page.dart`, `wallet_withdraw_page.dart`, `notchpay_pending_sheet.dart` |
| Chat/support | `chat_hub_page.dart`, `chat_page.dart`, `support_tickets_page.dart` |
| Profil/conformité | `profile_hub_page.dart`, `security_center_page.dart`, `compliance_documents_page.dart` |

Config défaut :

```dart
String.fromEnvironment("API_BASE_URL", defaultValue: "https://marche-cm.onrender.com")
```

### 1.6 Frontend clients `frontend/Clients`

Rôle : application acheteur/client dédiée.

Composants :

| Zone | Fichiers |
|---|---|
| API/security | `lib/core/api_service.dart`, `auth_token_manager.dart`, `websocket_service.dart`, `realtime_events_service.dart` |
| Auth/profil | `features/auth/auth_api_service.dart`, `session_store.dart`, `profile_hub_page.dart`, `security_center_page.dart`, `kyc_verification_page.dart`, `compliance_documents_page.dart` |
| Shopping | `buyer/cart_page.dart`, `shell/shop_tab.dart`, `buyer/buyer_dashboard_page.dart`, `buyer/notifications_page.dart` |
| Commandes/logistique | `orders/orders_page.dart`, `orders/order_tracking_page.dart`, `logistics/shipment_disputes_page.dart` |
| Wallet | `wallet_page.dart`, `wallet_send_page.dart`, `wallet_withdraw_page.dart`, `notchpay_pending_sheet.dart` |
| Innovation/B2B | `innovation_hub_page.dart`, `business/rfqs_page.dart`, `buyer/rfq_compare_page.dart` |
| Chat | `chat_hub_page.dart`, `chat_page.dart` |

Config défaut : `https://marche-cm.onrender.com`.

### 1.7 Driver App `frontend/Driver App/app`

Rôle : livreur/transitaire.

Composants :

| Zone | Fichiers |
|---|---|
| Config/API | `lib/core/config/app_config.dart`, `lib/core/network/driver_dio_client.dart` |
| Auth | `features/auth/infrastructure/driver_auth_api.dart`, `auth_notifier.dart`, `login_page.dart`, `register_page.dart`, `onboarding_page.dart` |
| Dashboard/missions | `dashboard_page.dart`, `missions_list_page.dart`, `mission_detail_page.dart`, `my_runs_page.dart`, `quote_send_page.dart` |
| Delivery | `active_delivery_page.dart`, `pickup_confirmation_page.dart`, `otp_validation_page.dart`, `delivery_proof_page.dart` |
| Profil | `profile_page.dart`, `vehicle_page.dart`, `documents_page.dart`, `reviews_page.dart` |

Config défaut :

- debug API : `http://10.0.2.2:8000`
- release API : `https://marche-cm.onrender.com`
- release WS : `wss://marche-cm.onrender.com/ws/events/`

### 1.8 Admin Flutter `frontend/admin/project`

Rôle : console admin dédiée `GENERAL_ADMIN`.

Composants :

| Zone | Fichiers |
|---|---|
| API/security | `core/api_service.dart`, `core/security/secure_dio_client.dart`, `core/token_repository.dart`, `core/roles.dart` |
| Auth | `features/auth/admin_login_page.dart`, `auth_api_service.dart`, `session_store.dart` |
| Dashboard | `dashboard/admin_dashboard_page.dart` |
| Utilisateurs | `users/users_page.dart`, `users/user_detail_page.dart` |
| Compliance | `compliance/kyc_queue_page.dart`, `document_review_page.dart` |
| Litiges | `disputes/disputes_page.dart`, `arbitration_page.dart`, `dispute_multiview_page.dart` |
| Wallet | `wallet/reconciliation_page.dart` |
| Audit/config/profil | `audit_page.dart`, `configuration_page.dart`, `admin_profile_page.dart` |

Config défaut : `https://marche-cm.onrender.com`.

### 1.9 Infrastructure AWS

Inventaire `infra/terraform/INVENTORY.md` :

| Ressource | État constaté |
|---|---|
| Région | `eu-north-1` |
| VPC | VPC par défaut `vpc-06c9268a6c1463479`, CIDR `172.31.0.0/16` |
| EC2 | 2 instances running (`market-CM-API` t3.large, `marchecm-api` t3.medium) + 1 stopped |
| EIP | 16.170.68.148 et 13.51.105.80 |
| RDS | `marchecm-postgres`, PostgreSQL 18.3, `db.r5.large`, 200 Go gp3, chiffrement KMS, backups 7 j, Multi-AZ non, deletion protection activée dans Terraform actuel |
| S3 | bucket `market-cm` |
| IAM | rôle EC2 `accessRoles3` avec `AmazonS3ExpressFullAccess` et `AmazonSSMManagedInstanceCore` |
| Observabilité | Terraform crée SNS + alarmes RDS/EC2, mais mémoire/disque EC2 nécessitent agent CloudWatch |

---

## PHASE 2 - CONTRAT API

### 2.1 Résultat de comparaison automatique actuel

Commande exécutée : `python compare.py`.

Appels frontend sans route backend détectée :

| Endpoint | Backend | Frontend | Statut | Impact |
|---|---|---|---|---|
| `/api/driver/reviews/` | aucune route | Driver App `profile/reviews_page.dart` | KO | écran avis livreur non fonctionnel |
| `/api/seller/stats/` | aucune route | `frontend/app/features/supplier/supplier_stats_page.dart` | KO | dashboard vendeur statistiques cassé |
| `/api/shipments/{id}/resend_otp/` | aucune action DRF | Driver App `delivery_proof_page.dart` | KO | impossible de renvoyer OTP livraison depuis app livreur |

Routes anciennement déclarées manquantes mais maintenant corrigées :

| Endpoint | État actuel |
|---|---|
| `/api/orders/{id}/confirm/` | plus détecté comme manquant par `compare.py`; l'ancien rapport était périmé ou la route front a été modifiée |
| `/api/orders/{id}/request-quote/` | plus détecté comme manquant par `compare.py` |
| `/api/shipments/{id}/quote/` | plus détecté comme manquant; backend expose `post_quote` et front actuel semble utiliser route alignée ailleurs |

### 2.2 Endpoints backend non consommés par Flutter

Ces routes ne sont pas forcément des bugs; certaines sont serveur-à-serveur, admin, docs, ou futures.

| Domaine | Routes non référencées côté Flutter | Lecture |
|---|---|---|
| Docs | `/api/schema/*` | normal |
| Auth legacy | `/api/auth/login/verify/`, `/api/auth/verify-email/` | flux OTP/email désactivé par conception; conserver ou supprimer pour réduire surface |
| Webhooks wallet | NotchPay/PayDunya checkout/disburse | normal serveur-à-serveur |
| Ledger | `/api/ledger/accounts/*`, `/api/ledger/transactions/*` | admin/ops non câblé ou réservé backend |
| Fraud | `/api/fraud/*` | admin/ops non exposé |
| Disputes génériques | `/api/disputes/*` | doublon fonctionnel avec `shipment-disputes`; risque de fragmentation produit |
| Escrow générique | `/api/escrow/holds/*` | partiellement admin; workflows front limités |
| Compliance nouvelle génération | `/api/compliance/kyc/*` | console admin utilise surtout `compliance-documents`; double système KYC |
| Actions users | `suspend`, `unsuspend`, `verification-status` | la V2 E2E dit OK côté admin; scan littéral peut manquer appels construits dynamiquement |
| Chat messages mark_read/mark_delivered | front utilise interpolation; `compare.py` peut ne pas normaliser parfaitement |

### 2.3 Table de contrat par famille

| Endpoint | Méthode | Payload attendu | Consommateur Flutter | Statut | Impact |
|---|---:|---|---|---|---|
| `/api/auth/register/` | POST | `username`, `email`, `password`, `name`, `phone_number`, pays/ville optionnels | app/Clients | OK | rôle forcé BUYER, protection privesc |
| `/api/auth/register/seller/` | POST | identité + rôle fournisseur/grossiste contraint | app | OK | inscription vendeur/grossiste |
| `/api/auth/register/driver/` | POST | identité livreur, rôle forcé TRANSIT_AGENT | Driver App | OK | onboarding livreur |
| `/api/auth/login/` | POST | `email`, `password`, device headers | toutes | OK avec risque perf sous concurrence | 5 erreurs 500 sous charge historique à investiguer |
| `/api/auth/refresh/` | POST | `refresh` | interceptors Dio | OK | rotation refresh |
| `/api/auth/logout/` | POST | `refresh` | toutes | OK | blacklist refresh |
| `/api/auth/me/` | GET | none | toutes | OK | session restore |
| `/api/auth/google/` | POST | `id_token` | app/Clients | OK statique | nécessite `GOOGLE_CLIENT_ID`/server id correct |
| `/api/auth/wallet-pin/` | POST | `pin` | app/Clients | OK | PIN wallet, longueur configurable |
| `/api/auth/sensitive-action/request/` | POST | `action_key` | app/admin | OK | step-up 2FA wallet/admin |
| `/api/auth/kyc/submit/` | POST multipart | `doc_type`, `file`, `signature`, `consent_accepted` | app/Clients | OK selon V2 | KYC acheteur |
| `/api/compliance-documents/` | GET/POST | `doc_type`, `file`, signature/consent | app/Clients/Driver/admin | OK avec double système | KYC legacy; attention périmètre rôles |
| `/api/compliance-documents/{id}/review/` | POST | `status`, `review_note` | admin | OK | validation/rejet KYC |
| `/api/users/` | GET | filters | admin/app role page | OK | liste admin ou self selon rôle |
| `/api/users/{id}/suspend/` | POST | `reason` | admin | OK selon V2 | suspension + login bloqué |
| `/api/users/{id}/unsuspend/` | POST | none | admin | OK selon V2 | réactivation |
| `/api/products/` | GET/POST | produit, catégories, prix, image/video | app/Clients | OK selon V2 après fix C-1/C-2 | catalogue |
| `/api/products/{id}/` | GET/PATCH/DELETE | produit | app/Clients | OK | IDOR contrôlé |
| `/api/products/mine/` | GET | none | vendeurs/grossistes | OK | inventaire vendeur |
| `/api/products/recommended/` | GET | none | acheteur | OK | home acheteur |
| `/api/products/track-view/` | POST | product id | non référencé direct actuel | non critique | analytics |
| `/api/product-favorites/toggle/` | POST | `product_id` | Clients | OK | favoris |
| `/api/product-filters/` | CRUD | filtres | Clients | OK | filtres sauvegardés |
| `/api/orders/` | GET/POST | `product`, `quantity`, options logistiques | app/Clients | OK | panier/commande |
| `/api/orders/sales-summary/` | GET | none | app | OK | vendeur revenue |
| `/api/orders/{id}/confirm_delivery/` | POST | none | app/Clients | OK | libération escrow local/logistique |
| `/api/orders/{id}/review/` | GET/POST | note/commentaire | app/Clients | OK | avis |
| `/api/wallets/` | GET | none | toutes | OK | auto-provision partiel |
| `/api/wallets/topup/` | POST | `amount`, provider, phone/source | app/Clients | OK avec risques config NotchPay | recharge |
| `/api/wallets/withdraw/` | POST | `amount`, provider, destination, PIN/2FA | app/Clients | OK | retrait |
| `/api/wallets/reconcile/` | POST | `transaction_id`, `status`, `challenge_token`, `verification_code` | admin | OK | reconciliation manuelle admin |
| `/api/wallets/transactions/` | GET | `status`, `kind`, cursor | app/Clients/Driver | OK | historique |
| `/api/wallets/transactions/{id}/status/` | GET | external id | app/Clients pending sheet | OK | polling paiement |
| `/api/shipments/` | GET/POST | shipment/order fields | toutes | OK | missions/livraison |
| `/api/shipments/{id}/post_quote/` | POST | `fee`, `eta_days`, note | Driver App | OK backend; vérifier front `quote_send_page` | devis transitaire |
| `/api/shipments/{id}/accept_quote/` | POST | `quote_id` | app/Clients | OK | choix transport |
| `/api/shipments/{id}/update_status/` | POST | `status`, preuve optionnelle | Driver App | OK selon V2 | cycle livraison |
| `/api/shipments/{id}/submit_proof/` | POST multipart | fichiers preuve | Driver App | OK | preuve livraison |
| `/api/shipments/{id}/validate_delivery/` | POST | OTP/preuve | Driver/App/Clients | OK | livraison |
| `/api/shipments/{id}/resend_otp/` | POST | aucun | Driver App | KO | action frontend orpheline |
| `/api/shipments/{id}/open_dispute/` | POST | `reason`, `details` | Clients | OK | litige livraison |
| `/api/shipment-disputes/` | CRUD | litige | app/Clients/admin | OK | litiges |
| `/api/shipment-disputes/{id}/add-evidence/` | POST multipart | preuve | app/Clients | OK | preuves |
| `/api/transport-profiles/` | CRUD | profil transport | Clients/Driver | OK | transporteurs |
| `/api/transport-quotes/` | GET | filters | app/Clients/Driver | OK | devis |
| `/api/driver/reviews/` | GET | none | Driver App | KO | écran avis |
| `/api/seller/stats/` | GET | `range` | app vendeur | KO | stats vendeur |
| `/api/notifications/` | GET | none | app/Clients | OK | notifications |
| `/api/notifications/{id}/mark_read/` | POST | none | app/Clients | OK | lu |
| `/api/notifications/mark_all_read/` | POST | none | app/Clients | OK | tout lu |
| `/api/chat/rooms/` | CRUD | participants | app/Clients | OK avec N+1 | chat |
| `/api/chat/messages/` | CRUD | room, content, type/file | app/Clients | OK | messages |
| `/api/support/tickets/` | CRUD | subject, description, priority | app | OK | support |
| `/api/support/tickets/{id}/add_message/` | POST | body/internal | app | OK | fil support |
| `/api/support/tickets/{id}/close/` | POST | none | app | OK | clôture |
| `/api/campaigns/` | CRUD | product, quantities | app | OK | group buying |
| `/api/rfqs/` | CRUD | RFQ fields | app/Clients | OK | demandes devis |
| `/api/rfq-offers/` | CRUD | rfq, price, qty | app/Clients | OK | offres |
| `/api/innovation/*` | GET/POST | selon service | Clients innovation hub | OK statique | fonctionnalités avancées |
| `/api/admin/dashboard/` | GET | none | admin | OK | dashboard |
| `/api/admin/audit/export/` | GET | filters | admin | OK | export CSV |
| `/metrics/` | GET | none | non-app | OK protégé `GENERAL_ADMIN` | monitoring |

---

## PHASE 3 - MODÈLES BACKEND VS FLUTTER

### 3.1 Rôles utilisateur

Backend `UserRole` :

- `BUYER`
- `SUPPLIER`
- `WHOLESALER`
- `TRANSIT_AGENT`
- `GENERAL_ADMIN`

Frontends :

- `app` et `Clients` connaissent les rôles partagés.
- Driver App force le rôle transitaire via `/api/auth/register/driver/`.
- Admin console refuse les non-`GENERAL_ADMIN`.

Statut : aligné.

Risque : le rôle admin reste présent dans certains modèles partagés côté app principale pour les `switch`; ce n'est pas un écran admin mais il faut éviter de réintroduire des actions admin dans les apps grand public.

### 3.2 User/Profile

Backend `User` expose via serializer : `id`, `username`, `name`, `email`, `phone_number`, `role`, `avatar_url`, `is_verified`, `is_online`, `last_seen_at`, `kyc_level`, champs localisation.

Risques :

| Champ | Backend | Flutter | Statut | Impact |
|---|---|---|---|---|
| `is_active` / suspension | backend bloque login si suspendu | front doit gérer `401 Compte suspendu` | à tester UI | message d'erreur générique possible |
| `kyc_level` | entier 0/1/2 | souvent lu comme int dynamique | OK | limites wallet appliquées backend |
| `phone_number` | format `+237...` validé | formulaires peuvent saisir local | à surveiller | 400 UX |
| `avatar` | upload validé magic bytes | profile forms multipart | OK | S3 obligatoire en prod |

### 3.3 Product

Champs backend majeurs : `seller`, `category`, `name`, `description`, `image`, `video`, `available_qty`, `min_order_qty`, `max_order_qty`, `unit_price`, `price_for_min_qty`, `price_for_max_qty`, `is_active`, `reference_code`, timestamps.

État actuel selon rapports V2 :

- création vendeur corrigée;
- `is_active` forcé à `True` à la création;
- création grossiste corrigée par dérivation prix.

Risques restants :

| Champ | Risque | Impact |
|---|---|---|
| `category` vs `category_name` | si anciens clients mobiles restent installés, payload legacy peut casser | création produit 400 |
| `is_active` | plus d'état brouillon | vendeur publie immédiatement |
| médias | URLs S3/R2 privées ou endpoint API S3 | images produit invisibles |

### 3.4 Order / Shipment / Escrow

Backend :

- `Order.status`: `PENDING`, `CONFIRMED`, `SHIPPING`, `DELIVERED`, `COMPLETED`, `CANCELLED`, `REFUNDED`, `DISPUTED`, plus états sourcing/international.
- `Order.escrow_status`: `HELD`, `SPLIT_LOCKED`, `RELEASED`, `REFUNDED`, `FROZEN`, `PARTIALLY_RELEASED`.
- `Shipment.status`: `PICKUP_PENDING`, `IN_TRANSIT`, `DELIVERED`, `CANCELLED`, etc.

Statut :

- C-3 historique corrigé par `OrderFinanceService.cancel_order()` atomique.
- Les frontends doivent consommer les états réels; tout écran qui suppose `PENDING -> COMPLETED` direct doit être refusé par backend.

Risque :

| Modèle | Incohérence possible | Impact |
|---|---|---|
| `Order` | front utilise labels libres, backend états stricts | boutons affichés au mauvais moment |
| `Shipment` | OTP resend absent | étape livraison bloquée si OTP non reçu |
| `OrderEscrow` | partiellement libéré / payout pending peu exposé | support client incapable d'expliquer fonds bloqués |

### 3.5 Wallet

Backend :

- `Wallet.available_balance`, `locked_balance`, `pending_balance`, `currency`
- `WalletTransaction.kind`, `status`, `provider`, `amount`, `external_transaction_id`, `failure_reason`, metadata
- ledger wallet et ledger double entrée séparés.

Flutter :

- listes transactions;
- polling `transactions/{external_id}/status/`;
- topup/withdraw;
- PIN wallet.

Statut : globalement aligné.

Risque critique : la configuration NotchPay vide-mais-présente peut casser toutes les recharges même si le code est sain.

### 3.6 Compliance/KYC

Deux systèmes coexistent :

| Système | Route | Modèles | Risque |
|---|---|---|---|
| Legacy | `/api/compliance-documents/`, `/api/auth/kyc/submit/` | `accounts.ComplianceDocument` | utilisé par apps et admin |
| Nouveau | `/api/compliance/kyc/` | `compliance.KYCApplication`, `KYCDocument`, `AMLScreening` | peu consommé côté Flutter |

Impact : duplication métier, risque de divergence de statut KYC si les deux systèmes évoluent séparément.

---

## PHASE 4 - AUTHENTIFICATION

### 4.1 JWT

Constats :

- SimpleJWT configuré avec access token 15 min par défaut et refresh 7 jours.
- Rotation et blacklist activées.
- `JWT_ALGORITHM=HS256` interdit en production sauf override explicite `ALLOW_HS256_IN_PRODUCTION=1`.
- RS256/ES256 exigent `SIGNING_KEY` et `VERIFYING_KEY`.
- `manage.py check` passe avec variables locales d'audit.

Risques :

| ID | Gravité | Problème | Impact |
|---|---|---|---|
| AUTH-001 | Élevé | environnement local/prod peut charger `JWT_ALGORITHM=RS256` sans clés valides | démarrage backend impossible |
| AUTH-002 | Moyen | apps mobiles hardcodent backend `marche-cm.onrender.com` par défaut | login contre mauvais backend |

### 4.2 Refresh

Front :

- `SecureDioClient` et `TokenRepository` font refresh proactif/réactif.
- anti-refresh concurrent via completer.
- tokens stockés secure storage.

Backend :

- endpoint `/api/auth/refresh/`.
- blacklist au logout.

Statut : OK.

### 4.3 MFA / Step-up

Backend :

- `SensitiveActionChallenge`
- `verify_sensitive_action_challenge`
- `SENSITIVE_ACTION_2FA_ENABLED`
- actions sensibles : wallet reconcile, opérations admin, wallet retrait selon flux.

Statut : bon modèle de sécurité.

Risque : l'expérience utilisateur dépend d'un email opérationnel; sans SMTP prod fiable, les actions financières/admin restent bloquées.

### 4.4 Google Login

Backend :

- `GoogleAuthView`
- `GOOGLE_CLIENT_ID`

Front :

- `googleClientId`, `googleServerClientId` injectés par `--dart-define`.

Risque :

- si `GOOGLE_SERVER_CLIENT_ID` n'est pas injecté dans les builds, l'app peut obtenir un token non vérifiable serveur.

### 4.5 Suspension utilisateur

Backend :

- `User.suspend()` et `unsuspend()`
- endpoints `/api/users/{id}/suspend/`, `/unsuspend/`
- rapport V2 : suspension -> login bloqué `401 "Compte suspendu"` -> réactivation OK.

Statut : OK.

### 4.6 Déconnexion

Backend :

- blacklist refresh token.

Front :

- suppression secure storage.

Statut : OK.

---

## PHASE 5 - WORKFLOWS MÉTIER

### 5.1 Acheteur

| Étape | Backend | Frontend | Statut | Risques |
|---|---|---|---|---|
| inscription | `/api/auth/register/` | app/Clients auth | OK | géocodage asynchrone corrigé selon V2 |
| login | `/api/auth/login/` | toutes | OK | 500 sous concurrence à investiguer |
| KYC | `/api/auth/kyc/submit/` | buyer_kyc/kyc_verification | OK | double système KYC |
| catalogue | `/api/products/`, `/recommended/` | home/catalog/shop | OK | médias S3/R2 peuvent ne pas s'afficher |
| panier/commande | `POST /api/orders/` | cart_page/orders | OK | prix doit rester calculé serveur |
| paiement wallet | wallet lock via OrderFinanceService | cart/orders | OK | solde insuffisant et KYC limits backend |
| suivi livraison | `/api/shipments/`, `/ws/tracking/{id}/` | orders/tracking | OK | connexion WS mobile à valider sous changement réseau |
| confirmation livraison | `/api/orders/{id}/confirm_delivery/` | orders_page | OK | libération fonds critique |
| annulation | `cancel_order()` atomique | via shipment/order selon UI | OK selon V2 | vérifier bouton UI n'appelle pas un ancien flux |

### 5.2 Vendeur / Fournisseur

| Étape | Backend | Frontend | Statut | Risques |
|---|---|---|---|---|
| inscription | `/api/auth/register/seller/` | seller_register_page | OK | rôle contraint |
| KYC | compliance documents | compliance pages | OK | admin review dépend console |
| création produit | `/api/products/` | supplier_product_edit_page | OK selon V2 | anciens builds mobiles peuvent envoyer payload legacy |
| stats | `/api/seller/stats/` | supplier_stats_page | KO | route inexistante actuelle |
| commandes reçues | `/api/orders/?role=seller` | supplier_orders_received_page | OK | backend filtre par rôle utilisateur, query `role` peut être ignorée |
| traitement | shipment/order actions | supplier_order_detail_page | partiel | anciennes routes confirm/request-quote à vérifier |
| revenus | wallet transactions/sales-summary | revenue pages | OK | états payout pending à exposer clairement |

### 5.3 Grossiste

| Étape | Statut | Risques |
|---|---|---|
| inscription seller/wholesaler | OK |
| campagnes groupées | OK via `/api/campaigns/` |
| RFQ/offres | OK via `/api/rfqs/`, `/api/rfq-offers/` |
| produit grossiste | OK selon V2 | vérifier que prix dérivés serveur ne régressent pas |

### 5.4 Livreur / Transitaire

| Étape | Backend | Driver App | Statut | Risques |
|---|---|---|---|---|
| inscription | `/api/auth/register/driver/` | register_page | OK | rôle forcé |
| login | `/api/auth/login/` | login_page | OK | mauvais backend par défaut release |
| missions | `/api/shipments/` | missions_list/active_delivery | OK | filtrage status côté front |
| envoyer devis | `/api/shipments/{id}/post_quote/` | quote_send_page | à vérifier | ancien scan avait `/quote/` |
| pickup | `/api/shipments/{id}/update_status/` | pickup_confirmation | OK | multipart/form |
| preuve | `/api/shipments/{id}/submit_proof/` | delivery_proof | OK | stockage S3 obligatoire |
| validation OTP | `/api/shipments/{id}/validate_delivery/` | otp_validation | OK | resend OTP absent |
| avis livreur | aucun endpoint `/api/driver/reviews/` | reviews_page | KO | écran vide/erreur |
| WS | `/ws/events/`, `/ws/tracking/{id}/` | config `/ws/events/` | OK | tracking dédié à brancher si besoin GPS |

### 5.5 Admin

| Étape | Backend | Admin app | Statut | Risques |
|---|---|---|---|---|
| login admin | `/api/auth/login/`, `/me/` | admin_login | OK | rôle check côté front et backend |
| dashboard | `/api/admin/dashboard/` | dashboard | OK | KPIs calculés partiellement |
| validation KYC | `/api/compliance-documents/{id}/review/` | document_review | OK | double système KYC |
| suspension | `/api/users/{id}/suspend/` | users/admin repo | OK selon V2 | scan littéral peut ne pas voir appels dynamiques |
| remboursement/arbitrage | litiges + OrderFinanceService | arbitration | OK | split/release financier doit être testé en charge |
| reconciliation wallet | `/api/wallets/reconcile/` + step-up | reconciliation_page | OK | dépend SMTP/2FA |

---

## PHASE 6 - PAIEMENTS

### 6.1 Chaîne Paiement -> Webhook -> Wallet -> Escrow -> Livraison -> Release

Flux topup :

1. utilisateur appelle `POST /api/wallets/topup/`;
2. backend valide montant, provider, téléphone, limites KYC, fraude;
3. crée `WalletTransaction PENDING`;
4. initialise NotchPay checkout/direct charge;
5. webhook checkout signé confirme;
6. backend vérifie HMAC, timestamp optionnel, token optionnel, montant exact, référence transaction;
7. `_mark_transaction_success` crédite wallet et ledger;
8. réconciliation fallback possible via management command/admin.

Flux commande/escrow :

1. acheteur crée commande;
2. `OrderFinanceService.lock_funds_for_order()` bloque fonds wallet avec idempotency key déterministe;
3. crée `OrderEscrow` local ou split international;
4. livraison confirmée ou arbitrage admin;
5. release/refund via `WalletAccountingService` et payout NotchPay si applicable.

### 6.2 Risques financiers classés

| ID | Niveau | Risque | État | Impact financier |
|---|---|---|---|---|
| PAY-001 | P0 | variables NotchPay vides-mais-présentes (`NOTCHPAY_PUBLIC_KEY=`) cassent toutes les recharges live | constaté V2, à répliquer dashboard prod | aucun encaissement possible |
| PAY-002 | P0 | `NOTCHPAY_CHECKOUT_RETURN_URL` vide redirige navigateur vers webhook GET 405 après paiement | constaté V2 | UX paiement cassée, tickets support |
| PAY-003 | P0 | webhooks NotchPay pointent vers backend non canonique/down | constaté rapports | paiement complet côté provider mais wallet non crédité sans reconciliation |
| PAY-004 | P1 | `WEBHOOK_REQUIRE_TIMESTAMP=False` par défaut | code actuel | HMAC protège, mais replay d'un webhook signé compromis reste possible |
| PAY-005 | P1 | auto-payout live dépend numéros et provider mode | startup validators présents | mauvaise config bloque ou envoie mauvais payout |
| PAY-006 | P1 | payout retry pending peut accumuler des fonds à libérer | modèle retry présent | fonds vendeur/transitaire retardés |
| PAY-007 | P1 | double système ledger wallet + ledger comptable | présent | divergence comptable si une écriture échoue hors transaction |
| PAY-008 | P2 | PayDunya aliases toujours exposés | compat | surface webhook doublée |

### 6.3 Race conditions

Protections présentes :

- `transaction.atomic()`
- `select_for_update()`
- idempotency sur locks commande `order:{id}:lock_funds_v1`
- `WalletWebhookEvent` unique par provider/event_id
- vérification montant webhook exact
- state logs append-only.

Points à renforcer :

- rendre `WEBHOOK_REQUIRE_TIMESTAMP=True` en production après confirmation fournisseur;
- monitorer le nombre de `PENDING` par âge;
- alerter si `WalletTransaction.SUCCESS` sans ledger double entrée;
- tester concurrence `confirm_delivery` x2, webhook x2, cancel vs delivery.

---

## PHASE 7 - WEBSOCKETS

### 7.1 Auth

Points forts :

- JWT validé via SimpleJWT;
- token query string bloqué en prod;
- user inactif refusé;
- origine validée par `AllowedHostsOriginValidator`;
- unauthorized close `4401`.

Risques :

| ID | Gravité | Problème | Impact |
|---|---|---|---|
| WS-001 | Moyen | clients mobiles doivent envoyer subprotocol `bearer,<token>`; tous les wrappers front ne sont pas prouvés | reconnexions silencieusement refusées |
| WS-002 | Moyen | `AuthMiddlewareStack` reste autour du JWT custom | complexité; sessions web possibles mais pas dangereuses si user active |
| WS-003 | Moyen | `/ws/events/` legacy et `/ws/notifications/` coexistent | double modèle de notification |
| WS-004 | Moyen | capacité 100 000 users non testée | Redis/channel layer peut saturer |

### 7.2 Reconnexion/changement réseau

Front `realtime_events_service.dart` prévoit reconnexion et refresh token REST pendant déconnexion. À tester explicitement :

- perte réseau 30 s;
- token expiré pendant WS connecté;
- app background/foreground;
- multi-device même compte;
- suspension admin pendant connexion active.

### 7.3 Multi-device

Backend utilise groupes `notification_{user_id}`, `chat_{room_id}`, `tracking_{shipment_id}`. Plusieurs sockets par utilisateur reçoivent les événements. Risque produit : actions `mark_read` depuis un device doivent synchroniser les autres devices via événement ou polling.

---

## PHASE 8 - PERFORMANCE

### 8.1 Résultats existants

Rapport `resultats/LOAD_TEST_REPORT.md` :

- catalogue : 4 requêtes SQL, pas de N+1;
- `/api/chat/rooms/` : N+1 confirmé (`SELECT accounts_user` x5 pour 4 rooms);
- `/api/orders/` : 6 requêtes pour 3 commandes, à surveiller;
- rate-limiting 429 dès 100 utilisateurs mono-IP;
- 5 erreurs 500 sur `/auth/login` sous palier 50;
- capacité 10k non mesurable depuis générateur unique.

### 8.2 Corrections exactes performance

| ID | Gravité | Fichier | Correction |
|---|---|---|---|
| PERF-001 | Élevé | `apps/chat/views.py` | ajouter `prefetch_related("participants")` sur rooms |
| PERF-002 | Élevé | déploiement | ajouter PgBouncer/RDS Proxy pour pool PostgreSQL |
| PERF-003 | Élevé | `apps/notifications/realtime.py` | `broadcast_event` doit être best-effort et non bloquer la requête |
| PERF-004 | Moyen | infra | CloudWatch agent EC2 pour mémoire/disque |
| PERF-005 | Moyen | throttling | distinguer anti-flood mono-IP et vrais utilisateurs derrière NAT opérateur |

Diff proposé PERF-001 :

```diff
diff --git a/backend/apps/chat/views.py b/backend/apps/chat/views.py
--- a/backend/apps/chat/views.py
+++ b/backend/apps/chat/views.py
@@
 class ChatRoomViewSet(viewsets.ModelViewSet):
@@
     def get_queryset(self):
-        return ChatRoom.objects.filter(participants=self.request.user)
+        return (
+            ChatRoom.objects
+            .filter(participants=self.request.user)
+            .prefetch_related("participants")
+        )
```

Diff proposé PERF-003 :

```diff
diff --git a/backend/apps/notifications/realtime.py b/backend/apps/notifications/realtime.py
--- a/backend/apps/notifications/realtime.py
+++ b/backend/apps/notifications/realtime.py
@@
+import logging
+
+logger = logging.getLogger(__name__)
+
 def broadcast_event(...):
-    async_to_sync(layer.group_send)(group, payload)
+    try:
+        async_to_sync(layer.group_send)(group, payload)
+    except Exception:
+        logger.exception("realtime_broadcast_failed", extra={"group": group})
```

---

## PHASE 9 - SÉCURITÉ OWASP

| Catégorie OWASP | État | Risques restants |
|---|---|---|
| A01 Broken Access Control / IDOR | globalement bon; querysets relationnels et 404 anti-énumération | endpoints peu consommés `disputes`, `ledger`, `fraud` à tester en E2E |
| A02 Crypto failures | JWT RS256 forcé en prod, Fernet PII, HTTPS release | volumes EBS non chiffrés sur EC2 racine selon Terraform; médias KYC URL publiques/signées à clarifier |
| A03 Injection | ORM, validations upload | champs texte stockés bruts; Flutter `Text` OK, mais admin web future doit échapper |
| A04 Insecure Design | escrow atomique corrigé, step-up admin | double KYC, double litiges, PayDunya legacy |
| A05 Security Misconfiguration | settings hardenés | Flutter pointe mauvais backend; SG SSH; IAM S3ExpressFullAccess |
| A06 Vulnerable Components | non audité par SCA dans ce tour | lancer `pip-audit`, `npm audit`/`dart pub outdated` |
| A07 Auth failures | JWT blacklist, suspension, MFA | SMTP/2FA dépendance opérationnelle |
| A08 Software/Data Integrity | migrations, ledger | CI/CD ECR absent, pas de signature image |
| A09 Logging/Monitoring | audit logs, metrics, CloudWatch alarms Terraform | logs applicatifs CloudWatch non complets; alertes paiement à vérifier |
| A10 SSRF | webhook subscriptions doivent valider URL | vérifier blocage IP privées/métadata AWS dans `WebhookSubscriptionViewSet` |

### 9.1 Failles classées

| ID | Gravité | Module | Description |
|---|---|---|---|
| SEC-001 | Critique | Infra AWS | SSH historiquement ouvert à `0.0.0.0/0` sur certains SG; Terraform actuel restreint partiellement mais état réel à confirmer |
| SEC-002 | Élevé | IAM | rôle EC2 `AmazonS3ExpressFullAccess`, trop large pour médias |
| SEC-003 | Élevé | S3/R2 | médias KYC/chat/produits peuvent être non servis ou servis publiquement sans séparation privé/public |
| SEC-004 | Élevé | Front config | builds release pointent backend non demandé par la mission |
| SEC-005 | Moyen | Webhooks | timestamp webhook non obligatoire par défaut |
| SEC-006 | Moyen | SSRF | endpoints partenaires/webhook subscriptions à re-tester contre IP privées |
| SEC-007 | Moyen | Secrets | docs mentionnent `.env`; Secrets Manager/SSM non utilisés partout |
| SEC-008 | Faible | Docs | `docs/.env` existe dans workspace; vérifier qu'il n'est jamais commité/poussé |

---

## PHASE 10 - INFRASTRUCTURE AWS

### 10.1 EC2

Constats :

- 2 instances running aux noms proches : coût et confusion de prod.
- Terraform canonique cible `market-CM-API`.
- root EBS `encrypted=false` dans `generated.tf`.
- IMDSv2 requis (`http_tokens=required`) : bon.
- monitoring détaillé EC2 `monitoring=false`.

Corrections :

```diff
diff --git a/infra/terraform/generated.tf b/infra/terraform/generated.tf
@@
   root_block_device {
     delete_on_termination = true
-    encrypted             = false
+    encrypted             = true
```

Décision requise : arrêter/supprimer l'instance non canonique après validation DNS et sauvegarde.

### 10.2 RDS PostgreSQL

Points forts :

- chiffrement KMS;
- backups 7 j;
- private;
- deletion protection activée dans Terraform;
- enhanced monitoring role.

Risques :

- Multi-AZ désactivé : P1 pour 100 000 utilisateurs;
- Performance Insights désactivé : diagnostic difficile;
- `db.r5.large` coûteux mais sans HA;
- `skip_final_snapshot=true` malgré deletion protection.

Corrections :

```diff
diff --git a/infra/terraform/generated.tf b/infra/terraform/generated.tf
@@
-  multi_az            = false
+  multi_az            = true
@@
-  performance_insights_enabled = false
+  performance_insights_enabled = true
@@
-  skip_final_snapshot = true
+  skip_final_snapshot = false
```

### 10.3 S3

Risques :

- IAM trop large;
- absence de versioning Terraform visible;
- séparation médias publics produits vs médias privés KYC/preuves non formalisée.

Corrections :

```hcl
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

IAM minimal :

```json
{
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
  "Resource": "arn:aws:s3:::market-cm/*"
}
```

### 10.4 IAM

Problème : `AmazonS3ExpressFullAccess` est surdimensionné.

Correction : remplacer par policy dédiée bucket `market-cm`, plus SSM.

### 10.5 Security Groups

État inventaire : `launch-wizard-1` et `SecureGroup-Mcm` avaient SSH ouvert monde; Terraform actuel montre restriction en `/24` pour certains SG.

Correction : vérifier état AWS réel, puis fermer SSH public. Préférer SSM Session Manager sans port 22.

### 10.6 Monitoring

Terraform crée :

- alarmes RDS CPU/storage/memory/connections;
- alarmes EC2 status/cpu;
- SNS email.

Manques :

- logs applicatifs Nginx/Daphne/Celery vers CloudWatch;
- métriques mémoire/disque EC2;
- alertes NotchPay pending > X min;
- alertes Celery queue backlog;
- alertes Redis memory/evictions/latency;
- dashboards p95/p99 API.

---

## PHASE 11 - TESTS

### 11.1 Inventaire actuel

Backend :

- `accounts`: tests sécurité, hardening, readiness, wave1/2/3/567/9/10, paiement E2E.
- `wallets`: tests wallet, sécurité, direct charge.
- `orders`: tests commande + atomicité annulation.
- `analytics`, `innovation`, `notifications`, `support`: tests unitaires.

Frontend :

- un `widget_test.dart` par app (`app`, `Clients`, `Driver App`, `admin`), couverture très faible.

QA E2E :

- `qa_e2e/t1_auth.py` à `t10_security.py`;
- probes WebSocket, NotchPay, charge, bench SQL/concurrence;
- locustfile.

### 11.2 Tests à ajouter pour atteindre >90 %

| Type | Tests requis |
|---|---|
| Unit backend | serializers Product/Order/Wallet/KYC, services `OrderFinanceService`, `WalletAccountingService`, webhook auth |
| Integration API | chaque ViewSet avec rôles BUYER/SUPPLIER/WHOLESALER/TRANSIT_AGENT/GENERAL_ADMIN |
| Contract API | générer OpenAPI et valider payloads Flutter contre schéma |
| Flutter unit | modèles `fromJson/toJson`, repositories API, error mapping 400/401/403/409/429 |
| Flutter widget | auth, panier, KYC, wallet, livraison, admin suspension/reconciliation |
| WebSocket | auth subprotocol, expiry, reconnect, multi-device, suspension active |
| E2E | buyer checkout, seller product/order, driver mission, admin KYC/refund |
| Load | k6/Locust distribué multi-IP, paliers 100/500/1k/2.5k/5k/10k, métriques DB/Redis/Celery |
| Security | SSRF webhook subscription, signed URL KYC, mass assignment tous serializers, IDOR endpoints non consommés |

### 11.3 Commandes de vérification

```powershell
# Backend
cd backend
python manage.py check
python manage.py test apps.accounts apps.wallets apps.orders apps.catalog apps.logistics

# Frontend
cd frontend/app
flutter analyze
flutter test

cd ../Clients
flutter analyze
flutter test

cd "../Driver App/app"
flutter analyze
flutter test

cd ../../admin/project
flutter analyze
flutter test

# Contrat
cd ../../..
python compare.py

# Charge
locust -f qa_e2e/loadtest/locustfile.py --host https://cm.digital-get.com --users 100 --spawn-rate 20 --run-time 5m --headless
```

---

## PHASE 12 - CORRECTIONS PAR PROBLÈME

### BUG-001 - Backend cible incohérent entre mission et apps

1. Cause racine : `AppConfig` des 4 apps utilise `https://marche-cm.onrender.com` par défaut; mission cible `https://cm.digital-get.com`.
2. Impact métier : builds release peuvent parler au mauvais backend, webhooks/DNS/support incohérents.
3. Criticité : Critique.
4. Fichiers : `frontend/app/lib/core/app_config.dart`, `frontend/Clients/lib/core/app_config.dart`, `frontend/Driver App/app/lib/core/config/app_config.dart`, `frontend/admin/project/lib/core/app_config.dart`.
5. Correctif exact : remplacer le défaut release par `https://cm.digital-get.com` ou garantir CI avec `--dart-define=API_BASE_URL=https://cm.digital-get.com`.
6. Diff :

```diff
- defaultValue: "https://marche-cm.onrender.com",
+ defaultValue: "https://cm.digital-get.com",
```

Driver :

```diff
- static const String _prodBaseUrl = 'https://marche-cm.onrender.com';
+ static const String _prodBaseUrl = 'https://cm.digital-get.com';
- : (kDebugMode ? 'ws://10.0.2.2:8000' : 'wss://marche-cm.onrender.com');
+ : (kDebugMode ? 'ws://10.0.2.2:8000' : 'wss://cm.digital-get.com');
```

7. Tests : test unitaire AppConfig release; CI build avec dart-define; smoke `GET /api/health/`.
8. Vérification : désassembler/logguer `AppConfig.apiBaseUrl` en build staging.

### BUG-002 - Endpoint `/api/seller/stats/` absent

1. Cause racine : écran vendeur appelle une route non exposée; backend a `/api/orders/sales-summary/`.
2. Impact : page statistiques vendeur cassée.
3. Criticité : Élevé.
4. Fichier : `frontend/app/lib/features/supplier/supplier_stats_page.dart`.
5. Correctif exact : remplacer par `/api/orders/sales-summary/?range=...` ou créer endpoint backend alias.
6. Diff :

```diff
- .getObject("/api/seller/stats/?range=${_rangeKey()}", token: token);
+ .getObject("/api/orders/sales-summary/?range=${_rangeKey()}", token: token);
```

7. Tests : widget/repository test stats seller; API test sales-summary.
8. Vérification : page stats charge avec 200.

### BUG-003 - Endpoint `/api/driver/reviews/` absent

1. Cause racine : Driver App attend un endpoint profil livreur dédié; backend expose plutôt rating via shipments/products.
2. Impact : écran avis livreur inutilisable.
3. Criticité : Moyen.
4. Fichier : `frontend/Driver App/app/lib/features/profile/presentation/reviews_page.dart`.
5. Correctif exact : soit créer `GET /api/driver/reviews/`, soit consommer `/api/shipments/?status=DELIVERED` + ratings existants.
6. Diff backend proposé :

```diff
diff --git a/backend/apps/logistics/views.py b/backend/apps/logistics/views.py
@@
+class DriverReviewsView(APIView):
+    permission_classes = [permissions.IsAuthenticated]
+    def get(self, request):
+        rows = TransitAgentRating.objects.filter(transit_agent=request.user).order_by("-created_at")
+        return response.Response(TransitAgentRatingSerializer(rows, many=True).data)
```

7. Tests : API 200 pour transitaire, 403/empty pour autre rôle.
8. Vérification : écran Driver reviews non vide.

### BUG-004 - Endpoint `/api/shipments/{id}/resend_otp/` absent

1. Cause racine : bouton frontend sans action backend.
2. Impact : si OTP livraison expire/perdu, livreur/support bloqué.
3. Criticité : Élevé.
4. Fichiers : `delivery_proof_page.dart`, `apps/logistics/views.py`.
5. Correctif exact : implémenter action `resend_otp` avec rate limit et audit, ou retirer le bouton.
6. Diff proposé :

```diff
diff --git a/backend/apps/logistics/views.py b/backend/apps/logistics/views.py
@@
+    @decorators.action(detail=True, methods=["post"], url_path="resend_otp")
+    def resend_otp(self, request, pk=None):
+        shipment = self.get_object()
+        if shipment.transit_agent_id != request.user.id:
+            return response.Response({"detail": "Action reservee au livreur assigne."}, status=403)
+        # generate/send OTP through notification/SMS provider
+        return response.Response({"detail": "OTP renvoye."})
```

7. Tests : rate limit, mauvais livreur 403, shipment inexistant 404, audit log.
8. Vérification : bouton Driver reçoit 200.

### BUG-005 - Médias S3/R2 non servables ou confidentialité ambiguë

1. Cause racine : URLs peuvent pointer vers endpoint API S3/R2 privé; pas de séparation public/private claire.
2. Impact : images produits/chat/KYC invisibles ou documents sensibles exposés.
3. Criticité : Critique.
4. Fichiers : `backend/config/settings.py`, infra S3/CloudFront.
5. Correctif exact : bucket privé + CloudFront/OAC; URLs signées pour KYC/preuves; domaine public pour produits.
6. Diff settings indicatif :

```diff
- AWS_QUERYSTRING_AUTH = _env_bool("AWS_QUERYSTRING_AUTH", False)
+ AWS_QUERYSTRING_AUTH = _env_bool("AWS_QUERYSTRING_AUTH", True)
```

7. Tests : upload produit GET public 200 si public; KYC URL non accessible sans signature; signature expire.
8. Vérification : curl URLs médias depuis réseau externe.

### BUG-006 - `broadcast_event` peut faire échouer des écritures métier si Redis tombe

1. Cause racine : `async_to_sync(group_send)` appelé dans chemin requête sans tolérance panne.
2. Impact : création produit/profil/chat peut retourner 500 même si DB OK.
3. Criticité : Élevé.
4. Fichier : `backend/apps/notifications/realtime.py`.
5. Correctif exact : try/except + log + éventuellement outbox Celery.
6. Diff : voir PERF-003.
7. Tests : monkeypatch channel layer exception; endpoint doit répondre 2xx.
8. Vérification : couper Redis staging et créer produit.

### BUG-007 - N+1 `/api/chat/rooms/`

1. Cause racine : participants non préfetchés.
2. Impact : latence et charge DB linéaire avec salons.
3. Criticité : Moyen.
4. Fichier : `backend/apps/chat/views.py`.
5. Correctif : `prefetch_related("participants")`.
6. Diff : voir PERF-001.
7. Tests : `assertNumQueries` constant.
8. Vérification : bench SQL.

### BUG-008 - SSH / IAM / EBS AWS

1. Cause racine : infra créée manuellement puis importée, SG et IAM larges.
2. Impact : compromission serveur ou médias.
3. Criticité : Critique.
4. Fichiers : `infra/terraform/generated.tf`.
5. Correctif : SSM au lieu SSH, SG restreint, EBS chiffré, IAM least privilege.
6. Diffs : voir Phase 10.
7. Tests : `terraform plan`, AWS Config/Security Hub, connexion SSM.
8. Vérification : `aws ec2 describe-security-groups`, `describe-volumes`.

### BUG-009 - RDS sans Multi-AZ / Performance Insights

1. Cause racine : configuration coût/simple.
2. Impact : panne AZ ou diagnostic incident difficile.
3. Criticité : Élevé.
4. Fichier : `infra/terraform/generated.tf`.
5. Correctif : `multi_az=true`, PI on, snapshots finaux.
6. Diff : voir Phase 10.
7. Tests : `terraform plan`, failover drill.
8. Vérification : console RDS.

### BUG-010 - Webhook timestamp non obligatoire

1. Cause racine : `WEBHOOK_REQUIRE_TIMESTAMP=False` par défaut.
2. Impact : HMAC protège, mais replay dans certains scénarios reste moins borné.
3. Criticité : Moyen.
4. Fichier : `backend/config/settings.py`.
5. Correctif : activer en prod après accord NotchPay.
6. Diff :

```diff
- WEBHOOK_REQUIRE_TIMESTAMP = _env_bool("WEBHOOK_REQUIRE_TIMESTAMP", False)
+ WEBHOOK_REQUIRE_TIMESTAMP = _env_bool("WEBHOOK_REQUIRE_TIMESTAMP", not DEBUG)
```

7. Tests : webhook sans timestamp 403 en prod, timestamp vieux 403, valide 200.
8. Vérification : test NotchPay staging.

### BUG-011 - Double système KYC

1. Cause racine : `accounts.ComplianceDocument` et `compliance.KYCApplication` coexistent.
2. Impact : divergence statut conformité, admin incomplet.
3. Criticité : Moyen.
4. Fichiers : `apps/accounts`, `apps/compliance`, front KYC/admin.
5. Correctif : choisir système canonique; créer migration/adapters.
6. Diff : architecture, non trivial.
7. Tests : un statut KYC unique visible dans `/api/auth/me/`.
8. Vérification : un document approuvé met à jour le même statut partout.

### BUG-012 - Capacité 100 000 non prouvée

1. Cause racine : load test mono-IP limité par Cloudflare/DRF, pas par serveur.
2. Impact : impossible de garantir demain 100k utilisateurs.
3. Criticité : Élevé.
4. Fichiers : infra/loadtest.
5. Correctif : test distribué multi-IP + métriques DB/Redis/Celery.
6. Diff : ajouter pipeline k6/Locust distribué.
7. Tests : paliers 100 -> 10k, extrapolation 100k par architecture.
8. Vérification : rapport p95/p99, erreurs <1%, DB connections maîtrisées.

---

## PHASE 13 - RAPPORT FINAL

### Tableau des bugs

| ID | Gravité | Module | Description | Impact |
|---|---|---|---|---|
| BUG-001 | Critique | Front config | backend par défaut `marche-cm.onrender.com` au lieu de `cm.digital-get.com` | mauvais environnement prod |
| BUG-002 | Élevé | Vendeur | `/api/seller/stats/` absent | stats vendeur cassées |
| BUG-003 | Moyen | Driver | `/api/driver/reviews/` absent | avis livreur cassés |
| BUG-004 | Élevé | Livraison | `/api/shipments/{id}/resend_otp/` absent | OTP non renvoyable |
| BUG-005 | Critique | S3/R2 | médias non servables/confidentialité floue | catalogue/KYC/chat affectés |
| BUG-006 | Élevé | Realtime/Redis | broadcast synchrone peut faire 500 | écritures métier fragiles |
| BUG-007 | Moyen | Chat | N+1 `/api/chat/rooms/` | charge DB |
| BUG-008 | Critique | AWS | SSH/IAM/EBS à durcir | compromission infra |
| BUG-009 | Élevé | RDS | pas Multi-AZ/PI | disponibilité/diagnostic |
| BUG-010 | Moyen | Paiement | timestamp webhook optionnel | replay hardening incomplet |
| BUG-011 | Moyen | KYC | double modèle conformité | divergence métier |
| BUG-012 | Élevé | Performance | 100k non prouvé | risque capacité |

### Tableau des corrections

| ID | Statut | Fichier | Solution |
|---|---|---|---|
| BUG-001 | À faire | `frontend/*/app_config.dart` | remplacer default backend ou CI dart-define obligatoire |
| BUG-002 | À faire | `supplier_stats_page.dart` | utiliser `/api/orders/sales-summary/` |
| BUG-003 | À arbitrer | Driver reviews + backend logistics | créer endpoint reviews ou retirer écran |
| BUG-004 | À faire | `logistics/views.py` | action `resend_otp` rate-limitée |
| BUG-005 | À faire | `settings.py`, Terraform S3/CloudFront | domaine média public + URLs signées privées |
| BUG-006 | À faire | `notifications/realtime.py` | broadcast best-effort |
| BUG-007 | À faire | `chat/views.py` | `prefetch_related` |
| BUG-008 | À faire | `infra/terraform/generated.tf` | SG/SSM/IAM/EBS |
| BUG-009 | À décider coût | `infra/terraform/generated.tf` | Multi-AZ + Performance Insights |
| BUG-010 | À coordonner provider | `settings.py` | timestamp webhook requis en prod |
| BUG-011 | Architecture | KYC apps | définir système canonique |
| BUG-012 | QA/DevOps | `qa_e2e/loadtest` | load test distribué |

### Tableau des risques restants

| Risque | Probabilité | Impact |
|---|---:|---:|
| Builds mobiles pointent mauvais backend | Élevée | Critique |
| Média produit/KYC inaccessible | Élevée | Critique |
| Incident Redis provoque 500 sur writes | Moyenne | Élevé |
| DB saturée sans pool à forte charge | Élevée | Critique |
| SSH/IAM trop permissifs si état AWS réel non durci | Moyenne | Critique |
| NotchPay mal configuré | Moyenne | Critique |
| Double KYC cause divergence conformité | Moyenne | Moyen |
| 100k utilisateurs non validés | Élevée | Élevé |
| NAT opérateur mobile déclenche 429 faux positifs | Moyenne | Élevé |

### Scores sur 100

| Domaine | Score | Justification |
|---|---:|---|
| Architecture | 74 | découpage riche mais double KYC/litiges, routes legacy, backend cible incohérent |
| Backend | 82 | beaucoup de hardening, atomicité financière, RBAC; quelques endpoints front absents |
| Frontend | 68 | sécurité Dio correcte, mais config backend mauvaise et couverture tests faible |
| Sécurité | 76 | très bon applicatif, infra/IAM/S3 à durcir |
| Performance | 70 | catalogue optimisé; N+1 chat, pool DB/load 100k non prouvés |
| DevOps | 62 | Terraform en progrès, mais double EC2, ECR/CI/CD/CloudWatch logs incomplets |
| Maintenabilité | 73 | code structuré, mais beaucoup de surface et duplications fonctionnelles |

Score global pondéré : 72 / 100.

---

## Vérification exécutée pendant cet audit

```text
python manage.py check
=> System check identified no issues (0 silenced).
```

```text
python compare.py
=> frontend missing backend:
   /api/driver/reviews/
   /api/seller/stats/
   /api/shipments/{param}/resend_otp/
```

```text
python qa_e2e/check_screen_backend_alignment.py
=> échec environnemental:
   JWT_ALGORITHM=RS256 requires both JWT_SIGNING_KEY and JWT_VERIFYING_KEY.
```
