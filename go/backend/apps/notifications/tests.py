from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from .models import Notification


class NotificationApiTests(APITestCase):
    def setUp(self):
        user_model = get_user_model()
        self.user = user_model.objects.create_user(
            username="notif_user",
            email="notif_user@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )
        self.other = user_model.objects.create_user(
            username="notif_other",
            email="notif_other@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )
        self.user_notif = Notification.objects.create(
            user=self.user,
            title="Notification test",
            body="Body test",
            is_read=False,
        )
        Notification.objects.create(
            user=self.other,
            title="Notification autre",
            body="Body autre",
            is_read=False,
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def _rows(self, payload):
        if isinstance(payload, dict) and "results" in payload:
            return payload["results"]
        return payload

    def test_list_returns_only_user_notifications(self):
        self._auth_as(self.user)
        res = self.client.get(reverse("notification-list"))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        rows = self._rows(res.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.user_notif.id)

    def test_mark_read_marks_notification(self):
        self._auth_as(self.user)
        res = self.client.post(reverse("notification-mark-read", args=[self.user_notif.id]), {}, format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.user_notif.refresh_from_db()
        self.assertTrue(self.user_notif.is_read)

    def test_mark_all_read_marks_only_current_user(self):
        self._auth_as(self.user)
        res = self.client.post(reverse("notification-mark-all-read"), {}, format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.user_notif.refresh_from_db()
        self.assertTrue(self.user_notif.is_read)
