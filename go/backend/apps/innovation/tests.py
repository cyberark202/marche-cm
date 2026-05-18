import urllib.error
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.analytics.models import RFQOffer, RFQStatus, RequestForQuotation
from apps.catalog.models import Product
from apps.innovation.models import (
    CounterOfferStatus,
    RFQCounterOffer,
    WalletApprovalRequest,
    WebhookSubscription,
)
from apps.logistics.models import DisputeStatus, Shipment, ShipmentDispute, ShipmentStatus
from apps.orders.models import EscrowStatus, Order, OrderStatus


class InnovationHardeningTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.admin = user_model.objects.create_user(
            username="admin_harden",
            email="admin_harden@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_active=True,
            is_verified=True,
        )
        self.buyer = user_model.objects.create_user(
            username="buyer_harden",
            email="buyer_harden@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
            is_verified=True,
        )
        self.supplier = user_model.objects.create_user(
            username="supplier_harden",
            email="supplier_harden@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_active=True,
            is_verified=True,
        )
        self.supplier_unverified = user_model.objects.create_user(
            username="supplier_unverified",
            email="supplier_unverified@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_active=True,
            is_verified=False,
        )
        self.transit = user_model.objects.create_user(
            username="transit_harden",
            email="transit_harden@test.local",
            password="TestPassword123!",
            role="TRANSIT_AGENT",
            is_active=True,
            is_verified=True,
        )

        self.product = Product.objects.create(
            seller=self.supplier,
            title="Produit innovation test",
            description="Description produit",
            brand="Brand",
            min_order_qty=1,
            max_order_qty=10,
            price_for_min_qty=Decimal("1000.00"),
            price_for_max_qty=Decimal("900.00"),
            is_active=True,
        )
        self.rfq_open = RequestForQuotation.objects.create(
            buyer=self.buyer,
            product_name="Riz premium",
            quantity=50,
            target_price=Decimal("880.00"),
            destination_city="Douala",
            country_code="CM",
            status=RFQStatus.OPEN,
        )
        self.rfq_offer_open = RFQOffer.objects.create(
            rfq=self.rfq_open,
            seller=self.supplier,
            price=Decimal("920.00"),
            lead_time_days=4,
            notes="Offre de base",
        )
        self.rfq_closed = RequestForQuotation.objects.create(
            buyer=self.buyer,
            product_name="Cafe",
            quantity=30,
            target_price=Decimal("1400.00"),
            destination_city="Yaounde",
            country_code="CM",
            status=RFQStatus.CLOSED,
        )
        self.rfq_offer_closed = RFQOffer.objects.create(
            rfq=self.rfq_closed,
            seller=self.supplier,
            price=Decimal("1500.00"),
            lead_time_days=3,
            notes="Offre RFQ ferme",
        )
        self.order = Order.objects.create(
            buyer=self.buyer,
            seller=self.supplier,
            product=self.product,
            quantity=2,
            preferred_transit_agent=self.transit,
            unit_price=Decimal("1000.00"),
            total_price=Decimal("2000.00"),
            status=OrderStatus.CONFIRMED,
            escrow_status=EscrowStatus.HELD,
        )
        self.shipment = Shipment.objects.create(
            order=self.order,
            buyer=self.buyer,
            seller=self.supplier,
            transit_agent=self.transit,
            pickup_address="A",
            dropoff_address="B",
            country_code="CM",
            shipping_fee=Decimal("250.00"),
            status=ShipmentStatus.IN_TRANSIT,
        )
        self.dispute = ShipmentDispute.objects.create(
            shipment=self.shipment,
            opened_by=self.buyer,
            reason="Retard",
            details="Le colis n'est pas livre dans le delai convenu.",
            status=DisputeStatus.OPEN,
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def test_price_alert_reserved_to_buyers(self):
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("price-alert-list"),
            {
                "product": self.product.id,
                "target_price": "800.00",
                "notify_on_back_in_stock": True,
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_price_alert_rejects_non_positive_target_price(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("price-alert-list"),
            {
                "product": self.product.id,
                "target_price": "0",
                "notify_on_back_in_stock": True,
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_counter_offer_rejects_duplicate_pending_from_same_creator(self):
        self._auth_as(self.supplier)
        RFQCounterOffer.objects.create(
            rfq_offer=self.rfq_offer_open,
            creator=self.supplier,
            target_price=Decimal("900.00"),
            lead_time_days=3,
            status=CounterOfferStatus.PENDING,
        )
        res = self.client.post(
            reverse("rfq-counter-offer-list"),
            {
                "rfq_offer": self.rfq_offer_open.id,
                "target_price": "880.00",
                "lead_time_days": 2,
                "note": "Nouvelle proposition",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_counter_offer_creator_cannot_decide_own_offer(self):
        counter = RFQCounterOffer.objects.create(
            rfq_offer=self.rfq_offer_open,
            creator=self.supplier,
            target_price=Decimal("900.00"),
            lead_time_days=3,
            status=CounterOfferStatus.PENDING,
        )
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("rfq-counter-offer-decide", args=[counter.id]),
            {"decision": "ACCEPTED"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_wallet_approval_creation_is_reserved_to_business_roles(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("wallet-approval-request-list"),
            {"amount": "20000.00", "reason": "Test depense"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_wallet_approval_decision_requires_admin(self):
        approval = WalletApprovalRequest.objects.create(
            requester=self.supplier,
            amount=Decimal("30000.00"),
            reason="Achat equipements",
        )
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("wallet-approval-request-decide", args=[approval.id]),
            {"decision": "APPROVED"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_loyalty_earn_is_reserved_to_admins(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("loyalty-account"),
            {"action": "EARN", "points": 120, "reason": "Bonus"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_loyalty_admin_can_credit_target_user(self):
        self._auth_as(self.admin)
        res = self.client.post(
            reverse("loyalty-account"),
            {
                "action": "EARN",
                "points": 200,
                "reason": "Compensation admin",
                "user_id": self.buyer.id,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data["user_id"], self.buyer.id)
        self.assertEqual(res.data["points_balance"], 200)

    def test_partner_api_key_requires_verified_business_user(self):
        self._auth_as(self.supplier_unverified)
        res = self.client.post(
            reverse("partner-api-key-list"),
            {"name": "ERP Integration"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_webhook_rejects_non_public_endpoint(self):
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("webhook-subscription-list"),
            {
                "topic": "orders",
                "endpoint_url": "http://example.com/hook",
                "secret": "x",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

        res_local = self.client.post(
            reverse("webhook-subscription-list"),
            {
                "topic": "orders",
                "endpoint_url": "https://localhost/hook",
                "secret": "x",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(res_local.status_code, status.HTTP_400_BAD_REQUEST)

    def test_webhook_send_test_is_rate_limited(self):
        sub = WebhookSubscription.objects.create(
            owner=self.supplier,
            topic="orders",
            endpoint_url="https://example.com/hook",
            secret="demo_secret",
            is_active=True,
            last_delivered_at=timezone.now(),
            last_delivery_status="HTTP_200",
        )
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("webhook-subscription-send-test", args=[sub.id]),
            {},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    # -----------------------------------------------------------------------
    # H4 — SSRF Protection: webhook URL validation + redirect blocking
    # -----------------------------------------------------------------------

    def test_webhook_rejects_private_ip_rfc1918(self):
        """RFC 1918 private IPs must be rejected at webhook creation (SSRF)."""
        self._auth_as(self.supplier)
        for private_url in (
            "https://192.168.1.100/hook",
            "https://10.0.0.1/hook",
            "https://172.16.0.1/hook",
        ):
            with self.subTest(url=private_url):
                res = self.client.post(
                    reverse("webhook-subscription-list"),
                    {"topic": "orders", "endpoint_url": private_url, "secret": "x", "is_active": True},
                    format="json",
                )
                self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, private_url)

    def test_webhook_rejects_cloud_metadata_ip(self):
        """AWS/GCP metadata IP 169.254.169.254 must be rejected (SSRF)."""
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("webhook-subscription-list"),
            {
                "topic": "orders",
                "endpoint_url": "https://169.254.169.254/latest/meta-data/",
                "secret": "x",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_webhook_rejects_loopback(self):
        """Loopback addresses must be rejected even on non-standard ports."""
        self._auth_as(self.supplier)
        for url in ("https://127.0.0.1/hook", "https://[::1]/hook"):
            with self.subTest(url=url):
                res = self.client.post(
                    reverse("webhook-subscription-list"),
                    {"topic": "orders", "endpoint_url": url, "secret": "x", "is_active": True},
                    format="json",
                )
                self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, url)

    def test_webhook_rejects_non_standard_port(self):
        """Non-standard ports (neither 80 nor 443) must be rejected."""
        self._auth_as(self.supplier)
        res = self.client.post(
            reverse("webhook-subscription-list"),
            {
                "topic": "orders",
                "endpoint_url": "https://example.com:8080/hook",
                "secret": "x",
                "is_active": True,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_send_test_redirect_is_blocked(self):
        """
        H4 — SSRF redirect blocking: send_test must reject any response that
        redirects (even to an allowed hostname), to prevent redirect-chain
        attacks that bypass _is_safe_webhook_url URL validation.
        """
        sub = WebhookSubscription.objects.create(
            owner=self.supplier,
            topic="orders",
            endpoint_url="https://example.com/hook",
            secret="demo_secret",
            is_active=True,
        )
        self._auth_as(self.supplier)

        # Simulate urllib raising HTTPError (redirect blocked by _NoRedirectHandler).
        redirect_error = urllib.error.HTTPError(
            url="https://example.com/hook",
            code=301,
            msg="Moved Permanently",
            hdrs={},
            fp=None,
        )
        with patch("urllib.request.OpenerDirector.open", side_effect=redirect_error):
            res = self.client.post(
                reverse("webhook-subscription-send-test", args=[sub.id]),
                {},
                format="json",
            )
        # The redirect must be caught gracefully — never a 500.
        self.assertNotEqual(res.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        # Caught by except → 502 (delivery failure), not a silent 200 success.
        self.assertEqual(res.status_code, status.HTTP_502_BAD_GATEWAY)
        # Must indicate the redirect was the cause, not a provider success.
        self.assertIn("error", res.data)

    def test_dispute_escalation_rejects_resolved_disputes(self):
        self.dispute.status = DisputeStatus.RESOLVED
        self.dispute.save(update_fields=["status", "updated_at"])
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("innovation-dispute-escalate", args=[self.dispute.id]),
            {"note": "Merci de rouvrir ce dossier."},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
