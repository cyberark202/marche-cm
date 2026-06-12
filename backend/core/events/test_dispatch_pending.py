"""
Régression [INFRA-P0-003] : dispatch_pending utilisait select_for_update hors
transaction → TransactionManagementError sur chaque batch outbox en prod
(workers Celery en autocommit). Le correctif enveloppe la réclamation du lot
dans transaction.atomic().
"""
from django.test import TestCase

from core.events.dispatcher import dispatch_pending, register_handler, _REGISTRY
from core.events.models import OutboxEvent, OutboxStatus


class DispatchPendingTransactionTests(TestCase):
    def tearDown(self):
        _REGISTRY.pop("audit.test.handled", None)

    def test_dispatch_without_handler_marks_processed(self):
        event = OutboxEvent.objects.create(event_type="audit.test.unhandled", payload={"k": "v"})
        processed = dispatch_pending()
        event.refresh_from_db()
        self.assertEqual(processed, 1)
        self.assertEqual(event.status, OutboxStatus.PROCESSED)

    def test_dispatch_with_handler_runs_in_autocommit_context(self):
        # Reproduit le contexte worker : aucun atomic() englobant côté appelant.
        seen = []
        register_handler("audit.test.handled", lambda e: seen.append(e.pk))
        event = OutboxEvent.objects.create(event_type="audit.test.handled", payload={})
        processed = dispatch_pending()
        event.refresh_from_db()
        self.assertEqual(processed, 1)
        self.assertEqual(seen, [event.pk])
        self.assertEqual(event.status, OutboxStatus.PROCESSED)

    def test_failing_handler_increments_retry(self):
        def boom(e):
            raise RuntimeError("handler failure")

        register_handler("audit.test.handled", boom)
        event = OutboxEvent.objects.create(event_type="audit.test.handled", payload={})
        dispatch_pending()
        event.refresh_from_db()
        self.assertGreaterEqual(event.retry_count, 1)
        self.assertNotEqual(event.status, OutboxStatus.PROCESSED)
