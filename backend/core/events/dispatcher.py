"""
Event dispatcher: reads pending OutboxEvents and routes to registered handlers.
Called by the Celery beat task `process_outbox_events`.
"""
from __future__ import annotations

import logging
from datetime import timedelta
from typing import Callable, Any

from django.db import transaction
from django.utils import timezone

from .models import OutboxEvent, OutboxStatus

logger = logging.getLogger(__name__)

HandlerFn = Callable[[OutboxEvent], None]

_REGISTRY: dict[str, list[HandlerFn]] = {}


def register_handler(event_type: str, handler: HandlerFn) -> None:
    _REGISTRY.setdefault(event_type, []).append(handler)


def handler(event_type: str):
    """Decorator to register an event handler."""
    def decorator(fn: HandlerFn) -> HandlerFn:
        register_handler(event_type, fn)
        return fn
    return decorator


def dispatch_pending(batch_size: int = 100) -> int:
    """
    Fetch and dispatch pending outbox events. Returns number processed.
    Called by Celery beat every N seconds.
    """
    now = timezone.now()
    events = (
        OutboxEvent.objects
        .select_for_update(skip_locked=True)
        .filter(status=OutboxStatus.PENDING, next_retry_at__lte=now)
        .order_by("created_at")[:batch_size]
    )

    processed = 0
    for event in events:
        _dispatch_single(event)
        processed += 1

    return processed


def _dispatch_single(event: OutboxEvent) -> None:
    handlers = _REGISTRY.get(event.event_type, [])
    if not handlers:
        # No handlers — mark processed (don't block the queue)
        event.status = OutboxStatus.PROCESSED
        event.processed_at = timezone.now()
        event.save(update_fields=["status", "processed_at"])
        return

    try:
        with transaction.atomic():
            event.status = OutboxStatus.PROCESSING
            event.save(update_fields=["status"])

        for h in handlers:
            try:
                h(event)
            except Exception as exc:
                logger.error(
                    "event_handler_error",
                    extra={"event_type": event.event_type, "handler": h.__name__, "error": str(exc)},
                    exc_info=True,
                )
                raise

        event.status = OutboxStatus.PROCESSED
        event.processed_at = timezone.now()
        event.save(update_fields=["status", "processed_at"])

    except Exception as exc:
        event.retry_count += 1
        event.error_message = str(exc)[:500]
        if event.retry_count >= event.max_retries:
            event.status = OutboxStatus.DEAD
        else:
            event.status = OutboxStatus.PENDING
            delay = min(2 ** event.retry_count * 30, 3600)  # exponential backoff, max 1h
            event.next_retry_at = timezone.now() + timedelta(seconds=delay)
        event.save(update_fields=["status", "retry_count", "error_message", "next_retry_at"])
