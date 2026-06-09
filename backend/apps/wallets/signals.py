"""
Cache invalidation signals for wallet updates.

When a wallet is modified, invalidate the cached wallet balance/details
to prevent stale data being served to clients.
"""

from django.core.cache import cache
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver

from .models import Wallet, WalletTransaction


@receiver(post_save, sender=Wallet)
def invalidate_wallet_cache(sender, instance, **kwargs):
    """Invalidate wallet cache when balance updates."""
    cache.delete(f"wallet:{instance.id}:detail")
    cache.delete(f"wallet:{instance.id}:balance")
    cache.delete(f"user:{instance.owner_id}:wallet")


@receiver(post_save, sender=WalletTransaction)
def invalidate_transaction_cache(sender, instance, **kwargs):
    """Invalidate transaction cache when new transaction created."""
    cache.delete(f"wallet:{instance.wallet_id}:transactions")
    cache.delete(f"wallet:{instance.wallet_id}:balance")


@receiver(post_delete, sender=Wallet)
def invalidate_deleted_wallet_cache(sender, instance, **kwargs):
    """Invalidate cache when wallet is deleted."""
    cache.delete(f"wallet:{instance.id}:detail")
    cache.delete(f"user:{instance.owner_id}:wallet")
