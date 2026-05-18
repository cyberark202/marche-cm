import base64
import hashlib
import logging
from functools import lru_cache

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured

ENCRYPTION_PREFIX = "enc1$"

logger = logging.getLogger(__name__)


def _derive_fernet_key(raw_secret: str) -> bytes:
    digest = hashlib.sha256(raw_secret.encode("utf-8")).digest()
    return base64.urlsafe_b64encode(digest)


def _normalize_raw_keys() -> list[str]:
    keys: list[str] = []
    raw_primary = (getattr(settings, "DATA_ENCRYPTION_KEY", "") or "").strip()
    if not raw_primary:
        if settings.DEBUG:
            raw_primary = f"{settings.SECRET_KEY}:dev-data-encryption"
        else:
            raise ImproperlyConfigured("DATA_ENCRYPTION_KEY is required when DEBUG=False.")
    keys.append(raw_primary)

    raw_fallback = getattr(settings, "DATA_ENCRYPTION_FALLBACK_KEYS", ())
    if isinstance(raw_fallback, str):
        candidates = [item.strip() for item in raw_fallback.split(",") if item.strip()]
    else:
        candidates = [str(item).strip() for item in raw_fallback if str(item).strip()]
    for item in candidates:
        if item not in keys:
            keys.append(item)
    return keys


@lru_cache(maxsize=1)
def _get_fernet_chain() -> tuple[Fernet, ...]:
    return tuple(Fernet(_derive_fernet_key(raw_key)) for raw_key in _normalize_raw_keys())


def clear_crypto_cache() -> None:
    _get_fernet_chain.cache_clear()


def looks_encrypted(value: str | None) -> bool:
    if not value:
        return False
    return str(value).startswith(ENCRYPTION_PREFIX)


def encrypt_value(value: str | None) -> str:
    if value is None:
        return ""
    text = str(value)
    if not text:
        return text
    if looks_encrypted(text):
        return text
    token = _get_fernet_chain()[0].encrypt(text.encode("utf-8")).decode("utf-8")
    return f"{ENCRYPTION_PREFIX}{token}"


def decrypt_value(value: str | None) -> str:
    if value is None:
        return ""
    text = str(value)
    if not text:
        return text
    if not looks_encrypted(text):
        return text
    token = text[len(ENCRYPTION_PREFIX) :]
    token_bytes = token.encode("utf-8")
    for fernet in _get_fernet_chain():
        try:
            return fernet.decrypt(token_bytes).decode("utf-8")
        except (InvalidToken, ValueError):
            continue
    # Aucune cle de la chaine n'a pu dechiffrer le payload: cela signale soit
    # une rotation manquante, soit une donnee corrompue. On log avec un
    # niveau eleve et on retourne une chaine vide pour ne JAMAIS exposer le
    # ciphertext brut a l'utilisateur ou via API.
    logger.error(
        "field_crypto.decrypt_failed: aucune cle DATA_ENCRYPTION_KEY ne peut dechiffrer le payload (longueur=%d)",
        len(token_bytes),
    )
    return ""
