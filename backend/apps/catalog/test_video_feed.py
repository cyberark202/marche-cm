"""Feed vidéo TikTok-like — contrat serveur.

Prouve que le payload produit embarque compteurs et états utilisateur
(likes/commentaires/vues, déjà-liké/suivi/favori) — avant, le client devait
faire 3 appels HTTP par vidéo — que le filtre ?has_video=true est appliqué,
et que les commentaires supportent réponses (1 niveau) et likes.
"""
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.catalog.models import (
    Product,
    ProductCategory,
    SellerFollow,
    VideoComment,
    VideoCommentLike,
    VideoLike,
)


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class VideoFeedContractTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        User = get_user_model()
        self.seller = User.objects.create_user(
            username="feed_seller", email="feed_seller@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, country_code="CM",
            phone_number="+237690000911")
        self.buyer = User.objects.create_user(
            username="feed_buyer", email="feed_buyer@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=1, country_code="CM",
            phone_number="+237690000912")
        category = ProductCategory.objects.create(name="Divers")
        common = dict(
            seller=self.seller, description="desc", brand="QA", category=category,
            weight_kg=1, min_order_qty=1, max_order_qty=10,
            price_for_min_qty=1000, price_for_max_qty=1000, is_active=True,
        )
        self.with_video = Product.objects.create(title="Avec video", **common)
        # Affectation directe du chemin : l'upload réel (validation ffprobe)
        # est couvert ailleurs, ici seul le contrat du feed est testé.
        Product.objects.filter(pk=self.with_video.pk).update(video="products/videos/demo.mp4")
        self.without_video = Product.objects.create(title="Sans video", **common)
        self.client_buyer = APIClient()
        self.client_buyer.force_authenticate(user=self.buyer)

    def _rows(self, response):
        return response.data["results"] if isinstance(response.data, dict) else response.data

    def test_has_video_filter(self):
        rows = self._rows(self.client_buyer.get("/api/products/?has_video=true"))
        titles = {row["title"] for row in rows}
        self.assertEqual(titles, {"Avec video"})

    def test_feed_embeds_counts_and_user_state(self):
        VideoLike.objects.create(user=self.buyer, product=self.with_video)
        VideoComment.objects.create(user=self.buyer, product=self.with_video, message="Top")
        SellerFollow.objects.create(follower=self.buyer, seller=self.seller)
        rows = self._rows(self.client_buyer.get("/api/products/?has_video=true"))
        row = rows[0]
        self.assertEqual(row["video_likes_count"], 1)
        self.assertEqual(row["video_comments_count"], 1)
        self.assertTrue(row["is_video_liked"])
        self.assertTrue(row["is_following_seller"])
        self.assertFalse(row["is_favorited"])
        self.assertEqual(row["video_views_count"], 0)

    def test_anonymous_feed_defaults(self):
        rows = self._rows(APIClient().get("/api/products/?has_video=true"))
        self.assertFalse(rows[0]["is_video_liked"])
        self.assertFalse(rows[0]["is_following_seller"])

    def test_comment_reply_one_level_and_listing(self):
        root = VideoComment.objects.create(user=self.seller, product=self.with_video, message="Dispo")
        response = self.client_buyer.post(
            "/api/video-comments/",
            {"product": self.with_video.id, "message": "Quel prix ?", "parent": root.id},
        )
        self.assertEqual(response.status_code, 201, response.content)
        self.assertTrue(response.data["is_seller"] is False)

        # La liste racine n'inclut pas les réponses, mais expose replies_count.
        top = self._rows(self.client_buyer.get(f"/api/video-comments/?product_id={self.with_video.id}"))
        self.assertEqual(len(top), 1)
        self.assertEqual(top[0]["replies_count"], 1)
        self.assertTrue(top[0]["is_seller"])

        replies = self._rows(self.client_buyer.get(f"/api/video-comments/?parent_id={root.id}"))
        self.assertEqual(len(replies), 1)
        self.assertEqual(replies[0]["message"], "Quel prix ?")

        # Pas de réponse à une réponse (fil à 1 niveau).
        nested = self.client_buyer.post(
            "/api/video-comments/",
            {"product": self.with_video.id, "message": "encore", "parent": response.data["id"]},
        )
        self.assertEqual(nested.status_code, 403)

    def test_comment_reply_must_match_product(self):
        root = VideoComment.objects.create(user=self.seller, product=self.with_video, message="Dispo")
        response = self.client_buyer.post(
            "/api/video-comments/",
            {"product": self.without_video.id, "message": "hs", "parent": root.id},
        )
        self.assertEqual(response.status_code, 403)

    def test_comment_like_toggle(self):
        comment = VideoComment.objects.create(user=self.seller, product=self.with_video, message="Dispo")
        url = f"/api/video-comments/{comment.id}/like/"
        response = self.client_buyer.post(url, {})
        self.assertEqual(response.data, {"liked": True, "total_likes": 1})
        response = self.client_buyer.post(url, {})
        self.assertEqual(response.data, {"liked": False, "total_likes": 0})
        self.assertEqual(VideoCommentLike.objects.count(), 0)

        # Le compteur remonte dans la liste.
        self.client_buyer.post(url, {})
        top = self._rows(self.client_buyer.get(f"/api/video-comments/?product_id={self.with_video.id}"))
        self.assertEqual(top[0]["likes_count"], 1)
        self.assertTrue(top[0]["is_liked"])
