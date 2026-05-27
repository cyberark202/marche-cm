from __future__ import annotations

import logging

from django.db import transaction
from django.utils import timezone

from .models import AMLScreening, KYCApplication, KYCStatus

logger = logging.getLogger(__name__)


class ComplianceService:
    def approve_kyc(self, application: KYCApplication, reviewer) -> None:
        with transaction.atomic():
            application.status = KYCStatus.APPROVED
            application.reviewed_at = timezone.now()
            application.reviewed_by = reviewer
            application.save(update_fields=["status", "reviewed_at", "reviewed_by_id", "updated_at"])
            user = application.user
            user.kyc_level = application.target_level
            user.is_verified = True
            user.save(update_fields=["kyc_level", "is_verified"])
        logger.info(
            "kyc_approved",
            extra={"user_id": application.user_id, "level": application.target_level},
        )

    def reject_kyc(self, application: KYCApplication, reviewer, reason: str) -> None:
        application.status = KYCStatus.REJECTED
        application.reviewed_at = timezone.now()
        application.reviewed_by = reviewer
        application.rejection_reason = reason
        application.save(
            update_fields=["status", "reviewed_at", "reviewed_by_id", "rejection_reason", "updated_at"]
        )
        logger.info(
            "kyc_rejected",
            extra={"user_id": application.user_id, "reason": reason},
        )

    def run_aml_screening(
        self,
        user,
        screening_type: str = "ONBOARDING",
        entity_type: str = "",
        entity_id: str = "",
    ) -> AMLScreening:
        from .models import SanctionsList

        name = getattr(user, "get_full_name", lambda: "")() or getattr(user, "username", "")
        hits = list(
            SanctionsList.objects.filter(
                full_name__icontains=name.split()[0] if name else "",
                is_active=True,
            ).values("list_name", "full_name", "reference_id")[:5]
        )
        result = "HIT" if hits else "CLEAR"
        screening = AMLScreening.objects.create(
            user=user,
            screening_type=screening_type,
            entity_type=entity_type,
            entity_id=entity_id,
            result=result,
            hits=hits,
        )
        logger.info(
            "aml_screening",
            extra={"user_id": user.pk, "result": result, "hits": len(hits)},
        )
        return screening


compliance_service = ComplianceService()
