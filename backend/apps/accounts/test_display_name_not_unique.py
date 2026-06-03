"""m-1 — Display name (first_name) is not globally unique on profile update.

Harmonises ProfileUpdateSerializer with RegisterSerializer (which dropped the
uniqueness check under H-005). Two users may share a display name.
"""
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings

from apps.accounts import field_crypto
from apps.accounts.serializers import ProfileUpdateSerializer


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class DisplayNameNotUniqueTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.first = u.objects.create_user(
            username="mm1_a", email="mm1_a@test.local", password="TestPassword123!",
            role="BUYER", first_name="Jean", country_code="CM", phone_number="+237690001301")
        self.second = u.objects.create_user(
            username="mm1_b", email="mm1_b@test.local", password="TestPassword123!",
            role="BUYER", first_name="Paul", country_code="CM", phone_number="+237690001302")

    def test_duplicate_display_name_is_allowed(self):
        s = ProfileUpdateSerializer(instance=self.second, data={"name": "Jean"}, partial=True)
        self.assertTrue(s.is_valid(), s.errors)
        self.assertEqual(s.validated_data.get("first_name"), "Jean")

    def test_short_display_name_still_rejected(self):
        s = ProfileUpdateSerializer(instance=self.second, data={"name": "J"}, partial=True)
        self.assertFalse(s.is_valid())
        self.assertIn("name", s.errors)
