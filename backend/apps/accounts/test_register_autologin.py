"""Auto-login on registration — the three public register endpoints must return
an authenticated session payload ``{access, refresh, user}`` so the mobile apps
log the user in immediately (no separate login round-trip).

Covers: buyer (/api/auth/register/), seller (/api/auth/register/seller/) and
driver (/api/auth/register/driver/). The issued access token must authenticate
against /api/auth/me/.
"""
from unittest import mock

from django.test import TestCase
from django.test.utils import override_settings

from apps.accounts import field_crypto

APPLY_ASYNC = "apps.accounts.tasks.user_geocode_task.apply_async"
FAST_HASHER = ["django.contrib.auth.hashers.MD5PasswordHasher"]


@override_settings(
    AUTH_LOCKDOWN=False,
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    PASSWORD_HASHERS=FAST_HASHER,
)
class RegisterAutoLoginTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def _assert_session_payload(self, resp, expected_role):
        self.assertEqual(resp.status_code, 201, resp.content)
        data = resp.json()
        self.assertTrue(data.get("access"), "missing access token")
        self.assertTrue(data.get("refresh"), "missing refresh token")
        self.assertIsInstance(data.get("user"), dict, "missing user object")
        self.assertEqual(data["user"].get("role"), expected_role)
        self.assertTrue(data["user"].get("id"), "missing user id")
        # The issued access token must authenticate immediately.
        me = self.client.get(
            "/api/auth/me/",
            HTTP_AUTHORIZATION=f"Bearer {data['access']}",
        )
        self.assertEqual(me.status_code, 200, me.content)
        self.assertEqual(me.json().get("id"), data["user"]["id"])

    def test_buyer_register_auto_login(self):
        with mock.patch(APPLY_ASYNC):
            resp = self.client.post(
                "/api/auth/register/",
                {
                    "name": "Awa Buyer", "email": "buyer.auto@qa.test",
                    "phone_number": "+237690001001", "password": "ChangeMe123!",
                    "country_code": "CM", "city": "Douala",
                },
                content_type="application/json",
            )
        self._assert_session_payload(resp, "BUYER")

    def test_seller_register_auto_login(self):
        with mock.patch(APPLY_ASYNC):
            resp = self.client.post(
                "/api/auth/register/seller/",
                {
                    "name": "Sara Seller", "email": "seller.auto@qa.test",
                    "phone_number": "+237690001002", "password": "ChangeMe123!",
                    "role": "SUPPLIER", "country_code": "CM", "city": "Douala",
                    "company_name": "Tropical Foods",
                },
                content_type="application/json",
            )
        self._assert_session_payload(resp, "SUPPLIER")

    def test_driver_register_auto_login(self):
        with mock.patch(APPLY_ASYNC):
            resp = self.client.post(
                "/api/auth/register/driver/",
                {
                    "name": "Dan Driver", "email": "driver.auto@qa.test",
                    "phone_number": "+237690001003", "password": "ChangeMe123!",
                    "country_code": "CM", "vehicle_type": "MOTO",
                },
                content_type="application/json",
            )
        self._assert_session_payload(resp, "TRANSIT_AGENT")
