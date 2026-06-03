"""M-6 — Admin user suspension: suspend / unsuspend, JWT revocation, audit, RBAC.

Guarantees:
  * an admin can suspend a non-admin user (is_suspended + is_active=False,
    who/when/why recorded);
  * a suspended user cannot log in (403) and an already-issued access token is
    rejected (JWT revocation via is_active + refresh blacklist);
  * unsuspend restores access;
  * every action writes an audit row;
  * RBAC: non-admins cannot suspend; an admin cannot suspend themselves or
    another admin; suspending a missing user is 404.
"""
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken

from apps.accounts import field_crypto
from apps.accounts.models import AuditLog


@override_settings(
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class UserSuspensionTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.admin = u.objects.create_user(
            username="m6_admin", email="m6_admin@test.local", password="TestPassword123!",
            role="GENERAL_ADMIN", is_superuser=True, is_staff=True, is_verified=True,
            country_code="CM", phone_number="+237690001201")
        self.admin2 = u.objects.create_user(
            username="m6_admin2", email="m6_admin2@test.local", password="TestPassword123!",
            role="GENERAL_ADMIN", is_verified=True, country_code="CM", phone_number="+237690001202")
        self.buyer = u.objects.create_user(
            username="m6_buyer", email="m6_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, country_code="CM", phone_number="+237690001203")
        self.other = u.objects.create_user(
            username="m6_other", email="m6_other@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, country_code="CM", phone_number="+237690001204")
        self.admin_api = APIClient(); self.admin_api.force_authenticate(user=self.admin)

    def test_admin_can_suspend_user(self):
        r = self.admin_api.post(f"/api/users/{self.buyer.id}/suspend/", {"reason": "Fraude"}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.buyer.refresh_from_db()
        self.assertTrue(self.buyer.is_suspended)
        self.assertFalse(self.buyer.is_active)
        self.assertEqual(self.buyer.suspension_reason, "Fraude")
        self.assertEqual(self.buyer.suspended_by_id, self.admin.id)
        self.assertIsNotNone(self.buyer.suspended_at)
        self.assertTrue(AuditLog.objects.filter(action_key="admin.users.suspend").exists())

    def test_suspended_user_cannot_login(self):
        self.buyer.suspend(by=self.admin, reason="x")
        anon = APIClient()
        r = anon.post("/api/auth/login/",
                      {"email": "m6_buyer@test.local", "password": "TestPassword123!"},
                      format="json")
        self.assertIn(r.status_code, (401, 403), r.content)
        self.assertIn("suspendu", str(r.content, "utf-8").lower())

    def test_existing_access_token_rejected_after_suspension(self):
        token = str(AccessToken.for_user(self.buyer))
        authed = APIClient()
        authed.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        before = authed.get("/api/auth/me/")
        self.assertEqual(before.status_code, 200, "token should work before suspension")
        self.buyer.suspend(by=self.admin, reason="x")
        after = authed.get("/api/auth/me/")
        self.assertIn(after.status_code, (401, 403), "token must be rejected after suspension")

    def test_unsuspend_restores_access(self):
        self.buyer.suspend(by=self.admin, reason="x")
        r = self.admin_api.post(f"/api/users/{self.buyer.id}/unsuspend/", {}, format="json")
        self.assertEqual(r.status_code, 200, r.content)
        self.buyer.refresh_from_db()
        self.assertFalse(self.buyer.is_suspended)
        self.assertTrue(self.buyer.is_active)
        anon = APIClient()
        login = anon.post("/api/auth/login/",
                          {"email": "m6_buyer@test.local", "password": "TestPassword123!"},
                          format="json")
        self.assertEqual(login.status_code, 200, login.content)

    def test_non_admin_cannot_suspend(self):
        buyer_api = APIClient(); buyer_api.force_authenticate(user=self.buyer)
        r = buyer_api.post(f"/api/users/{self.other.id}/suspend/", {"reason": "hack"}, format="json")
        self.assertIn(r.status_code, (403, 404), r.content)
        self.other.refresh_from_db()
        self.assertFalse(self.other.is_suspended)

    def test_admin_cannot_suspend_self(self):
        r = self.admin_api.post(f"/api/users/{self.admin.id}/suspend/", {"reason": "oops"}, format="json")
        self.assertEqual(r.status_code, 400, r.content)

    def test_admin_cannot_suspend_another_admin(self):
        r = self.admin_api.post(f"/api/users/{self.admin2.id}/suspend/", {"reason": "coup"}, format="json")
        self.assertEqual(r.status_code, 400, r.content)
        self.admin2.refresh_from_db()
        self.assertFalse(self.admin2.is_suspended)

    def test_suspend_missing_user_returns_404(self):
        r = self.admin_api.post("/api/users/999999/suspend/", {"reason": "x"}, format="json")
        self.assertEqual(r.status_code, 404, r.content)
