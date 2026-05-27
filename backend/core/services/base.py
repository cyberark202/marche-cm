"""
Service layer base.
Services contain ALL business logic.
- Views call services.
- Services call repositories.
- Services publish domain events via event_bus.
- No ORM access in views or serializers.
"""
from __future__ import annotations

import logging
from typing import Any

from django.db import transaction

logger = logging.getLogger(__name__)


class ServiceError(Exception):
    """Raised when a service operation fails due to a business rule violation."""
    def __init__(self, message: str, code: str = "service_error"):
        self.code = code
        super().__init__(message)


class BaseService:
    """Base service. Subclasses contain domain business logic."""

    def _with_transaction(self, fn, *args, **kwargs):
        """Convenience: run fn inside an atomic transaction."""
        with transaction.atomic():
            return fn(*args, **kwargs)
