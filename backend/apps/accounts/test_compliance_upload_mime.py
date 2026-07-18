"""Compliance / KYC upload Content-Type contract.

Regression for the driver-KYC blocker: mobile clients used to upload files with
no per-part Content-Type (dio/http default `application/octet-stream`), which
the UP-001 hardening rejects — so KYC submission always failed.

The fix is client-side (declare a concrete image MIME). These tests lock both
ends of the contract:
  * a proper image MIME is accepted (201);
  * octet-stream is still refused (400) — the security control is preserved.
"""
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts import field_crypto

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


@override_settings(
    AUTH_LOCKDOWN=False,
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class ComplianceUploadMimeTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def _agent_token(self):
        user = get_user_model().objects.create_user(
            username="driver_mime", email="driver_mime@qa.test", password="x",
            role="TRANSIT_AGENT", country_code="CM", phone_number="+237690003001",
        )
        return str(RefreshToken.for_user(user).access_token)

    def _post(self, token, content_type):
        upload = SimpleUploadedFile("cni.png", PNG_BYTES, content_type=content_type)
        return self.client.post(
            "/api/compliance-documents/",
            {"doc_type": "DRIVER_LICENSE", "file": upload},
            HTTP_AUTHORIZATION=f"Bearer {token}",
        )

    def test_proper_image_mime_accepted(self):
        resp = self._post(self._agent_token(), "image/png")
        self.assertEqual(resp.status_code, 201, resp.content)
        self.assertEqual(resp.json().get("doc_type"), "DRIVER_LICENSE")

    def test_octet_stream_rejected(self):
        resp = self._post(self._agent_token(), "application/octet-stream")
        self.assertEqual(resp.status_code, 400, resp.content)
