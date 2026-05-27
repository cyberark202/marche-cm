"""
Structured logging utilities.
All log calls should use extra={} for structured fields.
"""
from __future__ import annotations

import logging
import threading
import uuid

logger = logging.getLogger(__name__)

_correlation_id_local = threading.local()


def set_correlation_id(correlation_id: str) -> None:
    _correlation_id_local.value = correlation_id


def get_correlation_id() -> str:
    return getattr(_correlation_id_local, "value", "")


def generate_correlation_id() -> str:
    cid = str(uuid.uuid4())
    set_correlation_id(cid)
    return cid


class CorrelationIDFilter(logging.Filter):
    """Injects correlation_id into every log record."""
    def filter(self, record: logging.LogRecord) -> bool:
        record.correlation_id = get_correlation_id()
        return True
