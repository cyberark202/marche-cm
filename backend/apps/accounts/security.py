"""
Security utilities: audit logging, sensitive action challenges, role checks.

OWASP ASVS alignment:
  V7  — Logging: no PII/secrets in audit metadata (sanitize_audit_metadata)
  V2  — Authentication: PBKDF2-hashed OTP verification (check_password)
  V4  — Access control: role → action permission map (has_action_permission)
"""

import logging
import re
from typing import Any

from django.conf import settings
from django.contrib.auth.hashers import check_password
from django.utils import timezone

from .models import AuditLog, SensitiveActionChallenge, UserRole

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Role → allowed action map (deny-by-default: unlisted actions are forbidden)
# ---------------------------------------------------------------------------

_DISPUTE_PARTICIPANT_ACTIONS = {
    "logistics.dispute.open",
    "dispute.appeal",
    "dispute.evidence.add",
}

_WALLET_ACTIONS = {
    "wallet.topup",
    "wallet.withdraw",
    "wallet.transfer",
}

_CHAT_ACTIONS = {
    "chat.send",
    "chat.read",
}

ROLE_ACTIONS = {
    UserRole.GENERAL_ADMIN: {
        "admin.dashboard.view",
        "admin.users.manage",
        "admin.disputes.decide",
        "admin.dispute.appeal.resolve",
        "admin.dispute.inspect.request",
        "admin.dispute.inspection.upload",
        "admin.guarantee_fund.activate",
        "compliance.review",
        "wallet.reconcile",
        "wallet.reconcile.daily",
        "wallet.webhook.manage",
        "audit.export",
    },
    UserRole.BUYER: (
        _WALLET_ACTIONS | _CHAT_ACTIONS | _DISPUTE_PARTICIPANT_ACTIONS
    ),
    UserRole.SUPPLIER: (
        _WALLET_ACTIONS | _CHAT_ACTIONS | _DISPUTE_PARTICIPANT_ACTIONS
    ),
    UserRole.WHOLESALER: (
        _WALLET_ACTIONS | _CHAT_ACTIONS | _DISPUTE_PARTICIPANT_ACTIONS
    ),
    UserRole.TRANSIT_AGENT: (
        _WALLET_ACTIONS | _CHAT_ACTIONS | _DISPUTE_PARTICIPANT_ACTIONS | {"custody.log"}
    ),
}

SENSITIVE_ACTIONS_REQUIRING_2FA = {
    "wallet.withdraw",
    "wallet.reconcile",
    "profile.update",
    "auth.password.change",
    "auth.email.change",
    "auth.phone.change",
}

# ---------------------------------------------------------------------------
# Audit log PII sanitizer
# OWASP ASVS V7.1.1 — Logs must not contain PII or authentication secrets.
# ---------------------------------------------------------------------------

# Exact field names and substrings that identify PII / secret data.
# Any metadata key matching one of these patterns will be STRIPPED before
# the audit entry is persisted.  Callers must use user_id / reference_code
# instead of raw PII values.
_PII_BLOCKED_PATTERNS: frozenset[str] = frozenset({
    # Identity / contact
    "phone", "phone_number", "telephone", "mobile",
    "email", "mail", "address",
    # Credentials / secrets
    "password", "passwd", "pwd",
    "pin", "wallet_pin",
    "otp", "code", "verification_code",
    "token", "secret", "key", "api_key",
    # Financial PII
    "card_number", "iban", "bban", "cvv", "account_number",
    # Identity documents
    "national_id", "id_card", "passport", "cni",
    "kyc", "document", "tax_cert", "rccm", "insurance",
    # Location (high-precision)
    "latitude", "longitude", "gps", "coordinates",
})


def _is_pii_key(key: str) -> bool:
    """Return True if *key* resembles a PII or secret field name."""
    normalized = key.lower().strip()
    # Exact match
    if normalized in _PII_BLOCKED_PATTERNS:
        return True
    # Substring match for compound names (e.g. "user_phone_number", "new_email")
    return any(pattern in normalized for pattern in _PII_BLOCKED_PATTERNS)


def sanitize_audit_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
    """
    Strip PII and secrets from *metadata* before audit log persistence.

    This is a defense-in-depth measure: callers must not pass PII, but this
    sanitizer ensures no sensitive data leaks even if they accidentally do.

    Recursively processes nested dicts.  Lists are left as-is (values inside
    lists are not individually inspected).

    Usage::

        safe = sanitize_audit_metadata({"user_id": 42, "phone": "..."})
        # → {"user_id": 42}  — phone was stripped and a warning was logged
    """
    if not isinstance(metadata, dict):
        return {}

    sanitized: dict[str, Any] = {}
    for key, value in metadata.items():
        if _is_pii_key(str(key)):
            # Alert developers: the call site should be fixed to never pass PII.
            logger.warning(
                "[security.sanitize] Blocked PII field '%s' from audit log. "
                "Fix the call site — pass identifiers (user_id, reference_code) instead.",
                key,
            )
            continue
        sanitized[key] = sanitize_audit_metadata(value) if isinstance(value, dict) else value

    return sanitized


# ---------------------------------------------------------------------------
# Core security helpers
# ---------------------------------------------------------------------------

def has_action_permission(user, action_key: str) -> bool:
    """Return True iff *user* is authorized to perform *action_key*."""
    if not user or not user.is_authenticated:
        return False
    if user.is_superuser:
        return True
    return action_key in ROLE_ACTIONS.get(user.role, set())


def write_audit_log(
    *,
    actor,
    action: str,
    action_key: str = "",
    metadata: dict[str, Any] | None = None,
) -> None:
    """
    Persist an audit log entry.

    Metadata is automatically sanitized through *sanitize_audit_metadata*
    before writing, ensuring no PII or secrets ever reach the audit table.
    Callers should use opaque identifiers (user_id, order_id, reference_code)
    rather than raw PII values.
    """
    safe_metadata = sanitize_audit_metadata(metadata or {})
    AuditLog.objects.create(
        actor=actor if getattr(actor, "is_authenticated", False) else None,
        action=action,
        action_key=action_key,
        metadata=safe_metadata,
    )


def is_sensitive_action_2fa_required(action_key: str) -> bool:
    """Return True iff 2FA is globally enabled and required for *action_key*."""
    return bool(settings.SENSITIVE_ACTION_2FA_ENABLED and action_key in SENSITIVE_ACTIONS_REQUIRING_2FA)


def verify_sensitive_action_challenge(
    *,
    user,
    action_key: str,
    challenge_token: str,
    verification_code: str,
) -> tuple[bool, str]:
    """
    Verify a sensitive-action OTP challenge.

    The stored ``code_hash`` is verified with Django's ``check_password``
    (PBKDF2-SHA256) — the plain OTP is never compared against stored plaintext.

    Returns (success: bool, error_message: str).
    """
    if not is_sensitive_action_2fa_required(action_key):
        return True, ""

    token = str(challenge_token or "").strip()
    code = str(verification_code or "").strip()
    if not token or not code:
        return False, "Verification supplementaire requise. Demandez puis saisissez le code de securite."

    challenge = SensitiveActionChallenge.objects.filter(
        user=user,
        action_key=action_key,
        challenge_token=token,
    ).first()
    if not challenge:
        return False, "Code de securite invalide ou expire."
    if challenge.used_at is not None:
        return False, "Ce code a deja ete utilise."
    if challenge.expires_at <= timezone.now():
        return False, "Le code de securite a expire. Demandez-en un nouveau."

    # PBKDF2 timing-safe verification — never compare plaintext OTPs.
    if not check_password(code, challenge.code_hash):
        challenge.attempts += 1
        if challenge.attempts >= max(1, settings.SENSITIVE_ACTION_CODE_MAX_ATTEMPTS):
            # Expire the challenge atomically to prevent further brute-force.
            challenge.expires_at = timezone.now()
            challenge.save(update_fields=["attempts", "expires_at"])
            return False, "Trop de tentatives. Code invalide et challenge expire."
        challenge.save(update_fields=["attempts"])
        remaining = max(0, settings.SENSITIVE_ACTION_CODE_MAX_ATTEMPTS - challenge.attempts)
        return False, f"Code de securite invalide. Tentatives restantes: {remaining}."

    # Atomically mark as used — prevents replay attacks.
    challenge.used_at = timezone.now()
    challenge.save(update_fields=["used_at"])
    return True, ""
