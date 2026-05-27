"""
Audit chain integrity tasks.

Audit ref: [NEW-005, FIN-007] AuditEvent.save() computes a chain hash under
a distributed Redis lock, but falls back to a no-lock path if the lock is
unavailable. A fork in the chain is silent corruption — defeats the
non-tampering guarantee. This module ships the verifier the original audit
flagged as missing.

`verify_audit_chain_integrity` walks every (entity_type, entity_id) cohort,
recomputes the SHA-256 chain from scratch, and alerts on any mismatch.
"""
from __future__ import annotations

import hashlib
import json
import logging

from celery import shared_task
from django.db.models import Count

from .models import AuditEvent

logger = logging.getLogger(__name__)
security_logger = logging.getLogger("security")


@shared_task(
    name="apps.audit.tasks.verify_audit_chain_integrity",
    queue="default",
    max_retries=0,
)
def verify_audit_chain_integrity(*, sample_limit: int | None = None) -> dict:
    """Recompute the chain hash of every entity timeline and report drift.

    `sample_limit` restricts the number of (entity_type, entity_id) pairs
    inspected per run — handy when scheduling under a tight budget on very
    large tables. None = walk everything.
    """
    cohorts = (
        AuditEvent.objects.values("entity_type", "entity_id")
        .annotate(n=Count("id"))
        .order_by("entity_type", "entity_id")
    )
    if sample_limit:
        cohorts = cohorts[:sample_limit]

    checked = 0
    forks = 0
    mismatches: list[dict] = []

    for cohort in cohorts.iterator(chunk_size=200):
        entity_type = cohort["entity_type"]
        entity_id = cohort["entity_id"]
        events = list(
            AuditEvent.objects.filter(
                entity_type=entity_type, entity_id=entity_id,
            )
            .order_by("created_at", "id")
            .values("id", "event_type", "actor_id", "entity_id", "payload", "chain_hash")
        )
        checked += 1
        prev_hash = ""
        for evt in events:
            recomputed = _expected_chain_hash(prev_hash, evt)
            if evt["chain_hash"] != recomputed:
                forks += 1
                mismatches.append(
                    {
                        "entity_type": entity_type,
                        "entity_id": entity_id,
                        "event_id": evt["id"],
                        "stored": evt["chain_hash"],
                        "expected": recomputed,
                    }
                )
                # Only flag the FIRST divergence per cohort — everything
                # after the fork inherits the bad prev_hash.
                break
            prev_hash = evt["chain_hash"]

    summary = {"cohorts_checked": checked, "forks_detected": forks}
    if forks:
        security_logger.error(
            "audit_chain_fork_detected",
            extra={"summary": summary, "first_offenders": mismatches[:5]},
        )
    else:
        logger.info("audit_chain_verified", extra=summary)
    return summary


def _expected_chain_hash(prev_hash: str, evt: dict) -> str:
    """Mirror the formula used by AuditEvent._compute_chain_hash exactly.

    If that algorithm changes, this function MUST be updated in lock-step —
    keep both edits in the same PR so reviewers catch any drift, otherwise
    the verifier will report false forks.
    """
    raw = (
        f"{prev_hash}:"
        f"{evt['event_type']}:"
        f"{evt['actor_id']}:"
        f"{evt['entity_id']}:"
        f"{json.dumps(evt['payload'], sort_keys=True)}"
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
