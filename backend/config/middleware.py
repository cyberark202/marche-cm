"""
Security middleware stack — production-grade fintech hardening.

Layer order in settings.MIDDLEWARE (position matters):
  1. CorrelationIDMiddleware          — earliest: injects trace ID into every request
  2. SecurityHeadersMiddleware        — CSP, HSTS, security headers (after SecurityMiddleware)
  3. RequestSizeLimitMiddleware       — block oversized requests before they hit DRF
  4. SuspiciousRequestMiddleware      — anomaly detection, geo checks, fingerprinting

OWASP ASVS alignment:
  V7.1  — Logging (correlation IDs)
  V14.4 — HTTP Security Headers
  V4.2  — Access control (suspicious activity blocking)
  V1.14 — Configuration security
"""

import hashlib
import hmac
import ipaddress
import logging
import secrets
import time
from typing import Callable

from django.conf import settings
from django.core.cache import cache
from django.http import HttpRequest, HttpResponse, JsonResponse

logger = logging.getLogger("security")
security_event_logger = logging.getLogger("security.events")


# ---------------------------------------------------------------------------
# Correlation ID — OWASP ASVS V7.1.3
# ---------------------------------------------------------------------------

CORRELATION_HEADER = "X-Correlation-ID"
CORRELATION_REQUEST_ATTR = "_correlation_id"
_ID_CHARS = "0123456789abcdefghijklmnopqrstuvwxyz"


class CorrelationIDMiddleware:
    """
    Injects a per-request correlation ID for end-to-end log tracing.

    If the upstream proxy sends X-Correlation-ID, it is validated and
    forwarded. Otherwise a cryptographically random ID is generated.
    """

    def __init__(self, get_response: Callable) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        upstream = (request.META.get("HTTP_X_CORRELATION_ID") or "").strip()
        # Validate upstream IDs strictly — reject anything that could be injected.
        if upstream and len(upstream) <= 64 and upstream.replace("-", "").replace("_", "").isalnum():
            correlation_id = upstream[:64]
        else:
            correlation_id = secrets.token_hex(16)

        setattr(request, CORRELATION_REQUEST_ATTR, correlation_id)
        t_start = time.monotonic()
        resp = self.get_response(request)
        elapsed_ms = int((time.monotonic() - t_start) * 1000)

        resp[CORRELATION_HEADER] = correlation_id
        # Phase 6 — observability: response time visible to mobile clients and
        # reverse proxies so they can surface latency without server-side APM.
        resp["X-Response-Time"] = f"{elapsed_ms}ms"

        # Slow-request detection: log any API call exceeding the threshold.
        _slow_ms = getattr(settings, "SLOW_REQUEST_THRESHOLD_MS", 3000)
        if elapsed_ms >= _slow_ms:
            path = request.path
            method = request.method
            logger.warning(
                "slow_request method=%s path=%s elapsed_ms=%d correlation_id=%s",
                method,
                path,
                elapsed_ms,
                correlation_id,
            )

        return resp


def get_correlation_id(request: HttpRequest) -> str:
    return getattr(request, CORRELATION_REQUEST_ATTR, "unknown")


# ---------------------------------------------------------------------------
# Security Headers — OWASP ASVS V14.4
# ---------------------------------------------------------------------------

_CSP_DIRECTIVES = {
    "default-src": "'none'",
    "script-src": "'self'",
    "style-src": "'self'",
    "img-src": "'self' data: blob:",
    "font-src": "'self'",
    "connect-src": "'self'",
    "media-src": "'self'",
    "object-src": "'none'",
    "base-uri": "'self'",
    "form-action": "'self'",
    "frame-ancestors": "'none'",
    "upgrade-insecure-requests": "",
}


def _build_csp() -> str:
    parts = []
    for directive, value in _CSP_DIRECTIVES.items():
        parts.append(f"{directive} {value}".strip())
    return "; ".join(parts)


class SecurityHeadersMiddleware:
    """
    Injects production security headers on every response.

    Django's SecurityMiddleware handles HSTS and X-Frame-Options already;
    this middleware adds the remaining OWASP-recommended headers.
    """

    # API responses are JSON — no need for browser XSS protections on /api/.
    # But headers don't hurt and help if the API is ever embedded in a web view.
    _SECURITY_HEADERS = {
        "X-Content-Type-Options": "nosniff",
        "X-Permitted-Cross-Domain-Policies": "none",
        "Referrer-Policy": "strict-origin-when-cross-origin",
        "Permissions-Policy": (
            "camera=(), microphone=(), geolocation=(self), "
            "payment=(), usb=(), interest-cohort=()"
        ),
        # Cross-Origin policies — defense against Spectre and similar.
        "Cross-Origin-Embedder-Policy": "require-corp",
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Resource-Policy": "same-origin",
    }

    def __init__(self, get_response: Callable) -> None:
        self.get_response = get_response
        self._csp = _build_csp()
        # Override via environment if needed (e.g. to add CDN hashes).
        env_csp = getattr(settings, "CONTENT_SECURITY_POLICY", "").strip()
        if env_csp:
            self._csp = env_csp

    def __call__(self, request: HttpRequest) -> HttpResponse:
        response = self.get_response(request)
        self._apply(response)
        return response

    def _apply(self, response: HttpResponse) -> None:
        for header, value in self._SECURITY_HEADERS.items():
            if header not in response:
                response[header] = value
        if "Content-Security-Policy" not in response:
            response["Content-Security-Policy"] = self._csp
        # Remove server fingerprinting headers added by some middleware/servers.
        for _hdr in ("Server", "X-Powered-By"):
            if _hdr in response:
                del response[_hdr]


# ---------------------------------------------------------------------------
# Request size limiting — anti-DoS, anti-file-bomb
# ---------------------------------------------------------------------------

_DEFAULT_MAX_BODY_BYTES = 50 * 1024 * 1024  # 50 MB overall limit
_UPLOAD_PATH_PREFIXES = ("/api/compliance/", "/api/catalog/", "/api/wallets/")


class RequestSizeLimitMiddleware:
    """
    Rejects requests whose Content-Length exceeds per-path size limits before
    the body is read.  This prevents DoS via resource exhaustion on file uploads.
    """

    def __init__(self, get_response: Callable) -> None:
        self.get_response = get_response
        self._global_max = getattr(settings, "REQUEST_MAX_BODY_BYTES", _DEFAULT_MAX_BODY_BYTES)

    def __call__(self, request: HttpRequest) -> HttpResponse:
        content_length = self._parse_content_length(request)
        if content_length is not None and content_length > self._max_bytes(request):
            cid = get_correlation_id(request)
            security_event_logger.warning(
                "oversized_request path=%s content_length=%d max=%d ip=%s cid=%s",
                request.path,
                content_length,
                self._max_bytes(request),
                _client_ip(request),
                cid,
            )
            return JsonResponse(
                {"detail": "Request trop grande. Reduisez la taille du fichier."},
                status=413,
            )
        return self.get_response(request)

    @staticmethod
    def _parse_content_length(request: HttpRequest) -> int | None:
        raw = request.META.get("CONTENT_LENGTH", "").strip()
        try:
            value = int(raw)
            return value if value >= 0 else None
        except (ValueError, TypeError):
            return None

    def _max_bytes(self, request: HttpRequest) -> int:
        upload_max_mb = getattr(settings, "MAX_UPLOAD_IMAGE_MB", 5)
        for prefix in _UPLOAD_PATH_PREFIXES:
            if request.path.startswith(prefix):
                return upload_max_mb * 1024 * 1024
        return self._global_max


# ---------------------------------------------------------------------------
# Suspicious request detection — OWASP ASVS V4.2, V7.3
# ---------------------------------------------------------------------------

# Patterns that are almost certainly attack probes, never legitimate API calls.
_ATTACK_PATH_PATTERNS = (
    "/.git/",
    "/.env",
    "/wp-admin",
    "/wp-login",
    "/phpinfo",
    "/actuator",
    "/console",
    "/../",
    "/etc/passwd",
    "/proc/self",
    "/.aws/",
    "/.ssh/",
)

# Headers commonly injected by scanners/bots.
_ATTACK_HEADER_PATTERNS = (
    "sqlmap",
    "nikto",
    "nessus",
    "masscan",
    "zgrab",
    "wpscan",
)


class SuspiciousRequestMiddleware:
    """
    Detects and logs/blocks known attack patterns, path traversal attempts,
    scanner signatures, and IP-based anomalies.

    Does NOT block by default — it logs and optionally increments a suspicion
    counter in Redis. Hard-blocking is done at the WAF/Nginx layer.
    """

    def __init__(self, get_response: Callable) -> None:
        self.get_response = get_response
        self._hard_block = getattr(settings, "SECURITY_HARD_BLOCK_SCANNERS", not settings.DEBUG)

    def __call__(self, request: HttpRequest) -> HttpResponse:
        cid = get_correlation_id(request)
        ip = _client_ip(request)

        suspicion = self._score_request(request)
        if suspicion > 0:
            security_event_logger.warning(
                "suspicious_request score=%d path=%s method=%s ip=%s ua=%s cid=%s",
                suspicion,
                request.path,
                request.method,
                ip,
                request.META.get("HTTP_USER_AGENT", "")[:200],
                cid,
            )
            self._increment_suspicion_counter(ip, suspicion)

            if self._hard_block and suspicion >= 10:
                return JsonResponse({"detail": "Requete rejetee."}, status=400)

        response = self.get_response(request)
        return response

    def _score_request(self, request: HttpRequest) -> int:
        score = 0
        path = request.path.lower()
        ua = request.META.get("HTTP_USER_AGENT", "").lower()

        # Path traversal / known attack paths
        for pattern in _ATTACK_PATH_PATTERNS:
            if pattern in path:
                score += 10
                break

        # Scanner signatures in User-Agent
        for scanner in _ATTACK_HEADER_PATTERNS:
            if scanner in ua:
                score += 10
                break

        # Missing User-Agent on non-health paths (automated scanners often omit it)
        if not ua and not path.startswith("/api/health"):
            score += 3

        # Excessively long path (path traversal / fuzzing)
        if len(request.path) > 512:
            score += 5

        # Null bytes in any header (injection attempt)
        for key, value in request.META.items():
            if key.startswith("HTTP_") and "\x00" in str(value):
                score += 10
                break

        return score

    @staticmethod
    def _increment_suspicion_counter(ip: str, score: int) -> None:
        cache_key = f"sec:suspicion:{hashlib.sha256(ip.encode()).hexdigest()[:16]}"
        try:
            current = cache.get(cache_key, 0)
            cache.set(cache_key, current + score, timeout=3600)
        except Exception:
            pass  # Never fail a request due to cache errors


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_TRUSTED_PROXY_HEADERS = ("HTTP_X_FORWARDED_FOR", "HTTP_X_REAL_IP")


def _client_ip(request: HttpRequest) -> str:
    """
    Extract the real client IP, respecting X-Forwarded-For set by trusted proxies.

    We only trust the LEFTMOST address in XFF (the originating client).
    Rightmost addresses are added by each proxy hop and can be forged.
    """
    xff = request.META.get("HTTP_X_FORWARDED_FOR", "").strip()
    if xff:
        candidate = xff.split(",")[0].strip()
        try:
            ipaddress.ip_address(candidate)
            return candidate
        except ValueError:
            pass
    real_ip = request.META.get("HTTP_X_REAL_IP", "").strip()
    if real_ip:
        try:
            ipaddress.ip_address(real_ip)
            return real_ip
        except ValueError:
            pass
    return request.META.get("REMOTE_ADDR", "0.0.0.0")
