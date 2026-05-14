"""
TOTP MFA — RFC 6238 compliant, zero external dependencies.

Architecture:
  - TOTP secret generated with secrets.token_bytes(20), stored encrypted.
  - Backup codes: 8 × 10-char alphanumeric codes, PBKDF2-hashed before storage.
  - Recovery: backup codes are one-time-use; each use is logged.
  - Window tolerance: ±1 period (30s step) to handle clock skew.

OWASP ASVS V2.8 — One-Time Verifiers
"""

import base64
import hashlib
import hmac
import logging
import secrets
import struct
import time
from typing import Any

from django.contrib.auth.hashers import check_password, make_password
from django.conf import settings

logger = logging.getLogger("security.mfa")

# ---------------------------------------------------------------------------
# TOTP constants (RFC 6238 / RFC 4226)
# ---------------------------------------------------------------------------

TOTP_STEP_SECONDS = 30       # Standard 30-second window
TOTP_DIGITS = 6              # 6-digit codes
TOTP_ALGORITHM = "sha1"      # HOTP uses SHA-1 by default
TOTP_WINDOW = 1              # Accept ±1 step (±30s clock skew tolerance)
TOTP_SECRET_BYTES = 20       # 160-bit secret (standard for TOTP apps)

BACKUP_CODE_COUNT = 8
BACKUP_CODE_LENGTH = 10      # 10-char alphanumeric — ~50 bits of entropy
BACKUP_CODE_CHARS = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"  # Visually unambiguous


# ---------------------------------------------------------------------------
# Core TOTP algorithm (no external deps)
# ---------------------------------------------------------------------------

def _hotp(secret_bytes: bytes, counter: int) -> int:
    """RFC 4226 HOTP implementation."""
    counter_bytes = struct.pack(">Q", counter)
    h = hmac.new(secret_bytes, counter_bytes, hashlib.sha1).digest()
    offset = h[-1] & 0x0F
    code = struct.unpack(">I", h[offset: offset + 4])[0] & 0x7FFFFFFF
    return code % (10 ** TOTP_DIGITS)


def _totp(secret_bytes: bytes, at: float | None = None) -> int:
    """RFC 6238 TOTP: HOTP with time-based counter."""
    t = int((at or time.time()) / TOTP_STEP_SECONDS)
    return _hotp(secret_bytes, t)


class TOTPService:
    """
    TOTP generation, verification, and QR provisioning URI.

    Usage::
        secret = TOTPService.generate_secret()          # generate
        uri = TOTPService.provisioning_uri(user, secret)  # for QR code
        ok = TOTPService.verify(secret_b32, user_code)    # verify
    """

    @staticmethod
    def generate_secret() -> str:
        """Generate a cryptographically secure TOTP secret (base32-encoded)."""
        raw = secrets.token_bytes(TOTP_SECRET_BYTES)
        return base64.b32encode(raw).decode("ascii")

    @staticmethod
    def provisioning_uri(username: str, secret_b32: str, issuer: str | None = None) -> str:
        """
        Generate an otpauth:// URI for QR code display.

        Compatible with Google Authenticator, Authy, 1Password, etc.
        """
        issuer = issuer or getattr(settings, "MFA_ISSUER_NAME", "Marche CM")
        # URL-encode label components
        label = f"{issuer}:{username}".replace(" ", "%20")
        params = (
            f"secret={secret_b32}"
            f"&issuer={issuer.replace(' ', '%20')}"
            f"&algorithm=SHA1"
            f"&digits={TOTP_DIGITS}"
            f"&period={TOTP_STEP_SECONDS}"
        )
        return f"otpauth://totp/{label}?{params}"

    @staticmethod
    def verify(secret_b32: str, code: str, allow_window: int = TOTP_WINDOW) -> bool:
        """
        Verify a TOTP code with clock-skew tolerance.

        Checks current step ±allow_window steps.  The caller is responsible
        for preventing code reuse (store last used step in cache).
        """
        if not secret_b32 or not code:
            return False
        code_clean = "".join(filter(str.isdigit, code))
        if len(code_clean) != TOTP_DIGITS:
            return False
        try:
            secret_bytes = base64.b32decode(secret_b32, casefold=True)
        except Exception:
            return False

        now = time.time()
        for delta in range(-allow_window, allow_window + 1):
            expected_at = now + delta * TOTP_STEP_SECONDS
            expected = _totp(secret_bytes, at=expected_at)
            # Constant-time comparison to prevent timing attacks.
            if hmac.compare_digest(f"{expected:0{TOTP_DIGITS}d}", code_clean):
                return True
        return False

    @staticmethod
    def current_code(secret_b32: str) -> str:
        """Generate the current TOTP code — for testing only, never expose via API."""
        secret_bytes = base64.b32decode(secret_b32, casefold=True)
        return f"{_totp(secret_bytes):0{TOTP_DIGITS}d}"


# ---------------------------------------------------------------------------
# Backup codes
# ---------------------------------------------------------------------------

class BackupCodeService:
    """
    Single-use emergency recovery codes — OWASP ASVS V2.10.

    Generated codes are NEVER stored in plaintext.  Each code is hashed
    with PBKDF2-SHA256 and stored as a list of hashes in UserMFAConfig.
    """

    @staticmethod
    def generate() -> list[str]:
        """Generate BACKUP_CODE_COUNT new backup codes (plaintext, for display once)."""
        return [
            "".join(secrets.choice(BACKUP_CODE_CHARS) for _ in range(BACKUP_CODE_LENGTH))
            for _ in range(BACKUP_CODE_COUNT)
        ]

    @staticmethod
    def hash_codes(plain_codes: list[str]) -> list[str]:
        """Hash a list of plaintext backup codes for storage."""
        return [make_password(code) for code in plain_codes]

    @staticmethod
    def verify_and_consume(code: str, hashed_codes: list[str]) -> tuple[bool, list[str]]:
        """
        Check whether *code* matches any stored hash.

        Returns (matched: bool, remaining_hashes: list[str]).
        The matched hash is removed from remaining_hashes (one-time use).
        """
        code_clean = code.strip().upper()
        for i, code_hash in enumerate(hashed_codes):
            if check_password(code_clean, code_hash):
                remaining = hashed_codes[:i] + hashed_codes[i + 1:]
                return True, remaining
        return False, list(hashed_codes)

    @staticmethod
    def format_for_display(codes: list[str]) -> list[str]:
        """Format codes with a hyphen in the middle for readability (display once)."""
        mid = BACKUP_CODE_LENGTH // 2
        return [f"{c[:mid]}-{c[mid:]}" for c in codes]


# ---------------------------------------------------------------------------
# Step anti-replay — prevent code reuse
# ---------------------------------------------------------------------------

def mark_totp_step_used(user_id: int, step: int) -> bool:
    """
    Mark a TOTP step as used to prevent replay attacks.

    Returns True if the step was fresh (not previously used).
    """
    from django.core.cache import cache
    key = f"mfa:used_step:{user_id}:{step}"
    if cache.get(key):
        return False  # already used
    # Keep for 2× window + tolerance to be safe.
    cache.set(key, 1, timeout=TOTP_STEP_SECONDS * (2 * TOTP_WINDOW + 1))
    return True


def get_current_totp_step() -> int:
    return int(time.time() / TOTP_STEP_SECONDS)
