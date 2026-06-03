"""C-2 — A product created with an image upload (multipart) must be immediately
visible in the public catalogue (regression guard for the invisible-product bug).
"""
import io

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto


def _real_jpeg(name="v.jpg"):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (32, 32), (10, 120, 200)).save(buf, format="JPEG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/jpeg")


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class ProductVisibilityAfterUploadTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.supplier = get_user_model().objects.create_user(
            username="c2v_sup", email="c2v_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000801")

    def test_multipart_uploaded_product_is_publicly_visible(self):
        sup = APIClient()
        sup.force_authenticate(user=self.supplier)
        body = {
            "title": "Article visible", "description": "desc", "brand": "QA",
            "category_name": "Divers", "weight_kg": "2",
            "min_order_qty": "10", "max_order_qty": "100",
            "price_for_min_qty": "5000", "price_for_max_qty": "4500",
            "image": _real_jpeg(),
        }
        created = sup.post("/api/products/", body, format="multipart")
        self.assertEqual(created.status_code, 201, created.content)
        pid = created.data["id"]

        anon = APIClient()
        public = anon.get("/api/products/")
        self.assertEqual(public.status_code, 200)
        self.assertIn(pid, [row["id"] for row in public.data["results"]])

        detail = anon.get(f"/api/products/{pid}/")
        self.assertEqual(detail.status_code, 200, "image-uploaded product must be retrievable publicly")
