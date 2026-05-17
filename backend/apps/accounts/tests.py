from django.contrib.auth import get_user_model
from django.db import connection
from django.test import override_settings
from io import StringIO
from django.core.management import call_command
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts import field_crypto
from apps.accounts.models import ComplianceDocument


class LogoutTests(APITestCase):
    def test_logout_revokes_refresh_token(self):
        user = get_user_model().objects.create_user(
            username="user1",
            email="user1@test.local",
            password="TestPassword123!",
            is_active=True,
        )
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")
        res = self.client.post(reverse("auth-logout"), {"refresh": str(refresh)}, format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK)


class UserIsolationTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.buyer1 = User.objects.create_user(
            username="buyer1",
            email="buyer1@test.local",
            password="TestPassword123!",
            is_active=True,
            is_online=True,
            role="BUYER",
        )
        self.buyer2 = User.objects.create_user(
            username="buyer2",
            email="buyer2@test.local",
            password="TestPassword123!",
            is_active=True,
            is_online=True,
            role="BUYER",
        )
        self.admin = User.objects.create_user(
            username="admin1",
            email="admin1@test.local",
            password="TestPassword123!",
            is_active=True,
            role="GENERAL_ADMIN",
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def _rows(self, payload):
        if isinstance(payload, dict) and "results" in payload:
            return payload["results"]
        return payload

    def test_buyer_sees_only_self_in_users_list(self):
        self._auth_as(self.buyer1)
        res = self.client.get(reverse("user-list"))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        rows = self._rows(res.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], self.buyer1.id)

    def test_buyer_cannot_retrieve_another_user(self):
        self._auth_as(self.buyer1)
        res = self.client.get(reverse("user-detail", args=[self.buyer2.id]))
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_buyer_online_endpoint_returns_only_self(self):
        self._auth_as(self.buyer1)
        res = self.client.get(reverse("user-online"))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(res.data), 1)
        self.assertEqual(res.data[0]["id"], self.buyer1.id)

    def test_admin_can_see_all_users(self):
        self._auth_as(self.admin)
        res = self.client.get(reverse("user-list"))
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        rows = self._rows(res.data)
        ids = {row["id"] for row in rows}
        self.assertIn(self.admin.id, ids)
        self.assertIn(self.buyer1.id, ids)
        self.assertIn(self.buyer2.id, ids)


class ComplianceDocumentAccessTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.buyer = User.objects.create_user(
            username="buyer-doc",
            email="buyer-doc@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
        )
        self.supplier = User.objects.create_user(
            username="supplier-doc",
            email="supplier-doc@test.local",
            password="TestPassword123!",
            role="SUPPLIER",
            is_active=True,
        )

    def _auth_as(self, user):
        refresh = RefreshToken.for_user(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {refresh.access_token}")

    def _rows(self, payload):
        if isinstance(payload, dict) and "results" in payload:
            return payload["results"]
        return payload

    def test_buyer_cannot_create_compliance_document(self):
        self._auth_as(self.buyer)
        # Use valid JPEG magic bytes so upload_security passes and role check fires.
        fake_jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 20
        payload = {
            "doc_type": "CERT_BUSINESS_REGISTRATION",
            "file": SimpleUploadedFile("doc.jpg", fake_jpeg, content_type="image/jpeg"),
        }
        res = self.client.post(reverse("compliance-document-list"), payload, format="multipart")
        self.assertEqual(res.status_code, status.HTTP_403_FORBIDDEN)

    def test_supplier_cannot_duplicate_same_document_type(self):
        self._auth_as(self.supplier)
        fake_jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 20
        payload = {
            "doc_type": "CERT_BUSINESS_REGISTRATION",
            "file": SimpleUploadedFile("doc1.jpg", fake_jpeg, content_type="image/jpeg"),
        }
        first = self.client.post(reverse("compliance-document-list"), payload, format="multipart")
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        second_payload = {
            "doc_type": "CERT_BUSINESS_REGISTRATION",
            "file": SimpleUploadedFile("doc2.jpg", fake_jpeg, content_type="image/jpeg"),
        }
        second = self.client.post(reverse("compliance-document-list"), second_payload, format="multipart")
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)

    def test_user_can_access_own_approved_documents(self):
        doc = ComplianceDocument.objects.create(
            user=self.supplier,
            doc_type="CERT_INSURANCE",
            status="APPROVED",
            file=SimpleUploadedFile("public.jpg", b"fake", content_type="image/jpeg"),
        )
        # Authentication is now required — the old unauthenticated access was a BOLA
        # vulnerability and has been fixed.  Suppliers can still read their own docs.
        self._auth_as(self.supplier)
        res = self.client.get(f"{reverse('compliance-document-list')}?user_id={self.supplier.id}")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        rows = self._rows(res.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], doc.id)


class UserPiiEncryptionTests(APITestCase):
    def test_user_pii_fields_are_encrypted_at_rest(self):
        user = get_user_model().objects.create_user(
            username="enc_user",
            email="enc_user@test.local",
            password="TestPassword123!",
            role="BUYER",
            is_active=True,
            phone_number="+237670766331",
            city="Douala",
            location_label="Douala, Cameroon",
        )

        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT phone_number, city, location_label FROM accounts_user WHERE id = %s",
                [user.id],
            )
            row = cursor.fetchone()

        self.assertIsNotNone(row)
        phone_raw, city_raw, location_raw = row
        self.assertTrue(str(phone_raw).startswith("enc1$"))
        self.assertTrue(str(city_raw).startswith("enc1$"))
        self.assertTrue(str(location_raw).startswith("enc1$"))
        self.assertNotEqual(phone_raw, "+237670766331")
        self.assertNotEqual(city_raw, "Douala")
        self.assertNotEqual(location_raw, "Douala, Cameroon")

        user.refresh_from_db()
        self.assertEqual(user.phone_number, "+237670766331")
        self.assertEqual(user.city, "Douala")
        self.assertEqual(user.location_label, "Douala, Cameroon")

    def test_key_rotation_with_fallback_and_management_command(self):
        user_model = get_user_model()

        with override_settings(
            DATA_ENCRYPTION_KEY="legacy-key-secret",
            DATA_ENCRYPTION_FALLBACK_KEYS=[],
        ):
            field_crypto.clear_crypto_cache()
            user = user_model.objects.create_user(
                username="rotate_user",
                email="rotate_user@test.local",
                password="TestPassword123!",
                role="BUYER",
                is_active=True,
                phone_number="+237699000111",
                city="Douala",
                location_label="Douala, Cameroon",
            )

            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT phone_number, city, location_label FROM accounts_user WHERE id = %s",
                    [user.id],
                )
                legacy_row = cursor.fetchone()

        with override_settings(
            DATA_ENCRYPTION_KEY="new-key-secret",
            DATA_ENCRYPTION_FALLBACK_KEYS=["legacy-key-secret"],
        ):
            field_crypto.clear_crypto_cache()

            user.refresh_from_db()
            self.assertEqual(user.phone_number, "+237699000111")
            self.assertEqual(user.city, "Douala")
            self.assertEqual(user.location_label, "Douala, Cameroon")

            call_command("rotate_encrypted_user_pii", stdout=StringIO())

            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT phone_number, city, location_label FROM accounts_user WHERE id = %s",
                    [user.id],
                )
                rotated_row = cursor.fetchone()

            self.assertNotEqual(legacy_row, rotated_row)
            self.assertTrue(str(rotated_row[0]).startswith("enc1$"))
            self.assertTrue(str(rotated_row[1]).startswith("enc1$"))
            self.assertTrue(str(rotated_row[2]).startswith("enc1$"))

            user.refresh_from_db()
            self.assertEqual(user.phone_number, "+237699000111")
            self.assertEqual(user.city, "Douala")
            self.assertEqual(user.location_label, "Douala, Cameroon")
