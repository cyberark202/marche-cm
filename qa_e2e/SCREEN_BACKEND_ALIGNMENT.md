# Alignement écrans Flutter ↔ Backend

> Généré par `qa_e2e/check_screen_backend_alignment.py` (introspection URLconf Django + scan des littéraux `/api/` des 4 apps).

- Routes backend `/api/` : **167**
- Endpoints distincts référencés côté Flutter : **107**
- Endpoints alignés : **101**
- ❌ Appels frontend SANS route backend : **6**
- ℹ️ Routes backend non appelées : **66**

## ❌ Désalignements (à corriger)

### `/api/driver/reviews/`
- `/api/driver/reviews/` — Driver App · [frontend/Driver App/app/lib/features/profile/presentation/reviews_page.dart:11](frontend/Driver App/app/lib/features/profile/presentation/reviews_page.dart#L11)

### `/api/orders/{param}/confirm/`
- `/api/orders/$id/confirm/` — app · [frontend/app/lib/features/supplier/supplier_orders_received_page.dart:69](frontend/app/lib/features/supplier/supplier_orders_received_page.dart#L69)
- `/api/orders/{param}/confirm/` — app · [frontend/app/lib/features/supplier/supplier_order_detail_page.dart:58](frontend/app/lib/features/supplier/supplier_order_detail_page.dart#L58)

### `/api/orders/{param}/request-quote/`
- `/api/orders/{param}/request-quote/` — app · [frontend/app/lib/features/supplier/supplier_order_detail_page.dart:78](frontend/app/lib/features/supplier/supplier_order_detail_page.dart#L78)

### `/api/seller/stats/`
- `/api/seller/stats/?range={param}` — app · [frontend/app/lib/features/supplier/supplier_stats_page.dart:52](frontend/app/lib/features/supplier/supplier_stats_page.dart#L52)

### `/api/shipments/{param}/quote/`
- `/api/shipments/{param}/quote/` — Driver App · [frontend/Driver App/app/lib/features/missions/presentation/quote_send_page.dart:57](frontend/Driver App/app/lib/features/missions/presentation/quote_send_page.dart#L57)

### `/api/shipments/{param}/resend_otp/`
- `/api/shipments/{param}/resend_otp/` — Driver App · [frontend/Driver App/app/lib/features/delivery/presentation/delivery_proof_page.dart:86](frontend/Driver App/app/lib/features/delivery/presentation/delivery_proof_page.dart#L86)

## ℹ️ Routes backend non référencées par une app
- `/api/audit/events/{param}/`
- `/api/auth/login/verify/`
- `/api/auth/verify-email/`
- `/api/campaigns/{param}/`
- `/api/chat/messages/{param}/`
- `/api/chat/rooms/{param}/`
- `/api/compliance-documents/{param}/`
- `/api/compliance/kyc/`
- `/api/compliance/kyc/{param}/`
- `/api/compliance/kyc/{param}/approve/`
- `/api/compliance/kyc/{param}/reject/`
- `/api/disputes/`
- `/api/disputes/open/`
- `/api/disputes/{param}/`
- `/api/disputes/{param}/decide/`
- `/api/disputes/{param}/escalate/`
- `/api/disputes/{param}/timeline/`
- `/api/escrow/holds/{param}/`
- `/api/escrow/holds/{param}/freeze/`
- `/api/escrow/holds/{param}/mark-condition/`
- `/api/escrow/holds/{param}/transitions/`
- `/api/fraud/assessments/`
- `/api/fraud/assessments/{param}/`
- `/api/fraud/assessments/{param}/review/`
- `/api/fraud/risk-profiles/{param}/`
- `/api/innovation/notifications/smart-run/`
- `/api/ledger/accounts/`
- `/api/ledger/accounts/{param}/`
- `/api/ledger/accounts/{param}/balance/`
- `/api/ledger/transactions/`
- `/api/ledger/transactions/{param}/`
- `/api/notifications/{param}/`
- `/api/partner-api-keys/{param}/`
- `/api/price-alerts/{param}/`
- `/api/product-favorites/{param}/`
- `/api/products/image-search/`
- `/api/products/track-view/`
- `/api/rfq-counter-offers/{param}/`
- `/api/rfq-counter-offers/{param}/decide/`
- `/api/rfq-offers/{param}/`
- `/api/rfqs/{param}/`
- `/api/schema/`
- `/api/schema/redoc/`
- `/api/schema/swagger/`
- `/api/shipment-disputes/{param}/custody-chain/`
- `/api/shipment-disputes/{param}/inspection-report/`
- `/api/shipments/{param}/supplier/admin-validate/`
- `/api/shipments/{param}/supplier/confirm/`
- `/api/shipments/{param}/supplier/proof/`
- `/api/support/tickets/{param}/assign/`
- `/api/transport-quotes/{param}/`
- `/api/users/create_managed_user/`
- `/api/users/{param}/suspend/`
- `/api/users/{param}/unsuspend/`
- `/api/users/{param}/verification-status/`
- `/api/video-comments/{param}/`
- `/api/video-likes/`
- `/api/wallet-approval-requests/{param}/`
- `/api/wallet-approval-requests/{param}/decide/`
- `/api/wallets/notchpay/checkout/webhook/`
- `/api/wallets/notchpay/disburse/webhook/`
- `/api/wallets/paydunya/checkout/webhook/`
- `/api/wallets/paydunya/disburse/webhook/`
- `/api/wallets/request_otp/`
- `/api/wallets/{param}/`
- `/api/webhook-subscriptions/{param}/`
