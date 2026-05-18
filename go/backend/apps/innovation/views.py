import hashlib
import ipaddress
import json
import secrets
import socket
import urllib.request
from datetime import timedelta
from decimal import Decimal
from urllib.parse import urlparse

from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, Q, Sum
from django.utils import timezone
from rest_framework import decorators, permissions, response, status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.accounts.models import UserRole
from apps.accounts.security import write_audit_log
from apps.analytics.models import RFQOffer, RFQStatus, RequestForQuotation
from apps.catalog.models import BuyerPreferenceProfile, BuyerProductInteraction, Product
from apps.logistics.models import DisputeStatus, Shipment, ShipmentDispute, ShipmentEvent
from apps.orders.models import EscrowStatus, Order, OrderStatus
from apps.wallets.models import TransactionStatus, WalletTransaction
from apps.notifications.service import create_realtime_notification
from apps.notifications.realtime import broadcast_event
from .models import (
    ApprovalRequestStatus,
    CounterOfferStatus,
    LoyaltyAccount,
    LoyaltyTier,
    LoyaltyTransaction,
    LoyaltyTransactionType,
    PartnerApiKey,
    PriceAlert,
    RFQCounterOffer,
    WalletApprovalRequest,
    WebhookSubscription,
)
from .serializers import (
    LoyaltyAccountSerializer,
    PartnerApiKeySerializer,
    PriceAlertSerializer,
    RFQCounterOfferSerializer,
    WalletApprovalRequestSerializer,
    WebhookSubscriptionSerializer,
)


def _is_admin(user) -> bool:
    return bool(user and user.is_authenticated and (user.is_superuser or user.role == UserRole.GENERAL_ADMIN))


BUSINESS_ROLES = {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}
NEGOTIATION_ROLES = {UserRole.BUYER, UserRole.SUPPLIER, UserRole.WHOLESALER}
MAX_ACTIVE_PRICE_ALERTS = 50
MAX_PENDING_WALLET_APPROVALS = 5
MAX_WALLET_APPROVAL_AMOUNT = Decimal("5000000.00")
MAX_LOYALTY_POINTS_PER_TX = 10000
MAX_PARTNER_API_KEYS = 5
MAX_WEBHOOK_SUBSCRIPTIONS = 10
WEBHOOK_TEST_COOLDOWN_SECONDS = 60
ALLOWED_WEBHOOK_TOPICS = {"orders", "shipments", "wallets", "analytics", "compliance"}


def _is_business_user(user) -> bool:
    return bool(user and user.is_authenticated and (user.role in BUSINESS_ROLES))


def _is_safe_webhook_url(raw_url: str) -> bool:
    try:
        parsed = urlparse(raw_url)
    except Exception:
        return False
    hostname = (parsed.hostname or "").strip().lower()
    if parsed.scheme != "https" or not hostname:
        return False
    # Bloque les noms d'hote qui revelent une cible interne meme avant DNS.
    if hostname in {"localhost", "metadata.google.internal", "metadata"} or hostname.endswith(".local") or hostname.endswith(".internal"):
        return False
    # Bloque les ports inhabituels (autoriser uniquement 443 + 80 fallback).
    if parsed.port not in (None, 80, 443):
        return False
    # Cas 1: hostname est deja une IP litterale -> validation directe.
    try:
        ip = ipaddress.ip_address(hostname)
        return not (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_reserved
            or ip.is_multicast
            or ip.is_unspecified
        )
    except ValueError:
        pass
    # Cas 2: hostname est un FQDN -> resolution DNS et verification de TOUTES
    # les IP retournees pour bloquer le DNS rebinding (evil.com -> 127.0.0.1
    # ou 169.254.169.254 metadata cloud AWS/GCP).
    try:
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        infos = socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM)
    except (socket.gaierror, socket.herror, UnicodeError, ValueError):
        return False
    if not infos:
        return False
    for _family, _type, _proto, _canon, sockaddr in infos:
        try:
            ip = ipaddress.ip_address(sockaddr[0])
        except (ValueError, IndexError):
            return False
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_reserved
            or ip.is_multicast
            or ip.is_unspecified
        ):
            return False
    return True


class PriceAlertViewSet(viewsets.ModelViewSet):
    serializer_class = PriceAlertSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = PriceAlert.objects.select_related("product", "user").all()

    def get_queryset(self):
        if _is_admin(self.request.user):
            return self.queryset
        return self.queryset.filter(user=self.request.user)

    def perform_create(self, serializer):
        user = self.request.user
        product = serializer.validated_data["product"]
        target_price = serializer.validated_data.get("target_price")
        if not _is_admin(user) and user.role != UserRole.BUYER:
            raise PermissionDenied("Les alertes prix sont reservees aux acheteurs.")
        if not product.is_active:
            raise ValidationError({"product": "Le produit doit etre actif."})
        if target_price is not None and target_price <= 0:
            raise ValidationError({"target_price": "Le prix cible doit etre superieur a 0."})
        active_count = PriceAlert.objects.filter(user=user, is_active=True).count()
        if active_count >= MAX_ACTIVE_PRICE_ALERTS:
            raise ValidationError({"detail": "Limite d'alertes actives atteinte."})
        serializer.save(user=user)

    @decorators.action(detail=False, methods=["post"])
    def evaluate(self, request):
        alerts = self.get_queryset().filter(is_active=True)
        triggered = []
        for alert in alerts:
            product = alert.product
            current_price = min(
                Decimal(product.price_for_min_qty),
                Decimal(product.price_for_max_qty),
            )
            in_stock = (product.available_qty or 1) > 0
            matches_price = alert.target_price is not None and current_price <= alert.target_price
            matches_stock = alert.notify_on_back_in_stock and in_stock
            if not (matches_price or matches_stock):
                continue
            alert.last_notified_price = current_price
            alert.triggered_at = timezone.now()
            alert.save(update_fields=["last_notified_price", "triggered_at"])
            create_realtime_notification(
                user=alert.user,
                title="Alerte produit",
                body=f"{product.title}: prix {current_price} FCFA.",
                payload={
                    "product_id": product.id,
                    "price": str(current_price),
                    "alert_id": alert.id,
                },
            )
            triggered.append(
                {
                    "alert_id": alert.id,
                    "product_id": product.id,
                    "price": str(current_price),
                }
            )
        return response.Response({"triggered": triggered}, status=status.HTTP_200_OK)


class RFQCounterOfferViewSet(viewsets.ModelViewSet):
    serializer_class = RFQCounterOfferSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = RFQCounterOffer.objects.select_related("rfq_offer", "rfq_offer__rfq", "creator").all()

    def get_queryset(self):
        user = self.request.user
        if _is_admin(user):
            return self.queryset
        return self.queryset.filter(
            Q(rfq_offer__rfq__buyer=user) | Q(rfq_offer__seller=user) | Q(creator=user)
        ).distinct()

    def perform_create(self, serializer):
        offer = serializer.validated_data["rfq_offer"]
        user = self.request.user
        participants = {offer.seller_id, offer.rfq.buyer_id}
        if not _is_admin(user) and user.role not in NEGOTIATION_ROLES:
            raise PermissionDenied("Role non autorise pour les contre-offres RFQ.")
        if user.id not in participants and not _is_admin(user):
            raise PermissionDenied("Seuls les participants RFQ peuvent negocier.")
        if offer.rfq.status != RFQStatus.OPEN and not _is_admin(user):
            raise ValidationError({"rfq_offer": "Le RFQ est ferme."})
        target_price = serializer.validated_data["target_price"]
        lead_time_days = serializer.validated_data.get("lead_time_days") or 0
        expires_at = serializer.validated_data.get("expires_at")
        if target_price <= 0:
            raise ValidationError({"target_price": "Le prix cible doit etre superieur a 0."})
        if lead_time_days < 1 or lead_time_days > 90:
            raise ValidationError({"lead_time_days": "Le delai doit etre entre 1 et 90 jours."})
        if expires_at and expires_at <= timezone.now():
            raise ValidationError({"expires_at": "La date d'expiration doit etre future."})
        if RFQCounterOffer.objects.filter(
            rfq_offer=offer,
            creator=user,
            status=CounterOfferStatus.PENDING,
        ).exists():
            raise ValidationError({"detail": "Une contre-offre en attente existe deja pour cette offre."})
        counter_offer = serializer.save(creator=user)
        broadcast_event(
            "analytics",
            "rfq_counter_offer_created",
            {"counter_offer_id": counter_offer.id, "rfq_offer_id": offer.id},
        )

    @decorators.action(detail=True, methods=["post"])
    def decide(self, request, pk=None):
        decision = str(request.data.get("decision") or "").strip().upper()
        if decision not in {CounterOfferStatus.ACCEPTED, CounterOfferStatus.REJECTED}:
            return response.Response({"detail": "Decision invalide."}, status=status.HTTP_400_BAD_REQUEST)
        counter_offer = self.get_object()
        offer = counter_offer.rfq_offer
        user = request.user
        participants = {offer.seller_id, offer.rfq.buyer_id}
        if user.id not in participants and not _is_admin(user):
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
        if counter_offer.creator_id == user.id and not _is_admin(user):
            return response.Response(
                {"detail": "Le createur ne peut pas decider sa propre contre-offre."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if counter_offer.status != CounterOfferStatus.PENDING:
            return response.Response({"detail": "Contre-offre deja traitee."}, status=status.HTTP_400_BAD_REQUEST)
        if counter_offer.expires_at and counter_offer.expires_at <= timezone.now():
            return response.Response({"detail": "Contre-offre expiree."}, status=status.HTTP_400_BAD_REQUEST)
        if offer.rfq.status != RFQStatus.OPEN and not _is_admin(user):
            return response.Response({"detail": "Le RFQ est ferme."}, status=status.HTTP_400_BAD_REQUEST)

        decided_at = timezone.now()
        counter_offer.status = decision
        counter_offer.decided_at = decided_at
        counter_offer.save(update_fields=["status", "decided_at"])

        if decision == CounterOfferStatus.ACCEPTED:
            offer.price = counter_offer.target_price
            offer.lead_time_days = counter_offer.lead_time_days
            offer.notes = (offer.notes or "") + f"\n[CounterOffer accepted #{counter_offer.id}]"
            offer.save(update_fields=["price", "lead_time_days", "notes"])
            RFQCounterOffer.objects.filter(
                rfq_offer=offer,
                status=CounterOfferStatus.PENDING,
            ).exclude(id=counter_offer.id).update(
                status=CounterOfferStatus.REJECTED,
                decided_at=decided_at,
            )

        broadcast_event(
            "analytics",
            "rfq_counter_offer_decided",
            {"counter_offer_id": counter_offer.id, "status": counter_offer.status},
        )
        return response.Response(RFQCounterOfferSerializer(counter_offer).data, status=status.HTTP_200_OK)


class WalletApprovalRequestViewSet(viewsets.ModelViewSet):
    serializer_class = WalletApprovalRequestSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = WalletApprovalRequest.objects.select_related("requester", "approver").all()

    def get_queryset(self):
        user = self.request.user
        if _is_admin(user):
            return self.queryset
        return self.queryset.filter(Q(requester=user) | Q(approver=user)).distinct()

    def perform_create(self, serializer):
        user = self.request.user
        amount = serializer.validated_data["amount"]
        reason = (serializer.validated_data.get("reason") or "").strip()
        if not _is_admin(user) and not _is_business_user(user):
            raise PermissionDenied("Demande d'approbation reservee aux comptes entreprise.")
        if amount <= 0:
            raise ValidationError({"amount": "Le montant doit etre superieur a 0."})
        if amount > MAX_WALLET_APPROVAL_AMOUNT:
            raise ValidationError({"amount": f"Le montant maximum autorise est {MAX_WALLET_APPROVAL_AMOUNT}."})
        if len(reason) < 8:
            raise ValidationError({"reason": "Le motif doit contenir au moins 8 caracteres."})
        pending_count = WalletApprovalRequest.objects.filter(
            requester=user,
            status=ApprovalRequestStatus.PENDING,
        ).count()
        if pending_count >= MAX_PENDING_WALLET_APPROVALS:
            raise ValidationError({"detail": "Trop de demandes en attente."})
        serializer.save(requester=user)

    @decorators.action(detail=True, methods=["post"])
    def decide(self, request, pk=None):
        decision = str(request.data.get("decision") or "").strip().upper()
        approval = self.get_object()
        if decision not in {ApprovalRequestStatus.APPROVED, ApprovalRequestStatus.REJECTED}:
            return response.Response({"detail": "Decision invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if approval.status != ApprovalRequestStatus.PENDING:
            return response.Response({"detail": "Demande deja traitee."}, status=status.HTTP_400_BAD_REQUEST)

        if not _is_admin(request.user):
            return response.Response(
                {"detail": "Seuls les admins peuvent approuver ou rejeter une demande."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if approval.requester_id == request.user.id:
            return response.Response(
                {"detail": "Le demandeur ne peut pas approuver sa propre demande."},
                status=status.HTTP_403_FORBIDDEN,
            )

        approval.status = decision
        approval.approver = request.user
        approval.decided_at = timezone.now()
        approval.save(update_fields=["status", "approver", "decided_at"])
        return response.Response(WalletApprovalRequestSerializer(approval).data, status=status.HTTP_200_OK)


class LoyaltyAccountView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def _get_target_user(self, request, *, from_query: bool):
        raw_user_id = request.query_params.get("user_id") if from_query else request.data.get("user_id")
        if raw_user_id in {None, ""}:
            return request.user
        if not _is_admin(request.user):
            raise PermissionDenied("La consultation d'un autre compte fidelite est reservee aux admins.")
        try:
            user_id = int(raw_user_id)
        except (TypeError, ValueError):
            raise ValidationError({"user_id": "Identifiant utilisateur invalide."})
        user_model = get_user_model()
        target = user_model.objects.filter(id=user_id).first()
        if not target:
            raise ValidationError({"user_id": "Utilisateur introuvable."})
        return target

    def get(self, request):
        target_user = self._get_target_user(request, from_query=True)
        account = LoyaltyAccount.objects.filter(user=target_user).first()
        if account is None:
            return response.Response({
                "points_balance": 0,
                "tier": "BRONZE",
                "updated_at": None,
                "transactions": [],
                "user_id": target_user.id,
            })
        payload = LoyaltyAccountSerializer(account).data
        payload["transactions"] = payload["transactions"][:20]
        payload["user_id"] = target_user.id
        return response.Response(payload)

    def post(self, request):
        target_user = self._get_target_user(request, from_query=False)
        action = str(request.data.get("action") or "").strip().upper()
        reason = str(request.data.get("reason") or "").strip()
        points_raw = request.data.get("points")
        try:
            points = int(points_raw)
        except (TypeError, ValueError):
            return response.Response({"detail": "Points invalides."}, status=status.HTTP_400_BAD_REQUEST)
        if points <= 0:
            return response.Response({"detail": "Points invalides."}, status=status.HTTP_400_BAD_REQUEST)
        if points > MAX_LOYALTY_POINTS_PER_TX:
            return response.Response({"detail": "Nombre de points trop eleve."}, status=status.HTTP_400_BAD_REQUEST)
        if not reason:
            return response.Response({"detail": "Le motif est obligatoire."}, status=status.HTTP_400_BAD_REQUEST)

        if action == LoyaltyTransactionType.EARN:
            if not _is_admin(request.user):
                return response.Response(
                    {"detail": "Le credit de points est reserve aux admins."},
                    status=status.HTTP_403_FORBIDDEN,
                )
            delta = points
        elif action == LoyaltyTransactionType.REDEEM:
            if target_user.id != request.user.id and not _is_admin(request.user):
                return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)
            delta = -points
        elif action == LoyaltyTransactionType.ADJUST:
            if not _is_admin(request.user):
                return response.Response({"detail": "Ajustement reserve aux admins."}, status=status.HTTP_403_FORBIDDEN)
            delta = points
        else:
            return response.Response({"detail": "Action de fidelite invalide."}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            account, _ = LoyaltyAccount.objects.select_for_update().get_or_create(user=target_user)
            if action == LoyaltyTransactionType.REDEEM and account.points_balance + delta < 0:
                return response.Response(
                    {"detail": "Solde de points insuffisant."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            account.points_balance += delta
            if account.points_balance >= 5000:
                account.tier = LoyaltyTier.GOLD
            elif account.points_balance >= 1500:
                account.tier = LoyaltyTier.SILVER
            else:
                account.tier = LoyaltyTier.BRONZE
            account.save(update_fields=["points_balance", "tier", "updated_at"])
            LoyaltyTransaction.objects.create(
                account=account,
                action_type=action,
                points=delta,
                reason=reason,
            )
        account.refresh_from_db()
        payload = LoyaltyAccountSerializer(account).data
        payload["transactions"] = payload["transactions"][:20]
        payload["user_id"] = target_user.id
        return response.Response(payload)


class PartnerApiKeyViewSet(viewsets.ModelViewSet):
    serializer_class = PartnerApiKeySerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = PartnerApiKey.objects.select_related("owner").all()

    def get_queryset(self):
        if _is_admin(self.request.user):
            return self.queryset
        return self.queryset.filter(owner=self.request.user)

    def create(self, request, *args, **kwargs):
        if not _is_admin(request.user):
            if not _is_business_user(request.user):
                raise PermissionDenied("Les cles API partenaires sont reservees aux comptes entreprise.")
            if not request.user.is_verified:
                raise PermissionDenied("Le compte doit etre verifie pour creer une cle API.")
            active_count = PartnerApiKey.objects.filter(owner=request.user, is_active=True).count()
            if active_count >= MAX_PARTNER_API_KEYS:
                raise ValidationError({"detail": "Limite de cles API actives atteinte."})
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        name = (serializer.validated_data["name"] or "").strip()
        if len(name) < 3:
            raise ValidationError({"name": "Le nom de la cle API doit contenir au moins 3 caracteres."})
        plain_key = f"mcm_{secrets.token_urlsafe(24)}"
        key_hash = hashlib.sha256(plain_key.encode("utf-8")).hexdigest()
        key_prefix = plain_key[:12]
        instance = PartnerApiKey.objects.create(
            owner=request.user,
            name=name,
            key_prefix=key_prefix,
            key_hash=key_hash,
            is_active=True,
        )
        payload = self.get_serializer(instance).data
        payload["plain_key"] = plain_key
        return response.Response(payload, status=status.HTTP_201_CREATED)

    def perform_update(self, serializer):
        name = (serializer.validated_data.get("name", serializer.instance.name) or "").strip()
        if len(name) < 3:
            raise ValidationError({"name": "Le nom de la cle API doit contenir au moins 3 caracteres."})
        is_active = serializer.validated_data.get("is_active", serializer.instance.is_active)
        if is_active and not serializer.instance.is_active and not _is_admin(self.request.user):
            count = PartnerApiKey.objects.filter(owner=self.request.user, is_active=True).count()
            if count >= MAX_PARTNER_API_KEYS:
                raise ValidationError({"detail": "Limite de cles API actives atteinte."})
        serializer.save(name=name)


class WebhookSubscriptionViewSet(viewsets.ModelViewSet):
    serializer_class = WebhookSubscriptionSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = WebhookSubscription.objects.select_related("owner").all()

    def get_queryset(self):
        if _is_admin(self.request.user):
            return self.queryset
        return self.queryset.filter(owner=self.request.user)

    def _validate_subscription_payload(self, *, topic: str, endpoint_url: str):
        topic_clean = (topic or "").strip().lower()
        endpoint_clean = (endpoint_url or "").strip()
        if topic_clean not in ALLOWED_WEBHOOK_TOPICS:
            raise ValidationError({"topic": f"Topic non supporte. Valeurs: {', '.join(sorted(ALLOWED_WEBHOOK_TOPICS))}."})
        if not _is_safe_webhook_url(endpoint_clean):
            raise ValidationError(
                {"endpoint_url": "URL webhook invalide ou non publique. HTTPS requis, localhost/interne interdit."}
            )
        return topic_clean, endpoint_clean

    def _validate_owner_access(self, user):
        if _is_admin(user):
            return
        if not _is_business_user(user):
            raise PermissionDenied("Webhook reserve aux comptes entreprise.")
        if not user.is_verified:
            raise PermissionDenied("Le compte doit etre verifie pour creer un webhook.")

    def perform_create(self, serializer):
        self._validate_owner_access(self.request.user)
        topic, endpoint_url = self._validate_subscription_payload(
            topic=serializer.validated_data.get("topic"),
            endpoint_url=serializer.validated_data.get("endpoint_url"),
        )
        if not _is_admin(self.request.user):
            count = WebhookSubscription.objects.filter(owner=self.request.user, is_active=True).count()
            if count >= MAX_WEBHOOK_SUBSCRIPTIONS:
                raise ValidationError({"detail": "Limite de webhooks actifs atteinte."})
        secret = (serializer.validated_data.get("secret") or "").strip() or secrets.token_hex(16)
        serializer.save(owner=self.request.user, topic=topic, endpoint_url=endpoint_url, secret=secret)

    def perform_update(self, serializer):
        self._validate_owner_access(self.request.user)
        topic, endpoint_url = self._validate_subscription_payload(
            topic=serializer.validated_data.get("topic", serializer.instance.topic),
            endpoint_url=serializer.validated_data.get("endpoint_url", serializer.instance.endpoint_url),
        )
        target_is_active = serializer.validated_data.get("is_active", serializer.instance.is_active)
        if target_is_active and not serializer.instance.is_active and not _is_admin(self.request.user):
            count = WebhookSubscription.objects.filter(owner=self.request.user, is_active=True).count()
            if count >= MAX_WEBHOOK_SUBSCRIPTIONS:
                raise ValidationError({"detail": "Limite de webhooks actifs atteinte."})
        serializer.save(topic=topic, endpoint_url=endpoint_url)

    @decorators.action(detail=True, methods=["post"], throttle_classes=[ScopedRateThrottle])
    def send_test(self, request, pk=None):
        # Throttle scope dynamique pour cette action.
        self.throttle_scope = "webhook_test"
        sub = self.get_object()
        if not sub.is_active:
            return response.Response({"detail": "Webhook inactif."}, status=status.HTTP_400_BAD_REQUEST)
        if not _is_safe_webhook_url(sub.endpoint_url):
            return response.Response({"detail": "Endpoint webhook non autorise."}, status=status.HTTP_400_BAD_REQUEST)
        now = timezone.now()
        if sub.last_delivered_at and (now - sub.last_delivered_at).total_seconds() < WEBHOOK_TEST_COOLDOWN_SECONDS:
            retry = WEBHOOK_TEST_COOLDOWN_SECONDS - int((now - sub.last_delivered_at).total_seconds())
            return response.Response(
                {"detail": "Veuillez patienter avant un nouveau test.", "retry_after_seconds": max(retry, 1)},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )
        payload = {
            "topic": sub.topic,
            "type": "test_event",
            "sent_at": now.isoformat(),
            "data": {"message": "Render webhook test"},
        }
        payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        signature = hashlib.sha256(f"{sub.secret}:{payload_json}".encode("utf-8")).hexdigest()
        req = urllib.request.Request(
            sub.endpoint_url,
            data=payload_json.encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "X-MarcheCM-Signature": signature,
            },
            method="POST",
        )
        try:
            # H4 — SSRF redirect blocking: never follow HTTP redirects.
            # A legitimate endpoint that redirects to 169.254.169.254 or a
            # private address would bypass _is_safe_webhook_url() validation.
            # Use a no-redirect opener so the caller's URL is the final destination.
            class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
                def redirect_request(self, *args, **kwargs):
                    raise urllib.error.HTTPError(
                        args[0] if args else "",
                        0,
                        "Redirects interdits pour les webhooks (SSRF protection)",
                        {},
                        None,
                    )

            _opener = urllib.request.build_opener(_NoRedirectHandler)
            with _opener.open(req, timeout=6) as resp:
                status_code = getattr(resp, "status", 200)
                # H4 — Response size limit: read at most 4 KB to prevent
                # memory exhaustion via a slow/large response body.
                resp.read(4096)
            sub.last_delivery_status = f"HTTP_{status_code}"
            sub.last_delivered_at = timezone.now()
            sub.save(update_fields=["last_delivery_status", "last_delivered_at"])
            return response.Response({"detail": "Webhook test envoye.", "status": sub.last_delivery_status})
        except Exception as exc:
            sub.last_delivery_status = f"ERROR_{type(exc).__name__}"
            sub.last_delivered_at = timezone.now()
            sub.save(update_fields=["last_delivery_status", "last_delivered_at"])
            return response.Response(
                {"detail": "Echec envoi webhook test.", "error": type(exc).__name__},
                status=status.HTTP_502_BAD_GATEWAY,
            )


class EscrowSplitPreviewView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        order_id = request.query_params.get("order_id")
        if not order_id:
            return response.Response({"detail": "order_id requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            order = Order.objects.select_related("shipment").get(id=int(order_id))
        except (ValueError, Order.DoesNotExist):
            return response.Response({"detail": "Commande introuvable."}, status=status.HTTP_404_NOT_FOUND)
        if not _is_admin(request.user) and request.user.id not in {
            order.buyer_id,
            order.seller_id,
            order.preferred_transit_agent_id,
        }:
            return response.Response({"detail": "Acces non autorise."}, status=status.HTTP_403_FORBIDDEN)
        if order.status == OrderStatus.CANCELLED:
            return response.Response({"detail": "Commande annulee: repartition indisponible."}, status=status.HTTP_400_BAD_REQUEST)
        if Decimal(order.total_price) <= 0:
            return response.Response({"detail": "Montant de commande invalide."}, status=status.HTTP_400_BAD_REQUEST)

        total = Decimal(order.total_price)
        shipping_fee = Decimal(getattr(getattr(order, "shipment", None), "shipping_fee", 0) or 0)
        platform_pct_raw = request.query_params.get("platform_pct", "0.05")
        try:
            platform_pct = Decimal(platform_pct_raw)
        except Exception:
            return response.Response({"detail": "platform_pct invalide."}, status=status.HTTP_400_BAD_REQUEST)
        if platform_pct < 0 or platform_pct > Decimal("0.30"):
            return response.Response({"detail": "platform_pct doit etre entre 0 et 0.30."}, status=status.HTTP_400_BAD_REQUEST)
        platform_share = (total * platform_pct).quantize(Decimal("1.00"))
        transit_share = min(shipping_fee, (total * Decimal("0.25")).quantize(Decimal("1.00")))
        seller_share = (total - platform_share - transit_share).quantize(Decimal("1.00"))
        if seller_share < 0:
            seller_share = Decimal("0.00")
        return response.Response(
            {
                "order_id": order.id,
                "total_price": str(total),
                "escrow_status": order.escrow_status,
                "is_escrow_released": order.escrow_status == EscrowStatus.RELEASED,
                "distribution": {
                    "seller": str(seller_share),
                    "transit_agent": str(transit_share),
                    "platform": str(platform_share),
                },
            }
        )


class RFQCompareView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        rfq_id = request.query_params.get("rfq_id")
        if not rfq_id:
            return response.Response({"detail": "rfq_id requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            rfq = RequestForQuotation.objects.get(id=int(rfq_id))
        except (ValueError, RequestForQuotation.DoesNotExist):
            return response.Response({"detail": "RFQ introuvable."}, status=status.HTTP_404_NOT_FOUND)
        if not _is_admin(request.user) and request.user.id not in {rfq.buyer_id}:
            return response.Response({"detail": "Acces reserve a l'acheteur du RFQ."}, status=status.HTTP_403_FORBIDDEN)
        if rfq.status != RFQStatus.OPEN and not _is_admin(request.user):
            return response.Response({"detail": "Le RFQ est ferme."}, status=status.HTTP_400_BAD_REQUEST)

        offers = RFQOffer.objects.select_related("seller").filter(rfq=rfq)
        if not offers.exists():
            return response.Response({"rfq_id": rfq.id, "offers": [], "recommended_offer_id": None})

        target_price = rfq.target_price if rfq.target_price else None
        ranking = []
        for offer in offers:
            price = Decimal(offer.price)
            if target_price and target_price > 0:
                variance = abs(price - Decimal(target_price)) / Decimal(target_price)
                price_score = max(Decimal("0"), Decimal("100") - (variance * Decimal("100")))
            else:
                price_score = max(Decimal("0"), Decimal("100") - (price / Decimal("1000")))
            lead_score = max(Decimal("0"), Decimal("100") - (Decimal(offer.lead_time_days) * Decimal("8")))
            trust_score = min(Decimal("100"), Decimal(offer.seller.trust_score or 0) * Decimal("20"))
            total_score = (price_score * Decimal("0.55")) + (lead_score * Decimal("0.30")) + (trust_score * Decimal("0.15"))
            ranking.append(
                {
                    "offer_id": offer.id,
                    "seller_id": offer.seller_id,
                    "price": str(offer.price),
                    "lead_time_days": offer.lead_time_days,
                    "score": round(float(total_score), 2),
                }
            )
        ranking.sort(key=lambda row: row["score"], reverse=True)
        return response.Response(
            {
                "rfq_id": rfq.id,
                "offers": ranking,
                "recommended_offer_id": ranking[0]["offer_id"] if ranking else None,
            }
        )


class ShipmentTimelineView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        shipment_id = request.query_params.get("shipment_id")
        if not shipment_id:
            return response.Response({"detail": "shipment_id requis."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            shipment = Shipment.objects.select_related("buyer", "seller", "transit_agent").get(id=int(shipment_id))
        except (ValueError, Shipment.DoesNotExist):
            return response.Response({"detail": "Expedition introuvable."}, status=status.HTTP_404_NOT_FOUND)
        if not _is_admin(request.user) and request.user.id not in {
            shipment.buyer_id,
            shipment.seller_id,
            shipment.transit_agent_id,
        }:
            return response.Response({"detail": "Acces non autorise."}, status=status.HTTP_403_FORBIDDEN)

        events = ShipmentEvent.objects.filter(shipment=shipment).order_by("created_at")
        statuses_done = {event.status for event in events}
        statuses_done.add(shipment.status)
        canonical = [
            "PICKUP_PENDING",
            "IN_TRANSIT",
            "AT_CUSTOMS",
            "OUT_FOR_DELIVERY",
            "DELIVERED",
        ]
        timeline = [
            {"status": code, "done": code in statuses_done}
            for code in canonical
        ]

        eta = shipment.expected_delivery_at
        if not eta and shipment.status != "DELIVERED":
            offsets = {
                "PICKUP_PENDING": 4,
                "IN_TRANSIT": 3,
                "AT_CUSTOMS": 2,
                "OUT_FOR_DELIVERY": 1,
            }
            eta = timezone.now() + timedelta(days=offsets.get(shipment.status, 2))

        return response.Response(
            {
                "shipment_id": shipment.id,
                "current_status": shipment.status,
                "timeline": timeline,
                "eta": eta.isoformat() if eta else "",
                "events": [
                    {
                        "status": event.status,
                        "note": event.note,
                        "created_at": event.created_at.isoformat(),
                    }
                    for event in events
                ],
            }
        )


class DisputeEscalationView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, dispute_id: int):
        dispute = ShipmentDispute.objects.select_related("shipment").filter(id=dispute_id).first()
        if not dispute:
            return response.Response({"detail": "Litige introuvable."}, status=status.HTTP_404_NOT_FOUND)
        allowed_ids = {
            dispute.shipment.buyer_id,
            dispute.shipment.seller_id,
            dispute.shipment.transit_agent_id,
        }
        if not _is_admin(request.user) and request.user.id not in allowed_ids:
            return response.Response({"detail": "Action non autorisee."}, status=status.HTTP_403_FORBIDDEN)

        note = str(request.data.get("note") or "").strip()
        if dispute.status == DisputeStatus.RESOLVED:
            return response.Response({"detail": "Le litige est deja resolu."}, status=status.HTTP_400_BAD_REQUEST)
        if dispute.status == DisputeStatus.UNDER_REVIEW and dispute.sla_due_at and dispute.sla_due_at > timezone.now():
            return response.Response({"detail": "Le litige est deja en escalation."}, status=status.HTTP_400_BAD_REQUEST)
        if len(note) < 8:
            return response.Response({"detail": "Ajoutez une note d'au moins 8 caracteres."}, status=status.HTTP_400_BAD_REQUEST)
        dispute.status = DisputeStatus.UNDER_REVIEW
        dispute.sla_due_at = timezone.now() + timedelta(hours=24)
        dispute.resolution_note = ((dispute.resolution_note or "").strip() + f"\n[Escalated] {note}").strip()
        dispute.save(update_fields=["status", "sla_due_at", "resolution_note", "updated_at"])
        write_audit_log(
            actor=request.user,
            action="Escalade litige",
            action_key="logistics.dispute.open",
            metadata={"dispute_id": dispute.id},
        )
        broadcast_event("logistics", "dispute_escalated", {"dispute_id": dispute.id})
        return response.Response({"detail": "Litige escalade.", "dispute_id": dispute.id, "status": dispute.status})


class OnboardingChecklistView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        steps = [
            {"key": "email_verified", "label": "Email verifie", "done": bool(user.is_verified)},
            {"key": "country_code", "label": "Pays renseigne", "done": bool((user.country_code or "").strip())},
            {"key": "city", "label": "Ville renseignee", "done": bool((user.city or "").strip())},
            {"key": "wallet_pin", "label": "PIN wallet configure", "done": bool((user.wallet_pin_hash or "").strip())},
        ]
        if user.role in {UserRole.SUPPLIER, UserRole.WHOLESALER, UserRole.TRANSIT_AGENT}:
            steps.append(
                {
                    "key": "compliance",
                    "label": "Certifications soumises",
                    "done": user.compliance_documents.exists(),
                }
            )
        if user.role == UserRole.TRANSIT_AGENT:
            steps.append(
                {
                    "key": "transport_profile",
                    "label": "Profil transport complete",
                    "done": hasattr(user, "transport_profile"),
                }
            )
        done = sum(1 for step in steps if step["done"])
        total = len(steps)
        return response.Response(
            {
                "steps": steps,
                "progress_percent": int((done * 100) / total) if total else 0,
            }
        )


class SellerDashboardInsightsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role not in {UserRole.SUPPLIER, UserRole.WHOLESALER} and not _is_admin(user):
            return response.Response({"detail": "Reserve aux vendeurs."}, status=status.HTTP_403_FORBIDDEN)

        seller = user
        if _is_admin(user):
            seller_id = request.query_params.get("seller_id")
            if seller_id:
                from apps.accounts.models import User

                try:
                    seller_id_int = int(seller_id)
                except (TypeError, ValueError):
                    return response.Response({"detail": "seller_id invalide."}, status=status.HTTP_400_BAD_REQUEST)
                seller = User.objects.filter(id=seller_id_int).first()
                if not seller:
                    return response.Response({"detail": "Vendeur introuvable."}, status=status.HTTP_404_NOT_FOUND)
                if seller.role not in {UserRole.SUPPLIER, UserRole.WHOLESALER}:
                    return response.Response({"detail": "seller_id doit cibler un vendeur."}, status=status.HTTP_400_BAD_REQUEST)
        orders = seller.seller_orders.all()
        completed_orders = orders.filter(status="COMPLETED")
        revenue = completed_orders.aggregate(total=Sum("total_price"))["total"] or Decimal("0")
        repeat_buyers = (
            completed_orders.values("buyer_id").annotate(cnt=Count("id")).filter(cnt__gt=1).count()
        )
        top_products = (
            completed_orders.values("product_id", "product__title")
            .annotate(total=Count("id"))
            .order_by("-total")[:5]
        )
        return response.Response(
            {
                "seller_id": seller.id,
                "products_count": seller.products.count(),
                "orders_total": orders.count(),
                "orders_completed": completed_orders.count(),
                "revenue_completed": str(revenue),
                "repeat_buyers": repeat_buyers,
                "top_products": [
                    {
                        "product_id": row["product_id"],
                        "title": row["product__title"],
                        "orders": row["total"],
                    }
                    for row in top_products
                ],
            }
        )


class RecommendationReasonsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role != UserRole.BUYER and not _is_admin(user):
            return response.Response({"products": []})

        profile = BuyerPreferenceProfile.objects.filter(user=user).first()
        interactions = {
            row["product_id"]: row["view_count"]
            for row in BuyerProductInteraction.objects.filter(user=user).values("product_id", "view_count")
        }
        locality_weights = dict(profile.locality_weights if profile else {})
        keyword_weights = dict(profile.keyword_weights if profile else {})

        products = Product.objects.filter(is_active=True).select_related("seller")[:80]
        scored = []
        for product in products:
            reasons = []
            score = 0.0
            views = interactions.get(product.id, 0)
            if views > 0:
                score += views * 5
                reasons.append(f"Deja consulte {views} fois")
            locality_key = (product.seller.country_code or "").upper()
            locality_score = float(locality_weights.get(locality_key, 0))
            if locality_score > 0:
                score += locality_score * 2.5
                reasons.append(f"Localite preferee ({locality_key})")
            for token in ((product.title or "") + " " + (product.brand or "")).lower().split():
                kw_score = float(keyword_weights.get(token, 0))
                if kw_score > 0:
                    score += kw_score * 0.6
                    if len(reasons) < 4:
                        reasons.append(f"Mot-cle pertinent: {token}")
            trust = float(product.seller.trust_score or 0)
            score += trust * 0.25
            if trust >= 4:
                reasons.append("Vendeur fiable")
            scored.append(
                {
                    "product_id": product.id,
                    "title": product.title,
                    "score": round(score, 2),
                    "reasons": reasons[:4],
                }
            )
        scored.sort(key=lambda row: row["score"], reverse=True)
        return response.Response({"products": scored[:15]})


class SmartNotificationsRunView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if not _is_admin(request.user):
            return response.Response(
                {"detail": "Action reservee aux administrateurs."},
                status=status.HTTP_403_FORBIDDEN,
            )

        now = timezone.now()
        late_shipments = Shipment.objects.filter(
            expected_delivery_at__isnull=False,
            expected_delivery_at__lt=now,
        ).exclude(status="DELIVERED")

        late_alerts = 0
        for shipment in late_shipments.select_related("buyer", "seller", "transit_agent"):
            recipients = [shipment.buyer, shipment.seller, shipment.transit_agent]
            for user in recipients:
                if not user:
                    continue
                try:
                    create_realtime_notification(
                        user=user,
                        title="Alerte livraison en retard",
                        body=f"Expedition #{shipment.id} en retard. Verifiez le statut.",
                        payload={"shipment_id": shipment.id, "kind": "shipment_late"},
                    )
                    late_alerts += 1
                except Exception:
                    continue

        pending_tx = WalletTransaction.objects.filter(
            status=TransactionStatus.PENDING,
            created_at__lt=now - timedelta(minutes=20),
        ).select_related("wallet__owner")
        pending_alerts = 0
        for tx in pending_tx:
            try:
                create_realtime_notification(
                    user=tx.wallet.owner,
                    title="Paiement en attente",
                    body=f"Transaction {tx.external_transaction_id or tx.id} toujours en attente.",
                    payload={"transaction_id": tx.external_transaction_id, "kind": "wallet_pending"},
                )
                pending_alerts += 1
            except Exception:
                continue

        write_audit_log(
            actor=request.user,
            action="Execution notifications intelligentes",
            action_key="admin.dashboard.view",
            metadata={"late_alerts": late_alerts, "pending_alerts": pending_alerts},
        )
        return response.Response(
            {
                "detail": "Notifications intelligentes traitees.",
                "late_alerts": late_alerts,
                "pending_alerts": pending_alerts,
            },
            status=status.HTTP_200_OK,
        )
