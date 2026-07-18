"""Tests du cycle de location + séquestre (doc 14).

Vérifie les invariants financiers : blocage des fonds, remboursement au refus,
libération loyer/caution à la clôture conforme, et arbitrage de caution en litige.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test.utils import override_settings
from rest_framework.test import APITestCase

from apps.accounts import field_crypto
from apps.rentals.models import RentalBooking, RentalBookingStatus, RentalListing, RentalListingStatus
from apps.wallets.models import Wallet


@override_settings(NOTCHPAY_ENABLED=False, DATA_ENCRYPTION_KEY="test-data-encryption-key-ci")
class RentalFlowTests(APITestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        field_crypto.clear_crypto_cache()

    def setUp(self):
        u = get_user_model()
        self.owner = u.objects.create_user(
            username="rent_owner", email="rent_owner@test.local", password="TestPassword123!",
            role="SUPPLIER", is_verified=True, kyc_level=2, phone_number="+237690000701")
        self.renter = u.objects.create_user(
            username="rent_renter", email="rent_renter@test.local", password="TestPassword123!",
            role="BUYER", is_verified=True, kyc_level=2, phone_number="+237690000702")
        self.admin = u.objects.create_user(
            username="rent_admin", email="rent_admin@test.local", password="TestPassword123!",
            role="GENERAL_ADMIN", is_verified=True, kyc_level=2, is_staff=True, phone_number="+237690000703")
        self.listing = RentalListing.objects.create(
            owner=self.owner, title="Perceuse", description="outil", category="Materiel",
            price_period="DAY", price_per_period=Decimal("2000.00"), deposit_amount=Decimal("10000.00"),
            ownership_proof="rentals/ownership/x.pdf", status=RentalListingStatus.PUBLISHED)
        w, _ = Wallet.objects.get_or_create(owner=self.renter)
        w.available_balance = Decimal("100000.00")
        w.locked_balance = Decimal("0.00")
        w.pending_balance = Decimal("0.00")
        w.save(update_fields=["available_balance", "locked_balance", "pending_balance"])

    def _book(self, days=3):
        self.client.force_authenticate(self.renter)
        start = date.today() + timedelta(days=1)
        end = start + timedelta(days=days - 1)
        res = self.client.post("/api/rental-bookings/", {
            "listing": self.listing.id,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
        }, format="json")
        self.assertEqual(res.status_code, 201, res.data)
        return RentalBooking.objects.get(id=res.data["id"])

    def test_publish_requires_kyc_level_2(self):
        u = get_user_model()
        weak = u.objects.create_user(
            username="rent_weak", email="rent_weak@test.local", password="TestPassword123!",
            role="BUYER", is_verified=False, kyc_level=0, phone_number="+237690000704")
        self.client.force_authenticate(weak)
        res = self.client.post("/api/rental-listings/", {
            "title": "Velo", "description": "d", "price_period": "DAY", "price_per_period": "1000.00",
        }, format="json")
        self.assertEqual(res.status_code, 403)

    def test_booking_computes_amount_and_locks_funds_on_pay(self):
        booking = self._book(days=3)
        self.assertEqual(booking.rental_amount, Decimal("6000.00"))
        self.assertEqual(booking.deposit_amount, Decimal("10000.00"))
        res = self.client.post(f"/api/rental-bookings/{booking.id}/pay/")
        self.assertEqual(res.status_code, 200, res.data)
        booking.refresh_from_db()
        self.assertEqual(booking.status, RentalBookingStatus.PAID)
        w = Wallet.objects.get(owner=self.renter)
        self.assertEqual(w.locked_balance, Decimal("16000.00"))
        self.assertEqual(w.available_balance, Decimal("84000.00"))

    def test_refuse_refunds_everything(self):
        booking = self._book()
        self.client.post(f"/api/rental-bookings/{booking.id}/pay/")
        self.client.force_authenticate(self.owner)
        res = self.client.post(f"/api/rental-bookings/{booking.id}/refuse/")
        self.assertEqual(res.status_code, 200, res.data)
        w = Wallet.objects.get(owner=self.renter)
        self.assertEqual(w.available_balance, Decimal("100000.00"))
        self.assertEqual(w.locked_balance, Decimal("0.00"))

    def test_full_conform_cycle_releases_rent_and_returns_deposit(self):
        booking = self._book(days=3)
        self.client.post(f"/api/rental-bookings/{booking.id}/pay/")
        self.client.force_authenticate(self.owner)
        self.client.post(f"/api/rental-bookings/{booking.id}/accept/")
        self._otp_roundtrip(booking, issue_as=self.owner, confirm_as=self.renter,
                            issue_url="issue-handover-otp", confirm_url="confirm-handover", otp_field="handover_otp_hash")
        booking.refresh_from_db()
        self.assertEqual(booking.status, RentalBookingStatus.IN_PROGRESS)
        self._otp_roundtrip(booking, issue_as=self.renter, confirm_as=self.owner,
                            issue_url="issue-return-otp", confirm_url="confirm-return", otp_field="return_otp_hash")
        booking.refresh_from_db()
        self.assertEqual(booking.status, RentalBookingStatus.RETURNED)
        self.client.force_authenticate(self.owner)
        res = self.client.post(f"/api/rental-bookings/{booking.id}/settle/")
        self.assertEqual(res.status_code, 200, res.data)
        booking.refresh_from_db()
        self.assertEqual(booking.status, RentalBookingStatus.COMPLETED)
        renter_w = Wallet.objects.get(owner=self.renter)
        owner_w = Wallet.objects.get(owner=self.owner)
        self.assertEqual(renter_w.locked_balance, Decimal("0.00"))
        self.assertEqual(renter_w.available_balance, Decimal("94000.00"))
        self.assertEqual(owner_w.available_balance, Decimal("5400.00"))

    def test_dispute_forfeits_partial_deposit_to_owner(self):
        booking = self._book(days=3)
        self.client.post(f"/api/rental-bookings/{booking.id}/pay/")
        self.client.force_authenticate(self.owner)
        self.client.post(f"/api/rental-bookings/{booking.id}/accept/")
        self._otp_roundtrip(booking, issue_as=self.owner, confirm_as=self.renter,
                            issue_url="issue-handover-otp", confirm_url="confirm-handover", otp_field="handover_otp_hash")
        self._otp_roundtrip(booking, issue_as=self.renter, confirm_as=self.owner,
                            issue_url="issue-return-otp", confirm_url="confirm-return", otp_field="return_otp_hash")
        self.client.force_authenticate(self.owner)
        self.client.post(f"/api/rental-bookings/{booking.id}/open-dispute/", {"reason": "raye"}, format="json")
        self.client.force_authenticate(self.admin)
        res = self.client.post(f"/api/rental-bookings/{booking.id}/resolve-dispute/",
                               {"deposit_forfeit": "4000.00"}, format="json")
        self.assertEqual(res.status_code, 200, res.data)
        renter_w = Wallet.objects.get(owner=self.renter)
        owner_w = Wallet.objects.get(owner=self.owner)
        self.assertEqual(renter_w.locked_balance, Decimal("0.00"))
        self.assertEqual(renter_w.available_balance, Decimal("90000.00"))
        self.assertEqual(owner_w.available_balance, Decimal("9400.00"))

    def _otp_roundtrip(self, booking, *, issue_as, confirm_as, issue_url, confirm_url, otp_field):
        from django.contrib.auth.hashers import make_password

        self.client.force_authenticate(issue_as)
        res = self.client.post(f"/api/rental-bookings/{booking.id}/{issue_url}/")
        self.assertEqual(res.status_code, 200, res.data)
        known = "1234"
        booking.refresh_from_db()
        setattr(booking, otp_field, make_password(known))
        booking.save(update_fields=[otp_field])
        self.client.force_authenticate(confirm_as)
        res = self.client.post(f"/api/rental-bookings/{booking.id}/{confirm_url}/", {"otp": known}, format="json")
        self.assertEqual(res.status_code, 200, res.data)
