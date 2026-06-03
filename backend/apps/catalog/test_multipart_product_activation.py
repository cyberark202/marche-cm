"""C-2 — `is_active` must be server-controlled and behave identically for JSON
and multipart requests.

Root cause fixed: a DRF BooleanField absent from a multipart/form-data body was
coerced to False, so every product created with an image upload was silently
inactive (invisible in the public catalogue). `is_active` is now read-only and
forced True on create — and a manipulated payload cannot override it.
"""
import io
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import Product


def _real_jpeg(name="p.jpg"):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (32, 32), (200, 80, 40)).save(buf, format="JPEG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/jpeg")


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class MultipartProductActivationTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.supplier = get_user_model().objects.create_user(
            username="c2_sup", email="c2_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000701")
        self.client = APIClient()
        self.client.force_authenticate(user=self.supplier)

    def _form(self, **over):
        body = {
            "title": "Produit photo", "description": "desc", "brand": "QA",
            "category_name": "Divers", "weight_kg": "2",
            "min_order_qty": "10", "max_order_qty": "100",
            "price_for_min_qty": "5000", "price_for_max_qty": "4500",
        }
        body.update(over)
        return body

    def test_multipart_without_is_active_is_active_true(self):
        body = self._form()
        body["image"] = _real_jpeg()
        r = self.client.post("/api/products/", body, format="multipart")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertTrue(r.data["is_active"])
        self.assertTrue(Product.objects.get(id=r.data["id"]).is_active)

    def test_multipart_is_active_false_is_ignored(self):
        """Manipulated payload trying to publish an inactive product is overridden."""
        body = self._form(is_active="false")
        body["image"] = _real_jpeg()
        r = self.client.post("/api/products/", body, format="multipart")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertTrue(r.data["is_active"])
        self.assertTrue(Product.objects.get(id=r.data["id"]).is_active)

    def test_json_without_is_active_is_active_true(self):
        r = self.client.post("/api/products/", self._form(), format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertTrue(r.data["is_active"])

    def test_json_and_multipart_agree(self):
        j = self.client.post("/api/products/", self._form(title="J"), format="json")
        m_body = self._form(title="M")
        m_body["image"] = _real_jpeg()
        m = self.client.post("/api/products/", m_body, format="multipart")
        self.assertEqual(j.status_code, 201)
        self.assertEqual(m.status_code, 201)
        self.assertEqual(j.data["is_active"], m.data["is_active"])
        self.assertTrue(j.data["is_active"])
