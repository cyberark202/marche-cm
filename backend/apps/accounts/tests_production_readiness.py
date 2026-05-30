"""
Production-readiness suite.

Two layers, both runnable before a release:

  1. PreflightCommandTests — exercises the `preflight` management command (the
     infra/config gate) so the gate itself can't silently rot.
  2. CriticalBusinessGate* — asserts the business invariants that MUST hold in
     production: buyer KYC submission, admin RBAC, and the step-up gate on
     wallet reconciliation.

Run: `python manage.py test apps.accounts.tests_production_readiness`
"""

import io
from io import StringIO

from PIL import Image
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import ComplianceDocument

User = get_user_model()

# Minimal valid JPEG header so upload_security magic-byte validation passes
# (the `file` field is a plain FileField — no full image decode required).
FAKE_JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 32

def _jpeg(name="doc.jpg"):
    return SimpleUploadedFile(name, FAKE_JPEG, content_type="image/jpeg")


def _png(name="signature.png"):
    # The `signature` field is a DRF ImageField → requires a genuinely decodable
    # image (matches the real PNG exported by the app). Generate one with Pillow.
    buf = io.BytesIO()
    Image.new("RGB", (8, 8), (255, 255, 255)).save(buf, format="PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


# ── 1. Pre-flight gate ─────────────────────────────────────────────────────────


class PreflightCommandTests(APITestCase):
    def test_warn_only_never_raises_and_reports(self):
        out = StringIO()
        call_command("preflight", "--warn-only", stdout=out)
        report = out.getvalue()
        self.assertIn("PRÉFLIGHT PRODUCTION", report)
        # Core checks must always appear in the report.
        for check in ["DEBUG", "SECRET_KEY", "Database", "Email", "CORS", "JWT"]:
            self.assertIn(check, report)

    @override_settings(CORS_ALLOW_ALL_ORIGINS=True)
    def test_cors_wildcard_reported_as_fail(self):
        out = StringIO()
        call_command("preflight", "--warn-only", stdout=out)
        report = out.getvalue()
        self.assertIn("CORS_ALLOW_ALL_ORIGINS=True", report)

    @override_settings(CORS_ALLOW_ALL_ORIGINS=True)
    def test_gate_raises_when_a_failure_is_present(self):
        # Without --warn-only, any FAIL must make the command exit non-zero.
        with self.assertRaises(CommandError):
            call_command("preflight", stdout=StringIO())


# ── 2. Critical business gates ─────────────────────────────────────────────────


class _AuthMixin:
    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")


class BuyerKycSubmitTests(_AuthMixin, APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            username="kyc-buyer",
            email="kyc-buyer@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )

    def test_buyer_can_submit_identity_document(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("kyc-buyer-submit"),
            {"doc_type": "CNI", "file": _jpeg()},
            format="multipart",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        doc = ComplianceDocument.objects.get(user=self.buyer, doc_type="CNI")
        self.assertEqual(doc.status, "PENDING")

    def test_signature_and_consent_are_persisted(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("kyc-buyer-submit"),
            {
                "doc_type": "PASSPORT",
                "file": _jpeg("passport.jpg"),
                "signature": _png("signature.png"),
                "consent_accepted": "true",
            },
            format="multipart",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        doc = ComplianceDocument.objects.get(user=self.buyer, doc_type="PASSPORT")
        self.assertTrue(bool(doc.signature_image))
        self.assertIsNotNone(doc.consent_accepted_at)
        self.assertEqual(doc.consent_version, "1.0")

    def test_business_certificate_type_rejected_on_buyer_endpoint(self):
        self._auth_as(self.buyer)
        res = self.client.post(
            reverse("kyc-buyer-submit"),
            {"doc_type": "CERT_BUSINESS_REGISTRATION", "file": _jpeg()},
            format="multipart",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_resubmission_replaces_and_resets_to_pending(self):
        self._auth_as(self.buyer)
        url = reverse("kyc-buyer-submit")
        first = self.client.post(
            url, {"doc_type": "CNI", "file": _jpeg("a.jpg")}, format="multipart"
        )
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        # Reviewer rejects it…
        doc = ComplianceDocument.objects.get(user=self.buyer, doc_type="CNI")
        doc.status = "REJECTED"
        doc.save(update_fields=["status"])
        # …user re-submits → single doc, back to PENDING.
        second = self.client.post(
            url, {"doc_type": "CNI", "file": _jpeg("b.jpg")}, format="multipart"
        )
        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)
        self.assertEqual(
            ComplianceDocument.objects.filter(user=self.buyer, doc_type="CNI").count(), 1
        )
        doc.refresh_from_db()
        self.assertEqual(doc.status, "PENDING")

    def test_unauthenticated_cannot_submit(self):
        res = self.client.post(
            reverse("kyc-buyer-submit"),
            {"doc_type": "CNI", "file": _jpeg()},
            format="multipart",
        )
        self.assertIn(
            res.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )


class AdminAccessGateTests(_AuthMixin, APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            username="gate-buyer",
            email="gate-buyer@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )
        self.admin = User.objects.create_user(
            username="gate-admin",
            email="gate-admin@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_active=True,
        )

    def test_buyer_denied_admin_dashboard(self):
        self._auth_as(self.buyer)
        res = self.client.get(reverse("admin-dashboard"))
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_allowed_admin_dashboard(self):
        self._auth_as(self.admin)
        res = self.client.get(reverse("admin-dashboard"))
        self.assertEqual(res.status_code, status.HTTP_200_OK)


class WalletReconcileGateTests(_AuthMixin, APITestCase):
    def setUp(self):
        self.buyer = User.objects.create_user(
            username="rec-buyer",
            email="rec-buyer@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )
        self.admin = User.objects.create_user(
            username="rec-admin",
            email="rec-admin@test.local",
            password="TestPassword123!",
            role="GENERAL_ADMIN",
            is_active=True,
        )

    def test_buyer_cannot_reconcile(self):
        self._auth_as(self.buyer)
        res = self.client.post(reverse("wallet-reconcile"), {}, format="json")
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_reconcile_blocked_without_step_up(self):
        # A privileged admin still cannot move money without the 2FA step-up.
        self._auth_as(self.admin)
        res = self.client.post(
            reverse("wallet-reconcile"),
            {"transaction_id": "NCH-TEST", "status": "SUCCESS"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)
