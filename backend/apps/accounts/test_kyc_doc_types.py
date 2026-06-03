"""M-2 / M-3 — Buyer KYC document types: the view and the serializer must agree.

Regression: PROOF_ADDRESS and SELFIE were advertised by BuyerKycSubmitView but
rejected by ComplianceDocumentSerializer.ALLOWED_DOC_TYPES, 400'ing two steps of
the buyer KYC wizard. Both now derive from apps/accounts/kyc_constants.py.
"""
import io

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.accounts.kyc_constants import BUYER_IDENTITY_DOC_TYPES
from apps.accounts.models import ComplianceDocument
from apps.accounts.serializers import ComplianceDocumentSerializer

KYC_URL = "/api/auth/kyc/submit/"


def _jpeg(name="doc.jpg"):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (24, 24), (120, 120, 120)).save(buf, format="JPEG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/jpeg")


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class BuyerKycDocTypeTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.buyer = get_user_model().objects.create_user(
            username="kyc_buyer", email="kyc_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=False, kyc_level=0, country_code="CM",
            phone_number="+237690000951")
        self.client = APIClient()
        self.client.force_authenticate(user=self.buyer)

    def test_view_types_are_a_subset_of_serializer_allowed_types(self):
        """The invariant that makes the drift impossible to reintroduce."""
        self.assertTrue(
            BUYER_IDENTITY_DOC_TYPES.issubset(ComplianceDocumentSerializer.ALLOWED_DOC_TYPES),
            "BuyerKyc view advertises a doc_type the serializer rejects",
        )

    def test_all_buyer_identity_types_accepted(self):
        for dtype in sorted(BUYER_IDENTITY_DOC_TYPES):
            resp = self.client.post(
                KYC_URL,
                {"file": _jpeg(f"{dtype}.jpg"), "doc_type": dtype, "consent_accepted": "true"},
                format="multipart",
            )
            self.assertIn(resp.status_code, (200, 201), f"{dtype}: {resp.content}")
            doc = ComplianceDocument.objects.get(user=self.buyer, doc_type=dtype)
            self.assertEqual(doc.status, "PENDING")

    def test_proof_address_and_selfie_specifically_accepted(self):
        for dtype in ("PROOF_ADDRESS", "SELFIE"):
            resp = self.client.post(
                KYC_URL, {"file": _jpeg(), "doc_type": dtype}, format="multipart")
            self.assertIn(resp.status_code, (200, 201), f"{dtype} must be accepted: {resp.content}")

    def test_invalid_doc_type_rejected(self):
        resp = self.client.post(
            KYC_URL, {"file": _jpeg(), "doc_type": "BANANA"}, format="multipart")
        self.assertEqual(resp.status_code, 400, resp.content)

    def test_certification_type_rejected_for_buyer(self):
        resp = self.client.post(
            KYC_URL, {"file": _jpeg(), "doc_type": "CERT_BUSINESS_REGISTRATION"}, format="multipart")
        self.assertEqual(resp.status_code, 400, resp.content)

    def test_resubmission_replaces_and_resets_pending(self):
        first = self.client.post(
            KYC_URL, {"file": _jpeg(), "doc_type": "CNI"}, format="multipart")
        self.assertIn(first.status_code, (200, 201), first.content)
        doc = ComplianceDocument.objects.get(user=self.buyer, doc_type="CNI")
        ComplianceDocument.objects.filter(id=doc.id).update(status="APPROVED")
        again = self.client.post(
            KYC_URL, {"file": _jpeg(), "doc_type": "CNI"}, format="multipart")
        self.assertIn(again.status_code, (200, 201), again.content)
        doc.refresh_from_db()
        self.assertEqual(doc.status, "PENDING")
        # Still a single row (unique per user+doc_type).
        self.assertEqual(
            ComplianceDocument.objects.filter(user=self.buyer, doc_type="CNI").count(), 1)
