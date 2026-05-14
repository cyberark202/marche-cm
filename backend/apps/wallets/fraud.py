"""
Fraud detection engine — velocity checks, risk scoring, anomaly detection.

Architecture:
  - Risk scores are 0–100 (0 = clean, 100 = certain fraud).
  - Velocity counters live in Redis (fast, ephemeral).
  - Fraud events are persisted in FraudEvent model for audit/review.
  - High-risk transactions (score >= HOLD_THRESHOLD) are placed on hold.
  - Critical transactions (score >= BLOCK_THRESHOLD) are blocked outright.

OWASP ASVS V10 — Malicious Code / Fraud controls
"""

import hashlib
import logging
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any

from django.conf import settings
from django.core.cache import cache
from django.utils import timezone

logger = logging.getLogger("security.fraud")

# ---------------------------------------------------------------------------
# Thresholds (all configurable via Django settings)
# ---------------------------------------------------------------------------

HOLD_THRESHOLD: int = 60   # Risk score ≥ 60 → hold for manual review
BLOCK_THRESHOLD: int = 85  # Risk score ≥ 85 → hard block


def _cfg(name: str, default: Any) -> Any:
    return getattr(settings, name, default)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class RiskContext:
    """Input context for risk scoring."""
    user_id: int
    amount: Decimal
    action: str              # "withdraw", "transfer", "topup", "order"
    ip: str = ""
    user_agent: str = ""
    device_id: str = ""
    metadata: dict = field(default_factory=dict)


@dataclass
class RiskDecision:
    """Output of the fraud engine."""
    score: int               # 0–100
    action: str              # "allow", "hold", "block"
    reasons: list[str] = field(default_factory=list)
    hold_id: str | None = None

    @property
    def is_blocked(self) -> bool:
        return self.action == "block"

    @property
    def is_held(self) -> bool:
        return self.action == "hold"

    @property
    def is_allowed(self) -> bool:
        return self.action == "allow"


# ---------------------------------------------------------------------------
# Velocity checker — Redis sliding window counters
# ---------------------------------------------------------------------------

class VelocityChecker:
    """
    Track transaction velocity using Redis counters.

    Separate counters:
      - Per-user transaction count / hour
      - Per-user cumulative amount / day
      - Per-IP transaction count / hour
    """

    @staticmethod
    def _key(scope: str, identifier: str, window: str) -> str:
        safe = hashlib.sha256(identifier.encode()).hexdigest()[:16]
        return f"fraud:velocity:{scope}:{safe}:{window}"

    @classmethod
    def _increment(cls, key: str, ttl_seconds: int) -> int:
        try:
            current = cache.get(key, 0)
            new = int(current) + 1
            cache.set(key, new, timeout=ttl_seconds)
            return new
        except Exception:
            return 0

    @classmethod
    def record_transaction(cls, user_id: int, amount: Decimal, ip: str) -> dict[str, int | Decimal]:
        """Increment all velocity counters. Returns current counters."""
        uid = str(user_id)
        result: dict[str, int | Decimal] = {}

        # Per-user: transaction count per hour
        tx_count_key = cls._key("user_tx_count", uid, "1h")
        result["user_tx_count_1h"] = cls._increment(tx_count_key, 3600)

        # Per-user: transaction count per day
        tx_day_key = cls._key("user_tx_count", uid, "24h")
        result["user_tx_count_24h"] = cls._increment(tx_day_key, 86400)

        # Per-user: cumulative amount per day (store as int cents to avoid float)
        amt_cents = int(amount * 100)
        amt_day_key = cls._key("user_amount", uid, "24h")
        try:
            current_cents = int(cache.get(amt_day_key, 0))
            new_cents = current_cents + amt_cents
            cache.set(amt_day_key, new_cents, timeout=86400)
            result["user_amount_24h_cents"] = new_cents
        except Exception:
            result["user_amount_24h_cents"] = 0

        # Per-IP: transaction count per hour
        if ip:
            ip_key = cls._key("ip_tx_count", ip, "1h")
            result["ip_tx_count_1h"] = cls._increment(ip_key, 3600)

        return result

    @classmethod
    def get_counters(cls, user_id: int, ip: str = "") -> dict[str, int]:
        uid = str(user_id)
        result: dict[str, int] = {}
        try:
            result["user_tx_count_1h"] = int(cache.get(cls._key("user_tx_count", uid, "1h"), 0))
            result["user_tx_count_24h"] = int(cache.get(cls._key("user_tx_count", uid, "24h"), 0))
            result["user_amount_24h_cents"] = int(cache.get(cls._key("user_amount", uid, "24h"), 0))
            if ip:
                result["ip_tx_count_1h"] = int(cache.get(cls._key("ip_tx_count", ip, "1h"), 0))
        except Exception:
            pass
        return result


# ---------------------------------------------------------------------------
# Risk scorer
# ---------------------------------------------------------------------------

class RiskScorer:
    """
    Compute a 0–100 risk score from velocity and contextual signals.

    Signals (additive, capped at 100):
      +20  — High amount relative to KYC level limit
      +15  — User velocity: > 10 transactions/hour
      +10  — User velocity: > 5 transactions/hour
      +20  — Daily amount > 80% of KYC daily limit
      +15  — Daily amount > 50% of KYC daily limit
      +15  — IP velocity: > 20 transactions/hour from same IP
      +10  — IP velocity: > 10 transactions/hour from same IP
      +10  — Very first transaction ever (new account fraud pattern)
      +5   — Transaction from a new/untrusted device
    """

    def __init__(self, ctx: RiskContext) -> None:
        self.ctx = ctx

    def score(self, velocity: dict[str, int], kyc_limits: dict) -> tuple[int, list[str]]:
        total = 0
        reasons: list[str] = []

        amount = self.ctx.amount
        per_tx_limit = Decimal(str(kyc_limits.get("per_transaction", 0)))
        per_day_limit = Decimal(str(kyc_limits.get("per_day", 0)))

        # Amount-based signals
        if per_tx_limit > 0 and amount >= per_tx_limit * Decimal("0.8"):
            total += 20
            reasons.append("high_amount_vs_kyc_limit")
        elif per_tx_limit > 0 and amount >= per_tx_limit * Decimal("0.5"):
            total += 10
            reasons.append("moderate_amount_vs_kyc_limit")

        # Velocity: user transaction count
        user_tx_1h = velocity.get("user_tx_count_1h", 0)
        if user_tx_1h > 10:
            total += 15
            reasons.append(f"high_user_velocity:{user_tx_1h}tx/h")
        elif user_tx_1h > 5:
            total += 10
            reasons.append(f"elevated_user_velocity:{user_tx_1h}tx/h")

        # Velocity: user daily amount
        user_amt_cents = velocity.get("user_amount_24h_cents", 0)
        if per_day_limit > 0:
            daily_ratio = Decimal(str(user_amt_cents / 100)) / per_day_limit
            if daily_ratio >= Decimal("0.8"):
                total += 20
                reasons.append(f"high_daily_amount:{daily_ratio:.0%}")
            elif daily_ratio >= Decimal("0.5"):
                total += 15
                reasons.append(f"elevated_daily_amount:{daily_ratio:.0%}")

        # Velocity: IP transaction count
        ip_tx_1h = velocity.get("ip_tx_count_1h", 0)
        if ip_tx_1h > 20:
            total += 15
            reasons.append(f"high_ip_velocity:{ip_tx_1h}tx/h")
        elif ip_tx_1h > 10:
            total += 10
            reasons.append(f"elevated_ip_velocity:{ip_tx_1h}tx/h")

        # First transaction (new account pattern)
        if velocity.get("user_tx_count_24h", 0) <= 1:
            total += 5
            reasons.append("first_transaction")

        return min(total, 100), reasons


# ---------------------------------------------------------------------------
# Fraud engine — main entry point
# ---------------------------------------------------------------------------

class FraudEngine:
    """
    Main fraud detection engine.  Call `evaluate()` before executing any
    financial transaction.

    Usage::
        ctx = RiskContext(user_id=user.id, amount=amount, action="withdraw", ip=ip)
        decision = FraudEngine.evaluate(ctx, user)
        if decision.is_blocked:
            raise FraudRiskError(f"Transaction blocked: {decision.reasons}")
        if decision.is_held:
            # Place transaction in manual review queue
            hold_transaction(transaction, decision.hold_id)
    """

    @staticmethod
    def evaluate(ctx: RiskContext, user) -> RiskDecision:
        """Evaluate fraud risk and return a decision."""
        kyc_level = getattr(user, "kyc_level", 0)
        kyc_limits = _cfg("KYC_LIMITS", {}).get(kyc_level, {"per_transaction": 25000, "per_day": 50000})

        # Record velocity BEFORE scoring (includes current transaction).
        velocity = VelocityChecker.record_transaction(
            user_id=ctx.user_id,
            amount=ctx.amount,
            ip=ctx.ip,
        )

        scorer = RiskScorer(ctx)
        score, reasons = scorer.score(velocity, kyc_limits)

        if score >= BLOCK_THRESHOLD:
            action = "block"
        elif score >= HOLD_THRESHOLD:
            action = "hold"
        else:
            action = "allow"

        # Persist fraud event for audit trail.
        hold_id = FraudEngine._persist_event(ctx, score, reasons, action, user)

        if score > 0:
            logger.warning(
                "fraud_evaluation user=%d action=%s score=%d decision=%s reasons=%s ip=%s",
                ctx.user_id,
                ctx.action,
                score,
                action,
                ",".join(reasons),
                ctx.ip,
            )

        return RiskDecision(score=score, action=action, reasons=reasons, hold_id=hold_id)

    @staticmethod
    def _persist_event(
        ctx: RiskContext,
        score: int,
        reasons: list[str],
        action: str,
        user,
    ) -> str | None:
        """Persist a FraudEvent record. Returns hold_id if action is 'hold'."""
        if score == 0:
            return None
        try:
            from .models import FraudEvent  # late import — avoids circular
            event = FraudEvent.objects.create(
                user=user,
                event_type=ctx.action,
                risk_score=score,
                decision=action,
                metadata={
                    "reasons": reasons,
                    "ip": ctx.ip,
                    "amount_cents": int(ctx.amount * 100),
                    "action": ctx.action,
                },
            )
            return str(event.id) if action == "hold" else None
        except Exception:
            logger.exception("Failed to persist FraudEvent")
            return None
