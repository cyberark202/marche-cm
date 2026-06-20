"""ADMIN_LOGIC_AUDIT — preuves d'exécution de la posture d'autorisation admin.

Couvre la surface RÉELLE consommée par la console admin Flutter
(AdminRepository) + les invariants de sécurité demandés par l'audit :

  * AuthZ deny-by-default : un acheteur normal reçoit 403 sur CHAQUE
    endpoint réservé à l'admin (dashboard, audit, reconcile, compliance
    review, décision litige, gel escrow, création utilisateur géré).
  * Anti-escalade : impossible de passer buyer→admin via le profil
    (mass-assignment) ou via UserViewSet (lecture seule) ; l'admin
    lui-même ne peut pas fabriquer un GENERAL_ADMIN via l'API.
  * Anti-IDOR : la liste /api/users/ est auto-scopée pour un non-admin.
  * JWT falsifié → rejet.
  * Step-up obligatoire sur wallet.reconcile, même pour un admin.
  * Journalisation : les actions admin écrivent une ligne d'audit.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import override_settings
from rest_framework.test import APIClient

from apps.accounts import field_crypto
from apps.accounts.models import AuditLog, UserRole

User = get_user_model()


@override_settings(
    NOTCHPAY_ENABLED=False,
    DATA_ENCRYPTION_KEY="test-data-encryption-key-ci",
    SENSITIVE_ACTION_2FA_ENABLED=True,
    PASSWORD_HASHERS=["django.contrib.auth.hashers.MD5PasswordHasher"],
)
class AdminLogicAuditTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        self.admin = User.objects.create_user(
            username="al_admin", email="al_admin@test.local", password="TestPassword123!",
            role=UserRole.GENERAL_ADMIN, is_superuser=True, is_staff=True, is_verified=True,
            country_code="CM", phone_number="+237690009001")
        self.buyer = User.objects.create_user(
            username="al_buyer", email="al_buyer@test.local", password="TestPassword123!",
            role=UserRole.BUYER, is_verified=True, country_code="CM", phone_number="+237690009002")
        self.other = User.objects.create_user(
            username="al_other", email="al_other@test.local", password="TestPassword123!",
            role=UserRole.BUYER, is_verified=True, country_code="CM", phone_number="+237690009003")

        self.admin_api = APIClient(); self.admin_api.force_authenticate(user=self.admin)
        self.buyer_api = APIClient(); self.buyer_api.force_authenticate(user=self.buyer)
        self.anon = APIClient()

    # ── 1. AuthZ deny-by-default : un acheteur n'accède à AUCUN endpoint admin
    def test_buyer_forbidden_on_every_admin_endpoint(self):
        cases = [
            ("get", "/api/admin/dashboard/", None),
            ("get", "/api/admin/audit/export/", None),
            ("get", "/api/audit/events/", None),
            ("post", "/api/wallets/reconcile/", {"transaction_id": "x", "status": "SUCCESS"}),
            ("post", f"/api/compliance-documents/1/review/", {"status": "APPROVED"}),
            ("post", f"/api/shipment-disputes/1/decide/", {"status": "RESOLVED"}),
            ("post", "/api/users/create_managed_user/", {"username": "x"}),
            ("post", f"/api/users/{self.other.id}/suspend/", {"reason": "x"}),
        ]
        for method, url, payload in cases:
            call = getattr(self.buyer_api, method)
            resp = call(url, payload, format="json") if payload is not None else call(url)
            self.assertIn(
                resp.status_code, (403, 404),
                f"{method.upper()} {url} a renvoyé {resp.status_code}, attendu 403/404",
            )

    def test_anonymous_forbidden_on_admin_endpoints(self):
        for url in ("/api/admin/dashboard/", "/api/admin/audit/export/", "/api/audit/events/"):
            resp = self.anon.get(url)
            self.assertIn(resp.status_code, (401, 403), f"{url} → {resp.status_code}")

    # ── 2. Admin légitime : accès accordé
    def test_admin_dashboard_ok(self):
        resp = self.admin_api.get("/api/admin/dashboard/")
        self.assertEqual(resp.status_code, 200, resp.content)
        self.assertIn("users_total", resp.json())

    def test_admin_audit_events_ok_buyer_forbidden(self):
        self.assertEqual(self.admin_api.get("/api/audit/events/").status_code, 200)
        self.assertIn(self.buyer_api.get("/api/audit/events/").status_code, (403, 404))

    # ── 3. JWT falsifié → rejet
    def test_forged_jwt_rejected(self):
        forged = APIClient()
        forged.credentials(HTTP_AUTHORIZATION="Bearer not.a.valid.jwt.signature")
        self.assertEqual(forged.get("/api/admin/dashboard/").status_code, 401)

    # ── 4. Anti-escalade de privilège
    def test_buyer_cannot_self_promote_via_profile(self):
        """Le serializer profil n'expose pas `role`/`is_superuser` : ignorés."""
        resp = self.buyer_api.post(
            "/api/auth/profile/",
            {"role": "GENERAL_ADMIN", "is_superuser": True, "is_staff": True,
             "kyc_level": 9, "trust_score": 999},
            format="json",
        )
        self.buyer.refresh_from_db()
        self.assertEqual(self.buyer.role, UserRole.BUYER, resp.content)
        self.assertFalse(self.buyer.is_superuser)
        self.assertFalse(self.buyer.is_staff)

    def test_userviewset_is_read_only_no_role_patch(self):
        """UserViewSet est ReadOnly : PATCH/PUT sur un user → 405."""
        resp = self.buyer_api.patch(
            f"/api/users/{self.buyer.id}/", {"role": "GENERAL_ADMIN"}, format="json")
        self.assertEqual(resp.status_code, 405, resp.content)

    def test_admin_cannot_create_general_admin_via_api(self):
        resp = self.admin_api.post(
            "/api/users/create_managed_user/",
            {"username": "evil_admin", "email": "evil@test.local",
             "password": "TestPassword123!", "role": "GENERAL_ADMIN",
             "phone_number": "+237690009010", "country_code": "CM", "city": "Douala"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400, resp.content)
        self.assertFalse(User.objects.filter(username="evil_admin").exists())

    def test_admin_can_create_supplier(self):
        resp = self.admin_api.post(
            "/api/users/create_managed_user/",
            {"username": "good_supplier", "email": "sup@test.local",
             "password": "TestPassword123!", "role": "SUPPLIER",
             "phone_number": "+237690009011", "country_code": "CM", "city": "Douala"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.content)
        created = User.objects.get(username="good_supplier")
        self.assertEqual(created.role, UserRole.SUPPLIER)
        self.assertTrue(AuditLog.objects.filter(action_key="admin.users.manage").exists())

    # ── 5. Anti-IDOR : la liste users est auto-scopée pour un non-admin
    @staticmethod
    def _rows(resp):
        """Réponse DRF paginée ({results:[...]}) ou liste brute."""
        body = resp.json()
        return body["results"] if isinstance(body, dict) and "results" in body else body

    def test_userlist_self_scoped_for_buyer(self):
        resp = self.buyer_api.get("/api/users/")
        self.assertEqual(resp.status_code, 200, resp.content)
        ids = {row["id"] for row in self._rows(resp)}
        self.assertEqual(ids, {self.buyer.id},
                         "un acheteur ne doit voir que son propre compte")

    def test_userlist_full_for_admin(self):
        resp = self.admin_api.get("/api/users/")
        self.assertEqual(resp.status_code, 200, resp.content)
        ids = {row["id"] for row in self._rows(resp)}
        self.assertTrue({self.admin.id, self.buyer.id, self.other.id} <= ids)

    def test_buyer_cannot_retrieve_other_user(self):
        """get_queryset auto-scopé → 404 sur autrui (pas de fuite)."""
        resp = self.buyer_api.get(f"/api/users/{self.other.id}/")
        self.assertEqual(resp.status_code, 404, resp.content)

    # ── A-01 fix : recherche serveur (au-delà de la 1re page paginée)
    def test_admin_server_side_search_beyond_first_page(self):
        # Crée 30 acheteurs => la cible "needle" est hors de la 1re page (20).
        for i in range(30):
            User.objects.create_user(
                username=f"filler_{i}", email=f"filler_{i}@test.local",
                password="x", role=UserRole.BUYER, country_code="CM",
                phone_number=f"+23769010{i:04d}")
        needle = User.objects.create_user(
            username="needle_unique", email="needle@test.local", password="x",
            role=UserRole.BUYER, country_code="CM", phone_number="+237690200001")
        resp = self.admin_api.get("/api/users/?q=needle_unique")
        self.assertEqual(resp.status_code, 200, resp.content)
        ids = {row["id"] for row in self._rows(resp)}
        self.assertIn(needle.id, ids, "la recherche serveur doit trouver l'utilisateur cible")

    def test_admin_search_by_reference_code(self):
        resp = self.admin_api.get(f"/api/users/?q={self.other.reference_code}")
        self.assertEqual(resp.status_code, 200, resp.content)
        ids = {row["id"] for row in self._rows(resp)}
        self.assertEqual(ids, {self.other.id})

    def test_search_query_does_not_break_non_admin_scoping(self):
        """Régression anti-IDOR : un acheteur avec ?q= ne voit que lui-même."""
        resp = self.buyer_api.get(f"/api/users/?q={self.other.username}")
        self.assertEqual(resp.status_code, 200, resp.content)
        ids = {row["id"] for row in self._rows(resp)}
        self.assertEqual(ids, {self.buyer.id})

    # ── 6. Step-up obligatoire sur wallet.reconcile, même pour l'admin
    def test_admin_reconcile_requires_stepup(self):
        resp = self.admin_api.post(
            "/api/wallets/reconcile/",
            {"transaction_id": "nonexistent", "status": "SUCCESS"},
            format="json",
        )
        # 403 = step-up manquant (avant même de toucher la transaction)
        self.assertEqual(resp.status_code, 403, resp.content)
        self.assertIn("securite", str(resp.content, "utf-8").lower())

    # ── 7. Anti-self-suspension (cohérence du module d'administration)
    def test_admin_cannot_suspend_self(self):
        resp = self.admin_api.post(
            f"/api/users/{self.admin.id}/suspend/", {"reason": "x"}, format="json")
        self.assertEqual(resp.status_code, 400, resp.content)
        self.admin.refresh_from_db()
        self.assertFalse(getattr(self.admin, "is_suspended", False))
