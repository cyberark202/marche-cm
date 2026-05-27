"""
Distributed Redis locks for critical financial operations.

Acquire is `SET NX PX` (atomic).
Release is a Lua compare-and-delete script (atomic) — audit ref [FIN-017].

The previous implementation did `cache.get` then `cache.delete` in two trips,
opening a TOCTOU window: between the GET and the DELETE the original lock
could have TTL-expired and been re-acquired by a different worker, then the
stale holder's DELETE would release the NEW holder's lock.

Usage:
    from core.locks import acquire_lock, LockAcquisitionError

    with acquire_lock(f"wallet:{wallet_id}:write", ttl_seconds=10):
        # safe critical section
        ...
"""
from __future__ import annotations

import logging
import time
import uuid
from contextlib import contextmanager

from django.core.cache import cache

logger = logging.getLogger(__name__)


class DistributedLockError(Exception):
    pass


class LockAcquisitionError(DistributedLockError):
    pass


# Lua compare-and-delete: returns 1 if the key existed AND held our token, 0
# otherwise. Eval is atomic from Redis's perspective so no other worker can
# slip in between the GET and the DEL.
_RELEASE_LUA = (
    "if redis.call('get', KEYS[1]) == ARGV[1] "
    "then return redis.call('del', KEYS[1]) else return 0 end"
)


def _redis_client():
    """Best-effort access to the raw redis client behind Django's cache.

    Returns None if the cache backend is not Redis (e.g. LocMemCache in
    tests) — callers then fall back to a non-atomic release path. The
    fallback is acceptable in tests because there is no concurrency.
    """
    cache_impl = getattr(cache, "_cache", None) or getattr(cache, "client", None)
    if cache_impl is None:
        return None
    # Django built-in redis backend exposes `.get_client(...)`
    get_client = getattr(cache_impl, "get_client", None)
    if callable(get_client):
        try:
            return get_client(None, write=True)
        except TypeError:
            try:
                return get_client()
            except Exception:
                return None
    # django-redis style: `.get_client(...)` may sit on a deeper object
    deeper = getattr(cache_impl, "_client", None)
    if deeper is not None:
        get_client = getattr(deeper, "get_client", None)
        if callable(get_client):
            try:
                return get_client(write=True)
            except Exception:
                return None
    return None


def _atomic_release(lock_key: str, token: str) -> bool:
    """Compare-and-delete atomic via Lua. Falls back to a 2-step path if
    raw redis access is not available (LocMem backend in tests)."""
    client = _redis_client()
    if client is not None:
        try:
            # Django's redis backend prefixes the key; we use cache.make_key
            # to get the actual stored key name (with prefix/version).
            full_key = cache.make_key(lock_key, version=None)
            removed = client.eval(_RELEASE_LUA, 1, full_key, token)
            return bool(removed)
        except Exception:
            logger.exception("lock_release_lua_failed key=%s", lock_key)
            # fall through to non-atomic path
    current = cache.get(lock_key)
    if current == token:
        cache.delete(lock_key)
        return True
    return False


@contextmanager
def acquire_lock(
    resource_key: str,
    ttl_seconds: int = 30,
    retry_count: int = 3,
    retry_delay_ms: int = 100,
):
    """
    Acquire a distributed Redis lock for `resource_key`.
    Raises LockAcquisitionError if lock cannot be acquired after retries.
    Auto-releases on exit. Uses token-based release to prevent accidental
    release by another holder (atomic Lua script when Redis is available).
    """
    lock_key = f"dlock:{resource_key}"
    token = str(uuid.uuid4())
    acquired = False

    # `cache.add()` is the cross-backend "set if not exists" primitive — works
    # on both LocMemCache (tests) and the Redis backend (prod). Earlier
    # versions used cache.set(..., nx=True) which is Redis-only and crashed
    # under LocMem with "unexpected keyword argument 'nx'".
    for attempt in range(retry_count + 1):
        result = cache.add(lock_key, token, timeout=ttl_seconds)
        if result:
            acquired = True
            break
        if attempt < retry_count:
            time.sleep(retry_delay_ms / 1000.0)

    if not acquired:
        raise LockAcquisitionError(
            f"Could not acquire distributed lock on '{resource_key}' after {retry_count} retries."
        )

    logger.debug("lock_acquired", extra={"key": resource_key, "ttl": ttl_seconds})
    try:
        yield token
    finally:
        released = _atomic_release(lock_key, token)
        if released:
            logger.debug("lock_released", extra={"key": resource_key})
        else:
            logger.warning(
                "lock_expired",
                extra={"key": resource_key, "msg": "Lock expired or held by other before release"},
            )
