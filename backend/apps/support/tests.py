from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from .models import SupportTicket, TicketStatus


class SupportTicketTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.admin = user_model.objects.create_user(
            username="admin_support",
            email="admin_support@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_active=True,
        )
        self.buyer = user_model.objects.create_user(
            username="buyer_support",
            email="buyer_support@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def test_buyer_can_create_ticket(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("support-ticket-list"),
            {
                "subject": "Probleme commande",
                "description": "Je ne vois pas le statut de livraison sur ma commande.",
                "priority": "HIGH",
                "category": "ORDERS",
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        ticket = SupportTicket.objects.get(id=res.data["id"])
        self.assertEqual(ticket.created_by_id, self.buyer.id)
        self.assertEqual(ticket.messages.count(), 1)

    def test_non_admin_cannot_assign_ticket(self):
        ticket = SupportTicket.objects.create(
            created_by=self.buyer,
            subject="Erreur wallet",
            description="Le debit ne passe pas.",
        )
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("support-ticket-assign", args=[ticket.id]),
            {"assigned_to": self.admin.id},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_can_assign_and_buyer_can_close(self):
        ticket = SupportTicket.objects.create(
            created_by=self.buyer,
            subject="Erreur wallet",
            description="Le debit ne passe pas.",
        )

        self._auth_as(self.admin)
        assign = self.client.post(
            reverse("support-ticket-assign", args=[ticket.id]),
            {"assigned_to": self.admin.id},
            format="json",
        )
        self.assertEqual(assign.status_code, status.HTTP_200_OK)

        self._auth_as(self.buyer)
        close = self.client.post(reverse("support-ticket-close", args=[ticket.id]), {}, format="json")
        self.assertEqual(close.status_code, status.HTTP_200_OK)
        ticket.refresh_from_db()
        self.assertEqual(ticket.status, TicketStatus.CLOSED)
