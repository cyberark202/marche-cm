"""BUG-S1 — Galerie multi-images produit.

Avant: `Product` ne portait qu'un seul `image` -> la consigne "jusqu'a 10 images"
etait infaisable au niveau donnees. Ces tests prouvent que le vendeur peut
publier/mettre a jour un produit avec plusieurs images (cap 10), que chaque
fichier est valide (magic-bytes), que l'image principale est retro-remplie, et
que seul le proprietaire peut supprimer une image.
"""
import io
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import Product, ProductImage


def _real_jpeg(name="p.jpg"):
    from PIL import Image
    buf = io.BytesIO()
    Image.new("RGB", (32, 32), (200, 80, 40)).save(buf, format="JPEG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/jpeg")


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class ProductGalleryTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.supplier = get_user_model().objects.create_user(
            username="gal_sup", email="gal_sup@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000801")
        self.other = get_user_model().objects.create_user(
            username="gal_other", email="gal_other@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000802")
        self.client = APIClient()
        self.client.force_authenticate(user=self.supplier)

    def _form(self, **over):
        body = {
            "title": "Produit galerie", "description": "desc", "brand": "QA",
            "category_name": "Divers", "weight_kg": "2",
            "available_qty": "100", "unit_price": "5000",
        }
        body.update(over)
        return body

    def test_create_with_multiple_gallery_images(self):
        body = self._form()
        body["gallery_images"] = [_real_jpeg("a.jpg"), _real_jpeg("b.jpg"), _real_jpeg("c.jpg")]
        r = self.client.post("/api/products/", body, format="multipart")
        self.assertEqual(r.status_code, 201, r.content)
        product = Product.objects.get(id=r.data["id"])
        self.assertEqual(product.images.count(), 3)
        self.assertTrue(bool(product.image))
        self.assertEqual(len(r.data["images"]), 3)
        self.assertEqual([img["position"] for img in r.data["images"]], [0, 1, 2])

    def test_gallery_cap_at_ten(self):
        body = self._form()
        body["gallery_images"] = [_real_jpeg(f"{i}.jpg") for i in range(11)]
        r = self.client.post("/api/products/", body, format="multipart")
        self.assertEqual(r.status_code, 400, r.content)
        self.assertEqual(Product.objects.count(), 0)
        self.assertEqual(ProductImage.objects.count(), 0)

    def test_gallery_rejects_disguised_file(self):
        fake = SimpleUploadedFile("evil.jpg", b"<?php echo 1; ?>", content_type="image/jpeg")
        body = self._form()
        body["gallery_images"] = [fake]
        r = self.client.post("/api/products/", body, format="multipart")
        self.assertEqual(r.status_code, 400, r.content)
        self.assertEqual(Product.objects.count(), 0)

    def test_update_appends_within_cap(self):
        body = self._form()
        body["gallery_images"] = [_real_jpeg("a.jpg")]
        r = self.client.post("/api/products/", body, format="multipart")
        pid = r.data["id"]
        r2 = self.client.patch(
            f"/api/products/{pid}/",
            {"gallery_images": [_real_jpeg(f"{i}.jpg") for i in range(8)]},
            format="multipart",
        )
        self.assertEqual(r2.status_code, 200, r2.content)
        self.assertEqual(Product.objects.get(id=pid).images.count(), 9)
        r3 = self.client.patch(
            f"/api/products/{pid}/",
            {"gallery_images": [_real_jpeg("x.jpg"), _real_jpeg("y.jpg")]},
            format="multipart",
        )
        self.assertEqual(r3.status_code, 400, r3.content)
        self.assertEqual(Product.objects.get(id=pid).images.count(), 9)

    def test_owner_can_delete_image_others_cannot(self):
        body = self._form()
        body["gallery_images"] = [_real_jpeg("a.jpg"), _real_jpeg("b.jpg")]
        r = self.client.post("/api/products/", body, format="multipart")
        pid = r.data["id"]
        image_id = r.data["images"][0]["id"]

        self.client.force_authenticate(user=self.other)
        r_forbidden = self.client.delete(f"/api/products/{pid}/images/{image_id}/")
        self.assertIn(r_forbidden.status_code, (403, 404), r_forbidden.content)
        self.assertEqual(Product.objects.get(id=pid).images.count(), 2)

        self.client.force_authenticate(user=self.supplier)
        r_ok = self.client.delete(f"/api/products/{pid}/images/{image_id}/")
        self.assertEqual(r_ok.status_code, 204, r_ok.content)
        self.assertEqual(Product.objects.get(id=pid).images.count(), 1)

    def test_create_without_gallery_still_works(self):
        r = self.client.post("/api/products/", self._form(), format="json")
        self.assertEqual(r.status_code, 201, r.content)
        self.assertEqual(r.data["images"], [])
