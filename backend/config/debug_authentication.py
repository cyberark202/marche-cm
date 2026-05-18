import hmac

from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework.authentication import BaseAuthentication


class DebugBypassAuthentication(BaseAuthentication):
    def authenticate(self, request):
        if not settings.ENABLE_DEBUG_BYPASS:
            return None
        if not getattr(settings, "DEBUG", False):
            # Defense-in-depth: meme si ENABLE_DEBUG_BYPASS est positionne par erreur,
            # on refuse hors environnement de developpement.
            return None
        configured = getattr(settings, "DEBUG_BYPASS_TOKEN", "") or ""
        if not configured:
            return None

        auth_header = request.META.get("HTTP_AUTHORIZATION", "")
        if not auth_header.startswith("Bearer "):
            return None

        token = auth_header.split(" ", 1)[1].strip()
        if not hmac.compare_digest(str(token), str(configured)):
            return None

        user_model = get_user_model()
        user, created = user_model.objects.get_or_create(
            username="debug.admin",
            defaults={
                "email": "debug.admin@marche-cm.local",
                "role": "GENERAL_ADMIN",
                "is_active": True,
                "is_verified": True,
                "is_superuser": True,
                "is_staff": True,
            },
        )

        if not created:
            updates = []
            if not user.is_active:
                user.is_active = True
                updates.append("is_active")
            if getattr(user, "role", "") != "GENERAL_ADMIN":
                user.role = "GENERAL_ADMIN"
                updates.append("role")
            if not user.is_superuser:
                user.is_superuser = True
                updates.append("is_superuser")
            if not user.is_staff:
                user.is_staff = True
                updates.append("is_staff")
            if updates:
                user.save(update_fields=updates)

        return (user, None)
