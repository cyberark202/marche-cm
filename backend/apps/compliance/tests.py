"""Tests expiration documents KYC (doc 06) : alerte 30 j + rétrogradation."""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from apps.notifications.models import Notification, NotificationCategory

from .models import KYCApplication, KYCDocument, KYCStatus
from .tasks import check_kyc_document_expiry


class KYCDocumentExpiryTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(
            username="kyc_exp", email="kyc_exp@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=1, phone_number="+237690000801",
        )
        self.application = KYCApplication.objects.create(
            user=self.user, target_level=1, status=KYCStatus.APPROVED,
        )

    def _doc(self, expiry_date):
        return KYCDocument.objects.create(
            application=self.application, document_type="NATIONAL_ID",
            storage_key="kyc/test.pdf", file_hash="x" * 64, expiry_date=expiry_date,
        )

    def test_warning_sent_once_within_30_days(self):
        doc = self._doc(timezone.now().date() + timedelta(days=15))
        result = check_kyc_document_expiry()
        self.assertEqual(result["warned"], 1)
        doc.refresh_from_db()
        self.assertIsNotNone(doc.expiry_warning_sent_at)
        self.assertTrue(
            Notification.objects.filter(user=self.user, category=NotificationCategory.KYC).exists()
        )
        # Second run: no duplicate warning.
        self.assertEqual(check_kyc_document_expiry()["warned"], 0)

    def test_expired_document_downgrades_account(self):
        self._doc(timezone.now().date() - timedelta(days=1))
        result = check_kyc_document_expiry()
        self.assertEqual(result["expired"], 1)
        self.user.refresh_from_db()
        self.application.refresh_from_db()
        self.assertFalse(self.user.is_verified)
        self.assertEqual(self.user.kyc_level, 0)
        self.assertEqual(self.application.status, KYCStatus.EXPIRED)

    def test_valid_document_untouched(self):
        self._doc(timezone.now().date() + timedelta(days=365))
        result = check_kyc_document_expiry()
        self.assertEqual(result, {"warned": 0, "expired": 0})
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_verified)
