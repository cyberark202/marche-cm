from django.contrib import admin
from django.conf import settings
from django.conf.urls.static import static
from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from config.health import HealthView
from apps.accounts.views import (
    AdminDashboardView,
    AuditLogExportView,
    AuthDisabledView,
    ComplianceDocumentViewSet,
    FCMTokenView,
    GoogleAuthView,
    LoginRequestView,
    LoginVerifyView,
    LogoutView,
    MeView,
    ProfileUpdateView,
    ResolveLocationView,
    RegisterView,
    SensitiveActionRequestView,
    SessionManagementView,
    PasswordChangeView,
    UiConfigView,
    UserViewSet,
    VerifyEmailView,
    WalletPinView,
)
from apps.accounts.driver_views import (
    DriverRegisterView,
    DriverProfileView,
    DriverKYCView,
    DriverWalletView,
    DriverTransactionsView,
    DriverEarningsView,
    DriverWithdrawView,
)
from apps.catalog.views import ProductFavoriteViewSet, ProductViewSet, SavedProductFilterViewSet, VideoCommentViewSet, VideoLikeViewSet
from apps.chat.views import ChatRoomViewSet, MessageViewSet
from apps.analytics.views import GroupCampaignViewSet, RFQOfferViewSet, RequestForQuotationViewSet
from apps.logistics.views import ShipmentDisputeViewSet, ShipmentViewSet, TransportProfileViewSet, TransportQuoteViewSet
from apps.notifications.views import NotificationViewSet
from apps.innovation.views import (
    DisputeEscalationView,
    EscrowSplitPreviewView,
    LoyaltyAccountView,
    OnboardingChecklistView,
    PartnerApiKeyViewSet,
    PriceAlertViewSet,
    RecommendationReasonsView,
    SmartNotificationsRunView,
    RFQCompareView,
    RFQCounterOfferViewSet,
    SellerDashboardInsightsView,
    ShipmentTimelineView,
    WalletApprovalRequestViewSet,
    WebhookSubscriptionViewSet,
)
from apps.orders.views import OrderViewSet
from apps.support.views import SupportTicketViewSet
from apps.wallets.views import WalletViewSet

router = DefaultRouter()
router.register("users", UserViewSet, basename="user")
router.register("compliance-documents", ComplianceDocumentViewSet, basename="compliance-document")
router.register("products", ProductViewSet, basename="product")
router.register("product-favorites", ProductFavoriteViewSet, basename="product-favorite")
router.register("product-filters", SavedProductFilterViewSet, basename="product-filter")
router.register("video-likes", VideoLikeViewSet, basename="video-like")
router.register("video-comments", VideoCommentViewSet, basename="video-comment")
router.register("orders", OrderViewSet, basename="order")
router.register("wallets", WalletViewSet, basename="wallet")
router.register("chat/rooms", ChatRoomViewSet, basename="chat-room")
router.register("chat/messages", MessageViewSet, basename="chat-message")
router.register("campaigns", GroupCampaignViewSet, basename="campaign")
router.register("rfqs", RequestForQuotationViewSet, basename="rfq")
router.register("rfq-offers", RFQOfferViewSet, basename="rfq-offer")
router.register("transport-profiles", TransportProfileViewSet, basename="transport-profile")
router.register("shipments", ShipmentViewSet, basename="shipment")
router.register("transport-quotes", TransportQuoteViewSet, basename="transport-quote")
router.register("shipment-disputes", ShipmentDisputeViewSet, basename="shipment-dispute")
router.register("price-alerts", PriceAlertViewSet, basename="price-alert")
router.register("rfq-counter-offers", RFQCounterOfferViewSet, basename="rfq-counter-offer")
router.register("wallet-approval-requests", WalletApprovalRequestViewSet, basename="wallet-approval-request")
router.register("partner-api-keys", PartnerApiKeyViewSet, basename="partner-api-key")
router.register("webhook-subscriptions", WebhookSubscriptionViewSet, basename="webhook-subscription")
router.register("notifications", NotificationViewSet, basename="notification")
router.register("support/tickets", SupportTicketViewSet, basename="support-ticket")

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/health/", HealthView.as_view(), name="health"),
    path("api/ui-config/", UiConfigView.as_view(), name="ui-config"),
    path(
        "api/auth/register/",
        AuthDisabledView.as_view() if settings.AUTH_LOCKDOWN else RegisterView.as_view(),
        name="auth-register",
    ),
    path(
        "api/auth/login/",
        AuthDisabledView.as_view() if settings.AUTH_LOCKDOWN else LoginRequestView.as_view(),
        name="auth-login-request",
    ),
    path(
        "api/auth/login/verify/",
        AuthDisabledView.as_view() if settings.AUTH_LOCKDOWN else LoginVerifyView.as_view(),
        name="auth-login-verify",
    ),
    path(
        "api/auth/refresh/",
        AuthDisabledView.as_view() if settings.AUTH_LOCKDOWN else TokenRefreshView.as_view(),
        name="token_refresh",
    ),
    path("api/auth/logout/", LogoutView.as_view(), name="auth-logout"),
    path("api/auth/me/", MeView.as_view(), name="auth-me"),
    path("api/auth/profile/", ProfileUpdateView.as_view(), name="auth-profile-update"),
    path("api/auth/location/resolve/", ResolveLocationView.as_view(), name="auth-location-resolve"),
    path("api/auth/wallet-pin/", WalletPinView.as_view(), name="auth-wallet-pin"),
    path("api/auth/sensitive-action/request/", SensitiveActionRequestView.as_view(), name="auth-sensitive-action-request"),
    path("api/auth/sessions/", SessionManagementView.as_view(), name="auth-sessions"),
    path("api/auth/password-change/", PasswordChangeView.as_view(), name="auth-password-change"),
    path("api/admin/dashboard/", AdminDashboardView.as_view(), name="admin-dashboard"),
    path("api/admin/audit/export/", AuditLogExportView.as_view(), name="admin-audit-export"),
    path("api/loyalty/account/", LoyaltyAccountView.as_view(), name="loyalty-account"),
    path("api/innovation/escrow-split/", EscrowSplitPreviewView.as_view(), name="innovation-escrow-split"),
    path("api/innovation/rfq-compare/", RFQCompareView.as_view(), name="innovation-rfq-compare"),
    path("api/innovation/shipment-timeline/", ShipmentTimelineView.as_view(), name="innovation-shipment-timeline"),
    path(
        "api/innovation/disputes/<int:dispute_id>/escalate/",
        DisputeEscalationView.as_view(),
        name="innovation-dispute-escalate",
    ),
    path(
        "api/innovation/onboarding/checklist/",
        OnboardingChecklistView.as_view(),
        name="innovation-onboarding-checklist",
    ),
    path(
        "api/innovation/seller-dashboard/",
        SellerDashboardInsightsView.as_view(),
        name="innovation-seller-dashboard",
    ),
    path(
        "api/innovation/recommendations/reasons/",
        RecommendationReasonsView.as_view(),
        name="innovation-recommendation-reasons",
    ),
    path(
        "api/innovation/notifications/smart-run/",
        SmartNotificationsRunView.as_view(),
        name="innovation-smart-notifications-run",
    ),
    path("api/auth/fcm-token/", FCMTokenView.as_view(), name="auth-fcm-token"),
    path("api/auth/verify-email/", VerifyEmailView.as_view(), name="auth-verify-email"),
    # ── Driver-specific endpoints ─────────────────────────────────────────
    path("api/driver/register/", DriverRegisterView.as_view(), name="driver-register"),
    path("api/accounts/driver-profile/", DriverProfileView.as_view(), name="driver-profile"),
    path("api/accounts/driver-kyc/", DriverKYCView.as_view(), name="driver-kyc"),
    path("api/wallets/driver/", DriverWalletView.as_view(), name="driver-wallet"),
    path("api/wallets/driver/transactions/", DriverTransactionsView.as_view(), name="driver-transactions"),
    path("api/wallets/driver/earnings/", DriverEarningsView.as_view(), name="driver-earnings"),
    path("api/wallets/driver/withdraw/", DriverWithdrawView.as_view(), name="driver-withdraw"),
    path(
        "api/auth/google/",
        AuthDisabledView.as_view() if settings.AUTH_LOCKDOWN else GoogleAuthView.as_view(),
        name="auth-google",
    ),
    path("api/", include(router.urls)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
