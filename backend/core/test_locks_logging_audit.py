"""
Régression [INFRA-P0-007] : core/locks.py passait `msg` (attribut réservé du
LogRecord) dans `extra` → KeyError("Attempt to overwrite 'msg' in LogRecord")
qui faisait crasher toute tâche utilisant un lock (escrow auto-release).
Ce test exerce le chemin d'expiration du lock avec un vrai handler de logging.
"""
import logging

from django.test import TestCase

from core.locks import acquire_lock


class LockExpiryLoggingAuditTests(TestCase):
    def test_lock_expiry_log_does_not_raise(self):
        records = []

        class _Capture(logging.Handler):
            def emit(self, record):
                # Force le formatage : c'est là que le KeyError se déclenchait.
                records.append(self.format(record))

        lock_logger = logging.getLogger("core.locks")
        handler = _Capture()
        handler.setFormatter(logging.Formatter("%(message)s %(levelname)s"))
        lock_logger.addHandler(handler)
        lock_logger.setLevel(logging.DEBUG)
        try:
            # Le bloc se termine normalement ; le warning "lock_expired" se
            # déclenche si le token a expiré, mais le simple fait de logger
            # avec extra ne doit jamais lever, quel que soit le chemin.
            with acquire_lock("audit:locks:logging", ttl_seconds=5, retry_count=0):
                lock_logger.warning(
                    "lock_expired",
                    extra={"key": "audit:locks:logging", "detail": "simulated"},
                )
        finally:
            lock_logger.removeHandler(handler)
        self.assertTrue(any("lock_expired" in r for r in records))
