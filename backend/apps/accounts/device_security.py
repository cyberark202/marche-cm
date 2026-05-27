"""
Device fingerprinting, JWT device binding, and trusted device management.

Architecture:
  - Device fingerprint = HMAC-SHA256(secret, ip + ua + device_id)
  - Fingerprint is embedded in JWT as 'dfp' claim.
  - On every request: fingerprint is re-computed and compared in constant time.
  - IP changes are tolerated (mobile networks); only hard-fails on UA + device_id change.

OWASP ASVS V3.5 — Token-Based Sessions
"""

import hashlib
import hmac
import logging
from typing import Any

from django.conf import settings
from django.utils import timezone

logger = logging.getLogger("security.device")

# ---------------------------------------------------------------------------
# Device fingerprint
# ---------------------------------------------------------------------------

_FINGERPRINT_SECRET_ATTR = "DEVICE_FINGERPRINT_SECRET"


def _fingerprint_secret() -> bytes:
    """
    Per-installation HMAC secret for fingerprint generation.
    Falls back to a derivative of SECRET_KEY if not explicitly set.
    Never use plaintext SECRET_KEY directly — always derive it.
    """
    explicit = getattr(settings, _FINGERPRINT_SECRET_ATTR, "").strip()
    if explicit:
        return explicit.encode()
    # Derive from SECRET_KEY with domain separation — safe but suboptimal.
    # Operators SHOULD set DEVICE_FINGERPRINT_SECRET explicitly.
    sk = getattr(settings, "SECRET_KEY", "").encode()
    return hashlib.sha256(b"device-fingerprint:" + sk).digest()


class DeviceFingerprint:
    """
    Generates a stable, unforgeable device fingerprint from request metadata.

    The fingerprint binds a JWT to the device that requested it, detecting
    token theft when the device context changes significantly.

    Design choices:
      - IP address is NOT included in the fingerprint — mobile users change IPs
        frequently.  IP change is logged separately but not hard-enforced.
      - User-Agent IS included — changes rarely for legitimate users, commonly
        for stolen tokens being used in different environments.
      - X-Device-ID (client-generated stable UUID, stored in secure storage)
        is included when provided.
    """

    def __init__(self, user_agent: str, device_id: str = "") -> None:
        self.user_agent = (user_agent or "")[:512]
        self.device_id = (device_id or "")[:128]

    @classmethod
    def from_request(cls, request) -> "DeviceFingerprint":
        ua = request.META.get("HTTP_USER_AGENT", "")
        device_id = request.META.get("HTTP_X_DEVICE_ID", "")
        return cls(user_agent=ua, device_id=device_id)

    def compute(self) -> str:
        """Return hex fingerprint (SHA-256 HMAC, first 32 hex chars = 128 bits)."""
        secret = _fingerprint_secret()
        payload = f"{self.user_agent}|{self.device_id}".encode()
        digest = hmac.new(secret, payload, hashlib.sha256).hexdigest()
        return digest[:32]

    def matches(self, stored_fingerprint: str) -> bool:
        """Constant-time comparison to prevent timing attacks."""
        computed = self.compute()
        if not stored_fingerprint:
            return True  # No fingerprint stored — first request after migration
        return hmac.compare_digest(computed, stored_fingerprint)


# ---------------------------------------------------------------------------
# JWT device binding via custom SimpleJWT token class
# ---------------------------------------------------------------------------

def enrich_token_payload(token_payload: dict, request) -> dict:
    """
    Add device fingerprint claim to a JWT payload.

    Call this when issuing a new access or refresh token.
    """
    fingerprint = DeviceFingerprint.from_request(request).compute()
    token_payload["dfp"] = fingerprint
    return token_payload


def validate_token_device(token_payload: dict, request) -> bool:
    """
    Verify that the current request's device fingerprint matches the token's.

    Returns True if:
      - No 'dfp' claim present (token pre-dates device binding; soft-pass).
      - Fingerprint matches.
    Returns False if fingerprint mismatch detected.
    """
    stored_dfp = token_payload.get("dfp", "")
    if not stored_dfp:
        # Pre-migration token — log but allow. Force re-login after expiry.
        return True

    current = DeviceFingerprint.from_request(request).compute()
    match = hmac.compare_digest(current, stored_dfp)

    if not match:
        logger.warning(
            "device_fingerprint_mismatch user=%s jti=%s",
            token_payload.get("user_id", "?"),
            token_payload.get("jti", "?"),
        )

    return match


# ---------------------------------------------------------------------------
# Trusted device model helpers (uses TrustedDevice model defined in models.py)
# ---------------------------------------------------------------------------

def register_device_if_new(user, request) -> bool:
    """
    Register the device from *request* as a known device for *user*.

    Returns True if this is a new (previously unseen) device.
    """
    from .models import TrustedDevice

    fingerprint = DeviceFingerprint.from_request(request).compute()
    ip = _client_ip(request)
    ua = request.META.get("HTTP_USER_AGENT", "")[:512]
    ua_hash = hashlib.sha256(ua.encode()).hexdigest()[:32]

    obj, created = TrustedDevice.objects.get_or_create(
        user=user,
        device_fingerprint=fingerprint,
        defaults={
            "user_agent_hash": ua_hash,
            "ip_address_last": ip,
            "is_trusted": False,
        },
    )

    if not created:
        TrustedDevice.objects.filter(pk=obj.pk).update(
            last_seen_at=timezone.now(),
            ip_address_last=ip,
        )

    return created


def _client_ip(request) -> str:
    # Audit ref: [N-005] route every call site through the canonical helper
    # that honours settings.TRUSTED_PROXIES. Keeping a thin wrapper here
    # avoids breaking the public symbol used by accounts.security/middleware.
    from config.middleware import _client_ip as _canonical_client_ip
    return _canonical_client_ip(request)
