"""M-1 — Registration must NOT block on the Nominatim geocoding HTTP call.

Geocoding is offloaded to a Celery task (apps.accounts.tasks.user_geocode_task),
published on a short-lived daemon thread so the request never waits on the
broker. These tests prove:
  * the synchronous geocoder is never invoked during the registration request;
  * the dispatch helper publishes the task (and swallows broker errors);
  * registration stays well under the 500 ms target even when the broker is
    unreachable (the publish blocks the *thread*, not the request);
  * a before/after micro-benchmark vs the old inline geocode.
"""
import time
from unittest import mock

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings

from apps.accounts import field_crypto
from apps.accounts.location_service import _dispatch_geocode_task

REGISTER_URL = "/api/auth/register/"
FAST_HASHER = ["django.contrib.auth.hashers.MD5PasswordHasher"]
APPLY_ASYNC = "apps.accounts.tasks.user_geocode_task.apply_async"


@override_settings(
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    AUTH_LOCKDOWN=False,
)
class RegisterGeocodeAsyncTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def _payload(self, email):
        return {
            "name": "QA User", "email": email, "phone_number": "+237690000901",
            "password": "ChangeMe123!", "city": "Douala", "country_code": "CM",
        }

    # --- the dispatch helper (synchronous, deterministic) ---
    def test_dispatch_publishes_task(self):
        with mock.patch(APPLY_ASYNC) as m:
            _dispatch_geocode_task(4242)
        m.assert_called_once()
        self.assertEqual(m.call_args.kwargs["args"], [4242])

    def test_dispatch_swallows_broker_error(self):
        with mock.patch(APPLY_ASYNC, side_effect=RuntimeError("broker down")):
            _dispatch_geocode_task(4242)  # must not raise

    # --- the registration request path ---
    def test_geocoder_not_called_inline(self):
        with mock.patch("apps.accounts.location_service.update_user_location") as m_geo, \
             mock.patch(APPLY_ASYNC):
            resp = self.client.post(REGISTER_URL, self._payload("async1@qa.test"),
                                    content_type="application/json")
        self.assertIn(resp.status_code, (200, 201), resp.content)
        m_geo.assert_not_called()
        self.assertTrue(get_user_model().objects.filter(email__iexact="async1@qa.test").exists())

    @override_settings(PASSWORD_HASHERS=FAST_HASHER)
    def test_register_fast_even_when_broker_unreachable(self):
        # No mocking of the broker: apply_async will fail (no Redis), but that
        # happens on the daemon thread — the request must still be < 500 ms.
        t0 = time.perf_counter()
        resp = self.client.post(REGISTER_URL, self._payload("perf@qa.test"),
                                content_type="application/json")
        elapsed = time.perf_counter() - t0
        self.assertIn(resp.status_code, (200, 201), resp.content)
        self.assertLess(elapsed, 0.5, f"registration took {elapsed*1000:.0f}ms (target < 500ms)")

    @override_settings(PASSWORD_HASHERS=FAST_HASHER)
    def test_benchmark_before_after(self):
        # BEFORE: the old inline behaviour — a slow provider blocks the caller.
        slow_user = get_user_model().objects.create_user(
            username="bench_old", email="bench_old@qa.test", password="x",
            role="BUYER", country_code="CM", city="Douala", phone_number="+237690000902")
        from apps.accounts.location_service import update_user_location
        with mock.patch(
            "apps.accounts.location_service.geocode_with_nominatim",
            side_effect=lambda **kw: time.sleep(0.4) or None,
        ):
            t0 = time.perf_counter()
            update_user_location(slow_user, force=True)
            before = time.perf_counter() - t0

        # AFTER: registration dispatches async — no inline geocode.
        with mock.patch(APPLY_ASYNC):
            t0 = time.perf_counter()
            resp = self.client.post(REGISTER_URL, self._payload("bench_new@qa.test"),
                                    content_type="application/json")
            after = time.perf_counter() - t0

        self.assertIn(resp.status_code, (200, 201), resp.content)
        self.assertLess(after, before,
                        f"async register ({after*1000:.0f}ms) should beat inline geocode ({before*1000:.0f}ms)")
        self.assertLess(after, 0.5)
