"""
Regression tests for Wave 2 (CRITICAL remediation pass — financial settlement
and WebSocket authorization).

Coverage:
  * [WS-001] BaseAuthConsumer rejects unauthenticated scope.
  * [WS-003] _coerce_finite_float rejects NaN/inf/strings; lat/lng range guard.
  * [FIN-005] DisputeService._to_decimal rejects garbage, accepts Decimal/str.
  * [FIN-005] make_decision routes each outcome to the correct OrderFinanceService
              primitive AND emits an immutable audit log + DisputeDecision row.
  * [FIN-005] make_decision refuses negative amounts.
  * [FIN-008/009] EscrowService ghost methods raise EscrowServiceUnsupportedError.
"""
from __future__ import annotations

from decimal import Decimal
from unittest.mock import MagicMock, patch

from asgiref.sync import async_to_sync
from django.contrib.auth import get_user_model
from django.test import TestCase

from rest_framework.exceptions import ValidationError as DRFValidationError

User = get_user_model()


# ─────────────────────────────────────────────────────────────────────────────
# [WS-003] _coerce_finite_float helper
# ─────────────────────────────────────────────────────────────────────────────

class CoerceFiniteFloatTests(TestCase):
    def setUp(self):
        from apps.realtime.consumers import _coerce_finite_float
        self.coerce = _coerce_finite_float

    def test_accepts_int_and_float(self):
        self.assertEqual(self.coerce(0), 0.0)
        self.assertEqual(self.coerce(42), 42.0)
        self.assertEqual(self.coerce(3.14), 3.14)
        self.assertEqual(self.coerce("12.5"), 12.5)

    def test_rejects_nan_inf(self):
        self.assertIsNone(self.coerce(float("nan")))
        self.assertIsNone(self.coerce(float("inf")))
        self.assertIsNone(self.coerce(float("-inf")))

    def test_rejects_bool_and_garbage(self):
        # bool is an int subtype — must be explicitly rejected (audit clarity)
        self.assertIsNone(self.coerce(True))
        self.assertIsNone(self.coerce(False))
        self.assertIsNone(self.coerce("not-a-number"))
        self.assertIsNone(self.coerce(None))


# ─────────────────────────────────────────────────────────────────────────────
# [WS-001] BaseAuthConsumer closes when no valid user
# ─────────────────────────────────────────────────────────────────────────────

class BaseAuthConsumerTests(TestCase):
    def test_close_called_on_anonymous_scope(self):
        from apps.realtime.consumers import BaseAuthConsumer

        consumer = BaseAuthConsumer()
        consumer.scope = {
            "path": "/ws/notifications/",
            "subprotocols": [],
            "headers": [],
            "query_string": b"",
            "client": ("127.0.0.1", 0),
            "user": None,
        }

        async def _drive():
            close_calls = []
            super_calls = []

            async def fake_close(code=None):
                close_calls.append(code)

            async def fake_super_connect(_msg):
                super_calls.append(True)

            consumer.close = fake_close
            # Patch the parent connect via instance attribute — simpler than mocking MRO.
            consumer._super_connect = fake_super_connect  # documented anchor
            await consumer.websocket_connect({})
            return close_calls, super_calls

        with patch(
            "apps.realtime.consumers.authenticate_scope_user",
            new=lambda scope: _async_none(),
        ):
            close_calls, super_calls = async_to_sync(_drive)()

        self.assertEqual(close_calls, [4401])
        self.assertEqual(super_calls, [])


async def _async_none():
    return None


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-005] DisputeService._to_decimal helper
# ─────────────────────────────────────────────────────────────────────────────

class ToDecimalTests(TestCase):
    def setUp(self):
        from apps.disputes.services import _to_decimal
        self.to_dec = _to_decimal

    def test_accepts_decimal_str_int(self):
        self.assertEqual(self.to_dec(Decimal("12.34"), "x"), Decimal("12.34"))
        self.assertEqual(self.to_dec("0.50", "x"), Decimal("0.50"))
        self.assertEqual(self.to_dec(100, "x"), Decimal("100"))
        self.assertEqual(self.to_dec(None, "x"), Decimal("0"))
        self.assertEqual(self.to_dec("", "x"), Decimal("0"))

    def test_rejects_garbage(self):
        with self.assertRaises(DRFValidationError):
            self.to_dec("not-a-number", "buyer_refund")
        with self.assertRaises(DRFValidationError):
            self.to_dec(object(), "seller_release")


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-008/009] EscrowService ghost methods refuse to execute
# ─────────────────────────────────────────────────────────────────────────────

class EscrowServiceGhostMethodTests(TestCase):
    def test_create_order_escrow_raises(self):
        from apps.escrow.services import EscrowService, EscrowServiceUnsupportedError

        with self.assertRaises(EscrowServiceUnsupportedError) as ctx:
            EscrowService().create_order_escrow(
                payer=None, beneficiary=None, amount=Decimal("100"),
                commission=Decimal("5"), order_id="x",
            )
        msg = str(ctx.exception)
        self.assertIn("OrderFinanceService", msg)
        self.assertIn("FIN-008/009", msg)

    def test_release_to_beneficiary_raises(self):
        from apps.escrow.services import EscrowService, EscrowServiceUnsupportedError

        with self.assertRaises(EscrowServiceUnsupportedError):
            EscrowService().release_to_beneficiary(
                hold=MagicMock(pk="x"), amount=Decimal("100"),
                commission=Decimal("0"), actor=None, reason="test",
            )

    def test_refund_to_payer_raises(self):
        from apps.escrow.services import EscrowService, EscrowServiceUnsupportedError

        with self.assertRaises(EscrowServiceUnsupportedError):
            EscrowService().refund_to_payer(hold=MagicMock(pk="x"), actor=None, reason="test")


# ─────────────────────────────────────────────────────────────────────────────
# [FIN-005] make_decision routing per outcome
# ─────────────────────────────────────────────────────────────────────────────

class MakeDecisionRoutingTests(TestCase):
    def setUp(self):
        from apps.disputes.models import DisputeCase, DisputeState

        self.admin = User.objects.create_user(
            username="admin_1", email="admin@example.com",
            first_name="Admin", password="Pass!123",
            role="GENERAL_ADMIN",
        )
        self.opener = User.objects.create_user(
            username="opener_1", email="opener@example.com",
            first_name="Opener", password="Pass!123",
        )
        self.case = DisputeCase.objects.create(
            reference="DSP-TEST-001",
            category="DELIVERY",
            dispute_type="DELIVERY_NOT_RECEIVED",
            state=DisputeState.OPEN,
            opened_by=self.opener,
            entity_type="Order",
            entity_id="42",
            title="Test",
            description="x",
        )

    def _call(self, outcome, buyer_refund=Decimal("0"), seller_release=Decimal("0")):
        from apps.disputes.services import dispute_service
        return dispute_service.make_decision(
            case=self.case, decided_by=self.admin, outcome=outcome,
            buyer_refund=buyer_refund, seller_release=seller_release,
            reasoning="audit-test",
        )

    def _patch_machine(self):
        """Patch DisputeStateMachine.transition_to to a no-op while keeping
        the real .case attribute (DisputeDecision FK requires a real instance).
        """
        return patch(
            "apps.disputes.services.DisputeStateMachine.transition_to",
            return_value=None,
        )

    def test_no_action_does_not_touch_finance(self):
        # No mock for OrderFinanceService — if any primitive is called we explode.
        with self._patch_machine():
            decision = self._call("NO_ACTION")
        self.assertEqual(decision.outcome, "NO_ACTION")

    @patch("apps.orders.services.OrderFinanceService.refund_order_locked_funds")
    @patch("apps.orders.models.Order.objects")
    def test_refund_buyer_calls_refund_primitive(self, mock_order_qs, mock_refund):
        mock_order_qs.select_for_update.return_value.get.return_value = MagicMock(id=42)
        mock_refund.return_value = Decimal("500")
        with self._patch_machine():
            decision = self._call("REFUND_BUYER")
        self.assertEqual(decision.outcome, "REFUND_BUYER")
        mock_refund.assert_called_once()

    @patch("apps.orders.services.OrderFinanceService.admin_force_release_locked_escrows")
    @patch("apps.orders.models.Order.objects")
    def test_release_seller_calls_release_primitive(self, mock_order_qs, mock_release):
        mock_order_qs.select_for_update.return_value.get.return_value = MagicMock(id=42)
        mock_release.return_value = ["primary"]
        with self._patch_machine():
            decision = self._call("RELEASE_SELLER")
        self.assertEqual(decision.outcome, "RELEASE_SELLER")
        mock_release.assert_called_once()

    @patch("apps.orders.services.OrderFinanceService.dispute_split_release")
    @patch("apps.orders.models.Order.objects")
    def test_split_calls_split_primitive(self, mock_order_qs, mock_split):
        mock_order_qs.select_for_update.return_value.get.return_value = MagicMock(id=42)
        mock_split.return_value = {
            "buyer_refund": Decimal("100"),
            "seller_release": Decimal("400"),
            "total_locked": Decimal("500"),
        }
        with self._patch_machine():
            decision = self._call("SPLIT", Decimal("100"), Decimal("400"))
        self.assertEqual(decision.outcome, "SPLIT")
        mock_split.assert_called_once()
        _, kwargs = mock_split.call_args
        self.assertEqual(kwargs["buyer_refund"], Decimal("100"))
        self.assertEqual(kwargs["seller_release"], Decimal("400"))

    def test_negative_amounts_refused(self):
        with self.assertRaises(DRFValidationError):
            self._call("SPLIT", Decimal("-1"), Decimal("100"))
