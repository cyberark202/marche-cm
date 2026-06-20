from django.db import models


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

    # Nom court de l'app : "app" (buyer/seller), "clients", "driver", "admin".
    app = models.CharField(max_length=32)
    platform = models.CharField(max_length=16, choices=AppPlatform.choices, default=AppPlatform.ANDROID)

    # Dernière version publiée et version minimale encore autorisée (semver "x.y.z").
    latest_version = models.CharField(max_length=32, default="0.0.0")
    min_supported_version = models.CharField(max_length=32, default="0.0.0")

    # Où récupérer la mise à jour (APK direct via le site vitrine, ou lien store).
    download_url = models.URLField(blank=True)

    # Messages localisés {"fr": "...", "en": "..."}.
    update_message = models.JSONField(default=dict, blank=True)
    maintenance_message = models.JSONField(default=dict, blank=True)

    maintenance = models.BooleanField(default=False)
    # Coupe l'app (incident sécurité). Fail-closed côté client une fois reçu.
    kill_switch = models.BooleanField(default=False)

    # Drapeaux d'activation de fonctionnalités déjà livrées (dark launch).
    feature_flags = models.JSONField(default=dict, blank=True)

    # Incrémenté à chaque changement significatif — le client compare pour savoir
    # s'il doit ré-appliquer la config (notifié via WebSocket).
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
        # Diffusion temps réel : les clients connectés au topic "system" refetch
        # leur config et appliquent (kill switch / maintenance / flags) sans
        # redémarrage. Best-effort — broadcast_event avale toute panne du layer.
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
            pass
