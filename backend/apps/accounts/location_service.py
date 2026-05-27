import ipaddress
import json
import socket
import urllib.parse
import urllib.request
from typing import TypedDict

from django.conf import settings
from django.utils import timezone


def _is_safe_geocoder_url(url: str) -> bool:
    """Audit ref: [M-001] reject SSRF-prone URLs.

    Rules:
      * HTTPS only.
      * Hostname must resolve to a PUBLIC unicast IPv4/IPv6 — no loopback,
        link-local, private, multicast, reserved, or unspecified.
      * DEBUG=True relaxes the rule slightly (allows http://localhost) so
        the local dev nominatim mock container keeps working.
    """
    try:
        parsed = urllib.parse.urlparse(url)
    except Exception:
        return False
    scheme = (parsed.scheme or "").lower()
    host = (parsed.hostname or "").lower()
    if not host:
        return False

    debug = bool(getattr(settings, "DEBUG", False))
    if scheme not in ("https",):
        if not (debug and scheme == "http" and host in {"localhost", "127.0.0.1", "::1"}):
            return False

    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        return False
    for info in infos:
        ip_str = info[4][0]
        try:
            ip = ipaddress.ip_address(ip_str)
        except ValueError:
            return False
        if (
            ip.is_loopback
            or ip.is_private
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        ):
            if not (debug and ip.is_loopback):
                return False
    return True


class GeocodePayload(TypedDict):
    label: str
    latitude: float
    longitude: float


COUNTRY_CODE_FALLBACK = {
    "CM": "Cameroon",
    "CI": "Cote d'Ivoire",
    "SN": "Senegal",
    "NG": "Nigeria",
    "GH": "Ghana",
    "BF": "Burkina Faso",
    "FR": "France",
    "US": "United States",
    "CA": "Canada",
    "GB": "United Kingdom",
}


def _country_label_from_code(country_code: str) -> str:
    code = (country_code or "").strip().upper()
    if not code:
        return ""
    return COUNTRY_CODE_FALLBACK.get(code, code)


def _build_search_query(*, city: str, country_code: str) -> tuple[str, str]:
    normalized_city = (city or "").strip()
    normalized_code = (country_code or "").strip().upper()
    country_label = _country_label_from_code(normalized_code)
    if normalized_city and country_label:
        return f"{normalized_city}, {country_label}", normalized_code
    if country_label:
        return country_label, normalized_code
    return normalized_city, normalized_code


def geocode_with_nominatim(*, city: str, country_code: str) -> GeocodePayload | None:
    if not getattr(settings, "NOMINATIM_ENABLED", True):
        return None
    query, normalized_code = _build_search_query(city=city, country_code=country_code)
    if not query:
        return None

    params = {
        "q": query,
        "format": "jsonv2",
        "limit": 1,
        "addressdetails": 1,
    }
    if normalized_code:
        params["countrycodes"] = normalized_code.lower()
    email = getattr(settings, "NOMINATIM_EMAIL", "").strip()
    if email:
        params["email"] = email
    base_url = getattr(settings, "NOMINATIM_BASE_URL", "https://nominatim.openstreetmap.org").rstrip("/")
    # Audit ref: [M-001] block SSRF — refuse non-HTTPS schemes and any host
    # that resolves to a private/loopback/link-local range. Without this, a
    # misconfigured NOMINATIM_BASE_URL pointing at e.g.
    # http://169.254.169.254/ (cloud metadata) would let any caller of
    # update_user_location exfiltrate instance credentials.
    if not _is_safe_geocoder_url(base_url):
        return None
    url = f"{base_url}/search?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": getattr(
                settings,
                "NOMINATIM_USER_AGENT",
                "MarcheCM/1.0 (+admin@marche-cm.local)",
            ),
            "Accept": "application/json",
        },
        method="GET",
    )
    timeout = max(int(getattr(settings, "NOMINATIM_TIMEOUT_SECONDS", 10)), 1)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
        payload = json.loads(raw)
    except Exception:
        return None
    if not isinstance(payload, list) or not payload:
        return None
    row = payload[0] if isinstance(payload[0], dict) else {}
    label = (row.get("display_name") or "").strip()
    lat = row.get("lat")
    lon = row.get("lon")
    if not label or lat is None or lon is None:
        return None
    try:
        lat_value = float(lat)
        lon_value = float(lon)
    except (TypeError, ValueError):
        return None
    return {"label": label, "latitude": lat_value, "longitude": lon_value}


def update_user_location(user, *, force: bool = False) -> bool:
    if user is None:
        return False
    if not force and user.location_latitude is not None and user.location_longitude is not None:
        return False
    result = geocode_with_nominatim(city=getattr(user, "city", ""), country_code=getattr(user, "country_code", ""))
    if not result:
        return False
    user.location_label = result["label"]
    user.location_latitude = result["latitude"]
    user.location_longitude = result["longitude"]
    user.location_provider = "NOMINATIM"
    user.location_updated_at = timezone.now()
    user.save(
        update_fields=[
            "location_label",
            "location_latitude",
            "location_longitude",
            "location_provider",
            "location_updated_at",
        ]
    )
    return True
