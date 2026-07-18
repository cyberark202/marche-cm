from django.test import TestCase
from rest_framework.test import APITestCase

from apps.appconfig.models import AppPlatform, AppRelease
from apps.appconfig.views import parse_version, version_lt

URL = "/api/app/runtime-config/"


class VersionCompareTests(TestCase):
    def test_parse_ignores_build_metadata(self):
        self.assertEqual(parse_version("1.2.3+45"), (1, 2, 3))

    def test_parse_tolerates_garbage(self):
        self.assertEqual(parse_version("1.x.3"), (1, 0, 3))

    def test_lt_basic(self):
        self.assertTrue(version_lt("1.0.0", "1.0.1"))
        self.assertTrue(version_lt("1.0", "1.0.1"))
        self.assertFalse(version_lt("1.2.0", "1.2.0"))
        self.assertFalse(version_lt("2.0.0", "1.9.9"))


class RuntimeConfigViewTests(APITestCase):
    def test_no_release_is_fail_open(self):
        resp = self.client.get(URL, {"app": "driver", "platform": "android", "version": "1.0.0"})
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(resp.data["update_required"])
        self.assertFalse(resp.data["update_available"])
        self.assertFalse(resp.data["kill_switch"])
        self.assertEqual(resp.data["config_version"], 0)

    def test_update_required_when_below_min(self):
        AppRelease.objects.create(
            app="driver",
            platform=AppPlatform.ANDROID,
            latest_version="1.5.0",
            min_supported_version="1.2.0",
            download_url="https://example.com/driver.apk",
            update_message={"fr": "Mise à jour requise"},
        )
        resp = self.client.get(URL, {"app": "driver", "platform": "android", "version": "1.1.0"})
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.data["update_required"])
        self.assertTrue(resp.data["update_available"])
        self.assertEqual(resp.data["download_url"], "https://example.com/driver.apk")
        self.assertEqual(resp.data["update_message"], {"fr": "Mise à jour requise"})

    def test_update_available_but_not_required(self):
        AppRelease.objects.create(
            app="clients",
            platform=AppPlatform.ANDROID,
            latest_version="2.0.0",
            min_supported_version="1.0.0",
        )
        resp = self.client.get(URL, {"app": "clients", "platform": "android", "version": "1.5.0"})
        self.assertTrue(resp.data["update_available"])
        self.assertFalse(resp.data["update_required"])

    def test_up_to_date_client(self):
        AppRelease.objects.create(
            app="app",
            platform=AppPlatform.ANDROID,
            latest_version="1.0.0",
            min_supported_version="1.0.0",
        )
        resp = self.client.get(URL, {"app": "app", "platform": "android", "version": "1.0.0"})
        self.assertFalse(resp.data["update_available"])
        self.assertFalse(resp.data["update_required"])

    def test_kill_switch_and_maintenance_passthrough(self):
        AppRelease.objects.create(
            app="admin",
            platform=AppPlatform.ANDROID,
            latest_version="1.0.0",
            min_supported_version="1.0.0",
            maintenance=True,
            maintenance_message={"fr": "Maintenance en cours"},
            kill_switch=True,
            feature_flags={"wallet_v2": True},
        )
        resp = self.client.get(URL, {"app": "admin", "platform": "android", "version": "1.0.0"})
        self.assertTrue(resp.data["maintenance"])
        self.assertEqual(resp.data["maintenance_message"], {"fr": "Maintenance en cours"})
        self.assertTrue(resp.data["kill_switch"])
        self.assertEqual(resp.data["feature_flags"], {"wallet_v2": True})

    def test_inactive_release_is_ignored(self):
        AppRelease.objects.create(
            app="driver",
            platform=AppPlatform.ANDROID,
            latest_version="9.9.9",
            min_supported_version="9.9.9",
            is_active=False,
        )
        resp = self.client.get(URL, {"app": "driver", "platform": "android", "version": "1.0.0"})
        self.assertFalse(resp.data["update_required"])
