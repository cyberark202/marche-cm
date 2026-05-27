"""
Audit Service — the single entry point for writing audit events.
Import and use audit_service in every service that performs critical operations.
"""
from __future__ import annotations

import logging
from typing import Any

from .models import AuditCategory, AuditEvent

logger = logging.getLogger(__name__)


class AuditService:
    def log(
        self,
        category: str,
        event_type: str,
        entity_type: str,
        entity_id: str | int,
        payload: dict[str, Any] | None = None,
        actor=None,
        ip_address: str | None = None,
        user_agent: str = "",
        correlation_id: str = "",
        outcome: str = "SUCCESS",
    ) -> AuditEvent:
        actor_id = getattr(actor, "pk", None) if actor else None
        actor_role = getattr(actor, "role", "") if actor else ""

        event = AuditEvent.objects.create(
            category=category,
            event_type=event_type,
            actor_id=actor_id,
            actor_role=actor_role,
            entity_type=entity_type,
            entity_id=str(entity_id),
            payload=payload or {},
            ip_address=ip_address,
            user_agent=user_agent[:500] if user_agent else "",
            correlation_id=correlation_id or "",
            outcome=outcome,
        )
        logger.info(
            "audit_event",
            extra={
                "event_type": event_type,
                "entity": f"{entity_type}/{entity_id}",
                "actor": actor_id,
                "outcome": outcome,
            },
        )
        return event

    def log_financial(self, event_type: str, entity_type: str, entity_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.FINANCIAL, event_type, entity_type, entity_id, **kwargs)

    def log_auth(self, event_type: str, entity_type: str, entity_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.AUTH, event_type, entity_type, entity_id, **kwargs)

    def log_order(self, event_type: str, order_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.ORDER, event_type, "Order", order_id, **kwargs)

    def log_escrow(self, event_type: str, escrow_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.ESCROW, event_type, "Escrow", escrow_id, **kwargs)

    def log_dispute(self, event_type: str, dispute_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.DISPUTE, event_type, "Dispute", dispute_id, **kwargs)

    def log_kyc(self, event_type: str, user_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.KYC, event_type, "User", user_id, **kwargs)

    def log_fraud(self, event_type: str, user_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.FRAUD, event_type, "User", user_id, **kwargs)

    def log_admin(self, event_type: str, entity_type: str, entity_id, **kwargs) -> AuditEvent:
        return self.log(AuditCategory.ADMIN, event_type, entity_type, entity_id, **kwargs)


audit_service = AuditService()
