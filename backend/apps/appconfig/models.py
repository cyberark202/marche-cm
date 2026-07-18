import logging

from django.conf import settings as django_settings
from django.core.cache import cache
from django.db import models

logger = logging.getLogger(__name__)


class AppPlatform(models.TextChoices):
    ANDROID = "android", "Android"
    IOS = "ios", "iOS"
    WEB = "web", "Web"


class AppRelease(models.Model):
    """Gouvernance à distance d'une app cliente (forced-update / maintenance / kill switch).

    Un enregistrement par couple (app, platform). Édité par un admin ; lu par les
    clients via /api/app/runtime-config/. La diffusion temps réel d'un changement
    se fait via broadcast_event("system", "app_config_changed", ...).
    """

    app = models.CharField(max_length=32)
    platform = models.CharField(max_length=16, choices=AppPlatform.choices, default=AppPlatform.ANDROID)

    latest_version = models.CharField(max_length=32, default="0.0.0")
    min_supported_version = models.CharField(max_length=32, default="0.0.0")

    download_url = models.URLField(blank=True)

    update_message = models.JSONField(default=dict, blank=True)
    maintenance_message = models.JSONField(default=dict, blank=True)

    maintenance = models.BooleanField(default=False)
    kill_switch = models.BooleanField(default=False)

    feature_flags = models.JSONField(default=dict, blank=True)

    config_version = models.PositiveIntegerField(default=1)

    is_active = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["app", "platform"], name="uniq_app_platform"),
        ]
        ordering = ["app", "platform"]

    def __str__(self) -> str:
        return f"{self.app}/{self.platform} (min {self.min_supported_version}, latest {self.latest_version})"

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        try:
            from apps.notifications.realtime import broadcast_event

            broadcast_event(
                "system",
                "app_config_changed",
                {
                    "app": self.app,
                    "platform": self.platform,
                    "config_version": self.config_version,
                },
            )
        except Exception:
            logger.exception("app_config_broadcast_failed app=%s platform=%s", self.app, self.platform)



PLATFORM_SETTING_DEFAULTS: dict[str, object] = {
    "commission.default_rate": 0.10,
    "commission.category_rates": {},
    "commission.logistics_rate": 0.10,
    "commission.rental_rate": 0.10,
    "withdrawal.fee_percent": 1.5,
    "withdrawal.fee_min": 100,
    "kyc.limits": {
        "0": {"deposit_per_tx": 50000, "withdraw_per_tx": 100000, "per_day": 150000},
        "1": {"deposit_per_tx": 200000, "withdraw_per_tx": 200000, "per_day": 500000},
        "2": {"deposit_per_tx": 1500000, "withdraw_per_tx": 1500000, "per_day": 5000000},
        "3": {"deposit_per_tx": 5000000, "withdraw_per_tx": 5000000, "per_day": 20000000},
    },
    "wallet.dormancy_threshold": 2000000,
    "wallet.dormancy_delay_days": 7,
    "wallet.dormancy_penalty_percent": 0,
    "wallet.dormancy_enabled": False,
    "orders.seller_validation_hours": 24,
    "logistics.dispatch_offer_minutes": 15,
}

_SETTING_CACHE_PREFIX = "platform_setting:"
_SETTING_CACHE_TTL = 60


class PlatformSetting(models.Model):
    key = models.CharField(max_length=64, unique=True)
    value = models.JSONField()
    updated_by = models.ForeignKey(
        django_settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="platform_settings_updated",
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["key"]

    def __str__(self) -> str:
        return f"{self.key}={self.value}"


class PlatformSettingHistory(models.Model):
    """Historique immuable de chaque modification (append-only, jamais purgé)."""

    key = models.CharField(max_length=64, db_index=True)
    old_value = models.JSONField(null=True)
    new_value = models.JSONField()
    changed_by = models.ForeignKey(
        django_settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="platform_setting_changes",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


def get_platform_setting(key: str):
    """Valeur effective d'un paramètre : surcharge DB sinon défaut du registre.

    Cache 60 s pour ne pas toucher la DB sur les chemins chauds (checkout,
    retrait). Fail-safe : toute erreur DB/cache retombe sur le défaut.
    """
    if key not in PLATFORM_SETTING_DEFAULTS:
        raise KeyError(f"Parametre plateforme inconnu: {key}")
    cache_key = f"{_SETTING_CACHE_PREFIX}{key}"
    try:
        cached = cache.get(cache_key)
        if cached is not None:
            return cached
    except Exception:
        logger.exception("platform_setting_cache_get_failed key=%s", key)
    value = PLATFORM_SETTING_DEFAULTS[key]
    try:
        row = PlatformSetting.objects.filter(key=key).only("value").first()
        if row is not None:
            value = row.value
    except Exception:
        logger.exception("platform_setting_db_read_failed key=%s", key)
    try:
        cache.set(cache_key, value, _SETTING_CACHE_TTL)
    except Exception:
        logger.exception("platform_setting_cache_set_failed key=%s", key)
    return value


def set_platform_setting(key: str, value, *, actor=None):
    """Écrit un paramètre (registre fermé) + historise + invalide le cache."""
    if key not in PLATFORM_SETTING_DEFAULTS:
        raise KeyError(f"Parametre plateforme inconnu: {key}")
    row, created = PlatformSetting.objects.get_or_create(key=key, defaults={"value": value, "updated_by": actor})
    old_value = None if created else row.value
    if not created:
        row.value = value
        row.updated_by = actor
        row.save(update_fields=["value", "updated_by", "updated_at"])
    PlatformSettingHistory.objects.create(key=key, old_value=old_value, new_value=value, changed_by=actor)
    try:
        cache.delete(f"{_SETTING_CACHE_PREFIX}{key}")
    except Exception:
        logger.exception("platform_setting_cache_delete_failed key=%s", key)
    return row
