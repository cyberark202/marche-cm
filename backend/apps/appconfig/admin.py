from django.contrib import admin

from .models import AppRelease


@admin.register(AppRelease)
class AppReleaseAdmin(admin.ModelAdmin):
    list_display = (
        "app",
        "platform",
        "latest_version",
        "min_supported_version",
        "maintenance",
        "kill_switch",
        "is_active",
        "config_version",
        "updated_at",
    )
    list_filter = ("platform", "maintenance", "kill_switch", "is_active")
    search_fields = ("app",)
    readonly_fields = ("updated_at",)
