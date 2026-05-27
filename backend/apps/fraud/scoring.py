"""
Fraud scoring engine — rule-based risk assessment.
Returns a FraudAssessment with score 0-100 and decision ALLOW/REVIEW/BLOCK.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from .models import (
    BlacklistEntry,
    FraudAssessment,
    FraudDecision,
    FraudSignalType,
    RiskLevel,
    UserRiskProfile,
)

logger = logging.getLogger(__name__)


@dataclass
class ScoringContext:
    user: object
    action_type: str
    amount: Decimal = Decimal("0")
    ip_address: str = ""
    device_fingerprint: str = ""
    entity_type: str = ""
    entity_id: str = ""
    correlation_id: str = ""
    metadata: dict = field(default_factory=dict)


class FraudScorer:
    BLOCK_THRESHOLD = 80
    REVIEW_THRESHOLD = 50

    def _compute_risk_level(self, score: int) -> str:
        if score <= 30:
            return RiskLevel.LOW
        elif score <= 60:
            return RiskLevel.MEDIUM
        elif score <= 80:
            return RiskLevel.HIGH
        return RiskLevel.CRITICAL

    def _compute_decision(self, score: int) -> str:
        if score >= self.BLOCK_THRESHOLD:
            return FraudDecision.BLOCK
        elif score >= self.REVIEW_THRESHOLD:
            return FraudDecision.REVIEW
        return FraudDecision.ALLOW

    def _check_blacklist(self, ctx: ScoringContext) -> list[dict]:
        signals = []
        checks = []
        if ctx.ip_address:
            checks.append(("IP", ctx.ip_address))
        if ctx.device_fingerprint:
            checks.append(("DEVICE", ctx.device_fingerprint))
        if hasattr(ctx.user, "phone_number") and ctx.user.phone_number:
            checks.append(("PHONE", str(ctx.user.phone_number)))
        if hasattr(ctx.user, "email") and ctx.user.email:
            checks.append(("EMAIL", ctx.user.email))
        for entry_type, value in checks:
            if BlacklistEntry.objects.filter(entry_type=entry_type, value=value).exists():
                signals.append({
                    "type": FraudSignalType.BLACKLISTED,
                    "weight": 90,
                    "detail": f"{entry_type} on blacklist",
                })
        return signals

    def _check_velocity(self, ctx: ScoringContext) -> list[dict]:
        signals = []
        if ctx.amount <= 0:
            return signals
        window = timezone.now() - timedelta(hours=1)
        recent_count = FraudAssessment.objects.filter(
            user=ctx.user,
            action_type=ctx.action_type,
            created_at__gte=window,
        ).count()
        if recent_count >= 10:
            signals.append({
                "type": FraudSignalType.VELOCITY,
                "weight": 40,
                "detail": f"{recent_count} actions in 1h",
            })
        elif recent_count >= 5:
            signals.append({
                "type": FraudSignalType.VELOCITY,
                "weight": 20,
                "detail": f"{recent_count} actions in 1h",
            })
        return signals

    def _check_amount_spike(self, ctx: ScoringContext) -> list[dict]:
        signals = []
        if ctx.amount <= 0:
            return signals
        avg_window = timezone.now() - timedelta(days=30)
        recent = FraudAssessment.objects.filter(
            user=ctx.user,
            action_type=ctx.action_type,
            created_at__gte=avg_window,
        ).values_list("metadata__amount", flat=True)
        amounts = [Decimal(str(a)) for a in recent if a]
        if amounts:
            avg = sum(amounts) / len(amounts)
            if ctx.amount > avg * 5:
                signals.append({
                    "type": FraudSignalType.AMOUNT_SPIKE,
                    "weight": 35,
                    "detail": f"Amount {ctx.amount} >> avg {avg:.0f}",
                })
        return signals

    def _check_kyc_level(self, ctx: ScoringContext) -> list[dict]:
        signals = []
        kyc_level = getattr(ctx.user, "kyc_level", 0)
        from django.conf import settings
        limits = getattr(settings, "KYC_LIMITS", {})
        level_limits = limits.get(kyc_level, {})
        per_tx = level_limits.get("per_transaction", 0)
        if per_tx and ctx.amount > Decimal(str(per_tx)):
            signals.append({
                "type": FraudSignalType.KYC_MISMATCH,
                "weight": 50,
                "detail": f"Amount exceeds KYC{kyc_level} limit {per_tx}",
            })
        return signals

    def _check_device(self, ctx: ScoringContext) -> list[dict]:
        signals = []
        if not ctx.device_fingerprint or not ctx.user.pk:
            return signals
        try:
            trusted = ctx.user.trusted_devices.filter(
                device_fingerprint=ctx.device_fingerprint,
                is_trusted=True,
            ).exists()
            if not trusted:
                seen = ctx.user.trusted_devices.filter(
                    device_fingerprint=ctx.device_fingerprint,
                ).exists()
                if not seen:
                    signals.append({
                        "type": FraudSignalType.DEVICE_MISMATCH,
                        "weight": 25,
                        "detail": "Unknown device",
                    })
        except Exception:
            pass
        return signals

    def assess(self, ctx: ScoringContext) -> FraudAssessment:
        signals: list[dict] = []
        signals.extend(self._check_blacklist(ctx))
        signals.extend(self._check_velocity(ctx))
        signals.extend(self._check_amount_spike(ctx))
        signals.extend(self._check_kyc_level(ctx))
        signals.extend(self._check_device(ctx))

        score = min(100, sum(s["weight"] for s in signals))
        risk_level = self._compute_risk_level(score)
        decision = self._compute_decision(score)

        assessment = FraudAssessment.objects.create(
            user=ctx.user,
            action_type=ctx.action_type,
            risk_score=score,
            risk_level=risk_level,
            decision=decision,
            signals=signals,
            entity_type=ctx.entity_type,
            entity_id=ctx.entity_id,
            correlation_id=ctx.correlation_id,
            ip_address=ctx.ip_address or None,
            device_fingerprint=ctx.device_fingerprint,
            metadata={"amount": str(ctx.amount), **ctx.metadata},
        )

        # Update rolling profile
        profile, _ = UserRiskProfile.objects.get_or_create(user=ctx.user)
        total = profile.overall_score * profile.assessment_count + score
        profile.assessment_count += 1
        profile.overall_score = int(total / profile.assessment_count)
        profile.last_assessed_at = timezone.now()
        if decision == FraudDecision.BLOCK and not profile.is_blocked:
            profile.is_blocked = True
            profile.blocked_reason = f"Auto-blocked: score={score}"
            profile.blocked_at = timezone.now()
        profile.save()

        logger.info(
            "fraud_assessment",
            extra={
                "user_id": ctx.user.pk,
                "action": ctx.action_type,
                "score": score,
                "decision": decision,
            },
        )
        return assessment


fraud_scorer = FraudScorer()
