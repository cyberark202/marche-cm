"""
DRF exception handler — sanitizes error responses to prevent information leakage.

OWASP ASVS V7.4 — Error handling must not expose stack traces, internal paths,
database errors, or other implementation details to clients.

Rules:
  - 5xx errors → generic message, full details logged server-side only.
  - 4xx errors from DRF → pass through (they are intentional user-facing messages).
  - Unhandled exceptions → 500 with opaque ID the operator can correlate in logs.
"""

import logging
import traceback
import uuid

from django.conf import settings
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler

logger = logging.getLogger("security.exceptions")


def security_exception_handler(exc, context):
    """
    Custom DRF exception handler.

    1. Let DRF handle known API exceptions (ValidationError, NotFound, etc.).
    2. For unhandled exceptions: log the full traceback, return an opaque 500.
    3. Never include stack traces, file paths, or SQL in the response body.
    """
    # First, let DRF handle it normally.
    response = exception_handler(exc, context)

    if response is not None:
        # DRF handled it — add correlation ID and return.
        request = context.get("request")
        if request is not None:
            from config.middleware import get_correlation_id
            response["X-Error-ID"] = get_correlation_id(request)
        return response

    # Unhandled exception — log fully, respond with opaque error.
    error_id = str(uuid.uuid4())
    request = context.get("request")
    view = context.get("view")

    logger.error(
        "unhandled_exception error_id=%s path=%s method=%s view=%s\n%s",
        error_id,
        getattr(request, "path", "?"),
        getattr(request, "method", "?"),
        view.__class__.__name__ if view else "?",
        traceback.format_exc(),
    )

    # In debug mode, include the exception type (not the message) for developers.
    detail = (
        f"Erreur interne ({type(exc).__name__})"
        if settings.DEBUG
        else "Une erreur interne est survenue."
    )

    response = Response(
        {"detail": detail, "error_id": error_id},
        status=status.HTTP_500_INTERNAL_SERVER_ERROR,
    )
    response["X-Error-ID"] = error_id
    return response
