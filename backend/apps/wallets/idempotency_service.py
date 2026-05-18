"""
Fintech-grade idempotency service — Phase 1.

Gaps in the existing WalletTransaction-level idempotency:
  1. Race condition: two concurrent requests with the same key both pass
     wallet.transactions.filter(idempotency_key=key).first() before either
     creates the transaction.  The DB unique constraint catches the second
     as IntegrityError rather than returning a clean cached response.
  2. No request-body hash: the same key can be submitted with a different
     amount or provider — a payment fraud vector.
  3. No TTL: idempotency keys live forever in WalletTransaction.
  4. No response snapshot: the idempotent reply is recomputed from the
     transaction object, which may diverge after reconciliation.

This service adds IdempotencyRecord as a pre-check BEFORE the wallet
atomic block:
  Step 1 — SELECT FOR UPDATE on IdempotencyRecord by (key, user, endpoint).
  Step 2 — If record exists + hash matches → return cached response.
  Step 3 — If record exists + hash differs  → raise IdempotencyConflict.
  Step 4 — If expired record               → delete and treat as new.
  Step 5 — Create record with status=processing → caller proceeds.
  Step 6 — On success: caller calls complete() to snapshot the response.
  Step 7 — On failure: caller calls fail() so next retry is allowed.

The existing WalletTransaction.idempotency_key unique constraint remains
as a last-resort safety net — this service provides the correct UX on top.
"""

import hashlib
import json
import logging
from datetime import timedelta

from django.db import IntegrityError, transaction
from django.utils import timezone

logger = logging.getLogger("wallets.idempotency")

# Sensitive fields stripped from the hash so they can change across retries
# without causing a conflict (e.g. a fresh OTP code on a PIN-locked retry).
_STRIP_FROM_HASH = frozenset({"pin", "verification_code", "challenge_token"})

_DEFAULT_TTL = timedelta(hours=24)


def _hash_payload(data: dict) -> str:
    """SHA-256 of the request payload with secrets stripped."""
    sanitized = {k: v for k, v in data.items() if k not in _STRIP_FROM_HASH}
    canonical = json.dumps(sanitized, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode()).hexdigest()


class IdempotencyConflict(Exception):
    """Same key reused with a different request payload."""


class IdempotencyService:
    """
    Usage in a view action::

        record, cached = IdempotencyService.acquire(
            key=idempotency_key,
            user_id=request.user.id,
            endpoint="wallet.topup",
            payload=request.data,
        )
        if cached is not None:
            return Response(cached, status=HTTP_200_OK)
        try:
            # ... do financial work ...
            response_data = { ... }
            IdempotencyService.complete(record, response_data)
            return Response(response_data)
        except Exception:
            IdempotencyService.fail(record)
            raise
    """

    @staticmethod
    def acquire(
        *,
        key: str,
        user_id: int,
        endpoint: str,
        payload: dict,
        ttl: timedelta = _DEFAULT_TTL,
    ):
        """
        Acquire an idempotency slot.

        Returns (record | None, cached_response_dict | None).
        - record is None when key is empty (idempotency disabled for this call).
        - cached_response is not None when a valid completed record exists;
          the caller must return it immediately.

        Raises IdempotencyConflict when the same key is reused with a
        different payload (security violation — do not proceed).
        """
        from .models import IdempotencyRecord

        if not key:
            return None, None

        request_hash = _hash_payload(payload)
        now = timezone.now()
        expires_at = now + ttl

        with transaction.atomic():
            try:
                record = (
                    IdempotencyRecord.objects
                    .select_for_update(skip_locked=False)
                    .filter(key=key, user_id=user_id, endpoint=endpoint)
                    .first()
                )
            except Exception:
                # Redis/DB unavailable — degrade gracefully, skip idempotency.
                logger.exception("idempotency_service_unavailable endpoint=%s", endpoint)
                return None, None

            if record is not None:
                if record.expires_at < now:
                    # Expired record: tombstone it and proceed as a new request.
                    record.delete()
                    record = None
                elif record.request_hash != request_hash:
                    logger.warning(
                        "idempotency_conflict user=%d endpoint=%s key_prefix=%s",
                        user_id,
                        endpoint,
                        key[:8],
                    )
                    raise IdempotencyConflict(
                        "Cette cle d'idempotence a ete utilisee avec un payload different."
                    )
                elif record.status == IdempotencyRecord.STATUS_COMPLETE and record.response_snapshot:
                    # Clean idempotent replay.
                    logger.info(
                        "idempotency_replay user=%d endpoint=%s",
                        user_id,
                        endpoint,
                    )
                    return record, record.response_snapshot
                else:
                    # Still processing (concurrent request) or previous attempt
                    # failed: let this request proceed to retry.
                    return record, None

            # No record — create a new slot.
            try:
                record = IdempotencyRecord.objects.create(
                    key=key,
                    user_id=user_id,
                    endpoint=endpoint,
                    request_hash=request_hash,
                    response_snapshot=None,
                    status=IdempotencyRecord.STATUS_PROCESSING,
                    expires_at=expires_at,
                )
            except IntegrityError:
                # Lost race with a concurrent request for the exact same key.
                # Re-fetch and return the concurrent record's cached response
                # if it already completed, or return None to retry.
                record = (
                    IdempotencyRecord.objects
                    .filter(key=key, user_id=user_id, endpoint=endpoint)
                    .first()
                )
                if record and record.status == IdempotencyRecord.STATUS_COMPLETE and record.response_snapshot:
                    return record, record.response_snapshot
                return record, None

        return record, None

    @staticmethod
    def complete(record, response_data: dict) -> None:
        """
        Store the response snapshot and mark the record complete.
        Must be called after every successful financial operation.
        """
        if record is None:
            return
        try:
            record.response_snapshot = response_data
            record.status = record.STATUS_COMPLETE
            record.save(update_fields=["response_snapshot", "status"])
        except Exception:
            logger.exception("idempotency_complete_failed record_id=%s", getattr(record, "id", None))

    @staticmethod
    def fail(record) -> None:
        """
        Mark the record as failed so the next retry creates a fresh attempt.
        Must be called whenever the financial operation raises an exception.
        """
        if record is None:
            return
        try:
            record.status = record.STATUS_FAILED
            record.save(update_fields=["status"])
        except Exception:
            logger.exception("idempotency_fail_failed record_id=%s", getattr(record, "id", None))

    @staticmethod
    def cleanup_expired() -> int:
        """Delete expired records. Call periodically (e.g. from a management command)."""
        from .models import IdempotencyRecord
        deleted, _ = IdempotencyRecord.objects.filter(expires_at__lt=timezone.now()).delete()
        return deleted
