"""
Presence management — track online users via Redis.
"""
from __future__ import annotations

import logging

from django.core.cache import cache

logger = logging.getLogger(__name__)

PRESENCE_TTL = 65  # seconds — client should heartbeat every 30s
PRESENCE_PREFIX = "presence:"


def set_online(user_id: int) -> None:
    cache.set(f"{PRESENCE_PREFIX}{user_id}", "1", timeout=PRESENCE_TTL)


def set_offline(user_id: int) -> None:
    cache.delete(f"{PRESENCE_PREFIX}{user_id}")


def is_online(user_id: int) -> bool:
    return bool(cache.get(f"{PRESENCE_PREFIX}{user_id}"))


def get_online_users(user_ids: list[int]) -> list[int]:
    keys = [f"{PRESENCE_PREFIX}{uid}" for uid in user_ids]
    results = cache.get_many(keys)
    online = []
    for i, uid in enumerate(user_ids):
        if results.get(keys[i]):
            online.append(uid)
    return online
