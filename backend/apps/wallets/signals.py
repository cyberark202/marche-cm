"""
Cache invalidation signals for wallet updates.

When a wallet is modified, invalidate the cached wallet balance/details
to prevent stale data being served to clients.

Cache invalidation is best-effort: a cache backend outage (e.g. Redis down)
must never break a wallet write, which runs inside financial transactions
(order escrow lock, payouts, ...). Failures are swallowed and logged.
"""

import logging

from django.core.cache import cache
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

from .models import Wallet, WalletTransaction

logger = logging.getLogger("wallets")


def _safe_cache_delete(*keys):
    """Delete cache keys, never letting a cache backend failure propagate."""
    for key in keys:
        try:
            cache.delete(key)
        except Exception:  # noqa: BLE001 - cache invalidation is best-effort
            logger.warning("wallet cache invalidation failed for key=%s", key, exc_info=True)


@receiver(post_save, sender=Wallet)
def invalidate_wallet_cache(sender, instance, **kwargs):
    """Invalidate wallet cache when balance updates."""
    _safe_cache_delete(
        f"wallet:{instance.id}:detail",
        f"wallet:{instance.id}:balance",
        f"user:{instance.owner_id}:wallet",
    )


@receiver(post_save, sender=WalletTransaction)
def invalidate_transaction_cache(sender, instance, **kwargs):
    """Invalidate transaction cache when new transaction created."""
    _safe_cache_delete(
        f"wallet:{instance.wallet_id}:transactions",
        f"wallet:{instance.wallet_id}:balance",
    )


@receiver(post_delete, sender=Wallet)
def invalidate_deleted_wallet_cache(sender, instance, **kwargs):
    """Invalidate cache when wallet is deleted."""
    _safe_cache_delete(
        f"wallet:{instance.id}:detail",
        f"user:{instance.owner_id}:wallet",
    )
