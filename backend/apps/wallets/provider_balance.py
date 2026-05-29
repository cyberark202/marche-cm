from __future__ import annotations

import json
import logging
import urllib.request
from decimal import Decimal, InvalidOperation

from django.conf import settings


logger = logging.getLogger(__name__)


def _to_decimal(value) -> Decimal | None:
    if value in {None, ""}:
        return None
    try:
        return Decimal(str(value)).quantize(Decimal("0.01"))
    except (InvalidOperation, TypeError):
        return None


def _extract_by_path(payload: dict, path: str):
    if not path:
        return None
    cursor = payload
    for key in path.split("."):
        if isinstance(cursor, dict) and key in cursor:
            cursor = cursor[key]
            continue
        return None
    return cursor


def resolve_provider_real_balance() -> tuple[Decimal | None, str, str]:
    static_value = _to_decimal(getattr(settings, "FINOPS_PROVIDER_REAL_BALANCE", ""))
    if static_value is not None:
        return static_value, "env_static", ""

    endpoint = str(getattr(settings, "FINOPS_PROVIDER_BALANCE_URL", "") or "").strip()
    if not endpoint:
        return None, "missing_source", "FINOPS_PROVIDER_BALANCE_URL non configure."

    method = str(getattr(settings, "FINOPS_PROVIDER_BALANCE_HTTP_METHOD", "GET") or "GET").upper()
    if method not in {"GET", "POST"}:
        return None, "invalid_config", "FINOPS_PROVIDER_BALANCE_HTTP_METHOD doit etre GET ou POST."

    headers = {"Accept": "application/json"}
    extra_headers = getattr(settings, "FINOPS_PROVIDER_BALANCE_HEADERS", {}) or {}
    if isinstance(extra_headers, dict):
        for key, value in extra_headers.items():
            if key and value is not None:
                headers[str(key)] = str(value)

    auth_header = str(getattr(settings, "FINOPS_PROVIDER_BALANCE_AUTH_HEADER", "Authorization") or "").strip()
    auth_token = str(getattr(settings, "FINOPS_PROVIDER_BALANCE_AUTH_TOKEN", "") or "").strip()
    if auth_header and auth_token:
        headers[auth_header] = auth_token

    body = None
    if method == "POST":
        body = b"{}"
        headers["Content-Type"] = "application/json"

    try:
        req = urllib.request.Request(endpoint, data=body, headers=headers, method=method)
        timeout = max(3, int(getattr(settings, "FINOPS_PROVIDER_BALANCE_TIMEOUT_SECONDS", 15)))
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # nosec B310 - endpoint from FINOPS_PROVIDER_BALANCE settings (server-configured)
            raw = resp.read().decode("utf-8")
    except Exception as exc:
        logger.warning("Provider balance fetch failed: %s", type(exc).__name__)
        return None, "fetch_error", f"Echec appel provider balance: {type(exc).__name__}"

    try:
        payload = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return None, "invalid_payload", "Payload provider balance non JSON."
    if not isinstance(payload, dict):
        return None, "invalid_payload", "Payload provider balance invalide."

    path = str(getattr(settings, "FINOPS_PROVIDER_BALANCE_JSON_PATH", "balance") or "balance").strip()
    candidate = _extract_by_path(payload, path)
    balance = _to_decimal(candidate)
    if balance is None:
        return None, "missing_balance", f"Balance introuvable via path '{path}'."
    return balance, "provider_api", ""

