# API Role Audit (Frontend)

Date: 2026-03-06

## Role routing
- `GENERAL_ADMIN` -> `AdminDashboardPage`
- `SUPPLIER` -> `SupplierDashboardPage`
- `WHOLESALER` -> `WholesalerDashboardPage`
- `TRANSIT_AGENT` -> `TransitDashboardPage`
- `BUYER` -> `FeedPage` (buyer flow)

Le changement manuel de role dans les menus frontend a ete retire pour forcer l'usage du role reel de session.

## APIs connectees par role (frontend)
- `GENERAL_ADMIN`
  - `/api/admin/dashboard/`
  - `/api/admin/audit/export/`
  - `/api/users/`, `/api/users/online/`, `/api/users/create_managed_user/`
  - `/api/compliance-documents/`, `/api/compliance-documents/{id}/review/`
  - `/api/orders/`, `/api/shipments/`, `/api/shipment-disputes/`, `/api/shipment-disputes/{id}/decide/`
  - `/api/wallets/reconcile/`
- `SUPPLIER`
  - `/api/products/mine/`, `/api/products/`
  - `/api/orders/`, `/api/rfqs/`, `/api/rfq-offers/`, `/api/campaigns/`
  - `/api/wallets/`, `/api/compliance-documents/`
  - `/api/shipments/{id}/accept_quote/`
- `WHOLESALER`
  - `/api/products/mine/`, `/api/products/`
  - `/api/orders/`, `/api/rfqs/`, `/api/rfq-offers/`, `/api/campaigns/`
  - `/api/shipments/`, `/api/wallets/`, `/api/compliance-documents/`
  - `/api/shipments/{id}/accept_quote/`
- `TRANSIT_AGENT`
  - `/api/shipments/`, `/api/transport-quotes/`, `/api/transport-profiles/`
  - `/api/shipment-disputes/`
  - actions: `post_quote`, `update_status`, `submit_proof`, `open_dispute`
- `BUYER`
  - `/api/products/`, `/api/products/recommended/`, `/api/products/image-search/`, `/api/products/track-view/`
  - `/api/orders/`, `/api/orders/{id}/confirm_delivery/`
  - `/api/shipments/{id}/validate_delivery/`, `/api/shipments/{id}/rate_transit_agent/`
  - `/api/rfqs/`, `/api/rfq-offers/`
  - `/api/chat/rooms/`, `/api/chat/messages/`, `/api/chat/messages/{id}/mark_delivered/`, `/api/chat/messages/{id}/mark_read/`
  - `/api/wallets/`, `/api/wallets/transactions/`, `/api/wallets/request_otp/`, `/api/wallets/topup/`, `/api/wallets/withdraw/`

## APIs backend non reliees au frontend (a ce jour)
- `/api/auth/login/verify/` (desactive, flux OTP retire)
- `/api/auth/refresh/` (refresh automatique non implemente cote frontend)
- `/api/auth/verify-email/` (desactive)
- `/api/health/` (pas d'ecran monitoring frontend)
- `/api/wallets/notchpay/checkout/webhook/` (endpoint serveur-a-serveur, normal non expose frontend)
- `/api/wallets/notchpay/disburse/webhook/` (endpoint serveur-a-serveur, normal non expose frontend)

## Note
- `/api/products/image-search/` et `/api/products/track-view/` sont utilises via URL absolue dans `feed_api_service.dart`.
