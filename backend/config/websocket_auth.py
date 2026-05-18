import logging
from urllib.parse import parse_qs

from asgiref.sync import sync_to_async
from rest_framework_simplejwt.authentication import JWTAuthentication

logger = logging.getLogger(__name__)


def _extract_token_from_subprotocols(scope) -> str:
    """Recupere le JWT depuis Sec-WebSocket-Protocol (recommande).

    Format attendu: deux sous-protocoles separes par une virgule, par ex.
    `Sec-WebSocket-Protocol: bearer, eyJhbGciOi...`. Cette methode evite que
    le token apparaisse dans les access logs des reverse-proxies.
    """
    subprotocols = scope.get("subprotocols") or []
    if not subprotocols:
        return ""
    if len(subprotocols) >= 2 and subprotocols[0].strip().lower() == "bearer":
        return subprotocols[1].strip()
    return ""


def _extract_token_from_headers(scope) -> str:
    """Fallback: lecture de l'en-tete Authorization quand le client le supporte."""
    headers = scope.get("headers") or []
    for raw_name, raw_value in headers:
        try:
            name = raw_name.decode("latin-1").lower()
            value = raw_value.decode("latin-1")
        except Exception:
            continue
        if name == "authorization" and value.lower().startswith("bearer "):
            return value.split(" ", 1)[1].strip()
    return ""


@sync_to_async
def authenticate_scope_user(scope):
    user = scope.get("user")
    if user and getattr(user, "is_authenticated", False) and getattr(user, "is_active", False):
        return user

    token = _extract_token_from_subprotocols(scope) or _extract_token_from_headers(scope)
    if not token:
        # Fallback de compatibilite ascendante: query string. A retirer une
        # fois tous les clients migres vers le subprotocole/header.
        raw_query = scope.get("query_string", b"").decode()
        token = parse_qs(raw_query).get("token", [""])[0].strip()
        if token:
            logger.warning(
                "websocket_auth.token_in_query_string: client utilise un canal "
                "obsolete (token visible dans les logs proxy). Migrer vers "
                "Sec-WebSocket-Protocol: bearer, <token>."
            )
    if not token:
        return None

    authenticator = JWTAuthentication()
    try:
        validated_token = authenticator.get_validated_token(token)
        user = authenticator.get_user(validated_token)
    except Exception:
        return None

    if not user or not getattr(user, "is_active", False):
        return None
    return user
