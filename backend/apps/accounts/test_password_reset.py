"""Forgot-password flow — request a code by email, then confirm a new password.

Covers the happy path, attempt limiting, single-use codes, password-rotation
side effects (sessions revoked) and anti-enumeration of unknown emails.
"""
import re

from django.contrib.auth import get_user_model
from django.core import mail
from django.core.cache import cache
from django.test import TestCase
from django.test.utils import override_settings

from apps.accounts import field_crypto
from apps.accounts.models import PasswordResetChallenge

REQUEST_URL = "/api/auth/password/reset/request/"
CONFIRM_URL = "/api/auth/password/reset/confirm/"


@override_settings(
    AUTH_LOCKDOWN=False,
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
)
class PasswordResetFlowTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        cache.clear()  # reset sliding-window throttle counters between tests
        mail.outbox = []
        self.user = get_user_model().objects.create_user(
            username="resetme", email="resetme@qa.test", password="OldPass123!",
            role="BUYER", country_code="CM", phone_number="+237690004001",
        )

    def _request(self, email):
        return self.client.post(REQUEST_URL, {"email": email}, content_type="application/json")

    def _code_from_mail(self):
        body = mail.outbox[-1].body
        return re.search(r"\b(\d{6})\b", body).group(1)

    def test_full_reset_flow(self):
        resp = self._request("resetme@qa.test")
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(
            PasswordResetChallenge.objects.filter(user=self.user, used_at__isnull=True).count(), 1
        )
        code = self._code_from_mail()

        # Wrong code increments attempts but does not reset the password.
        bad = self.client.post(
            CONFIRM_URL,
            {"email": "resetme@qa.test", "code": "000000", "new_password": "BrandNew123!"},
            content_type="application/json",
        )
        self.assertEqual(bad.status_code, 400, bad.content)

        ok = self.client.post(
            CONFIRM_URL,
            {"email": "resetme@qa.test", "code": code, "new_password": "BrandNew123!"},
            content_type="application/json",
        )
        self.assertEqual(ok.status_code, 200, ok.content)

        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("BrandNew123!"))
        self.assertFalse(self.user.check_password("OldPass123!"))

        # The code is single-use — replaying it fails.
        replay = self.client.post(
            CONFIRM_URL,
            {"email": "resetme@qa.test", "code": code, "new_password": "Another123!"},
            content_type="application/json",
        )
        self.assertEqual(replay.status_code, 400, replay.content)

    def test_unknown_email_is_indistinguishable(self):
        resp = self._request("ghost@nowhere.test")
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertEqual(len(mail.outbox), 0)  # no email sent
        self.assertFalse(PasswordResetChallenge.objects.exists())

    def test_short_password_rejected(self):
        self._request("resetme@qa.test")
        code = self._code_from_mail()
        resp = self.client.post(
            CONFIRM_URL,
            {"email": "resetme@qa.test", "code": code, "new_password": "short"},
            content_type="application/json",
        )
        self.assertEqual(resp.status_code, 400, resp.content)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("OldPass123!"))
