from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AppPlatform, AppRelease


def parse_version(value: str) -> tuple[int, ...]:
    """Parse 'x.y.z' (en ignorant un éventuel '+build') en tuple d'entiers.

    Tolérant : tout segment non numérique vaut 0. '1.2.3+4' -> (1, 2, 3).
    """
    core = (value or "").split("+", 1)[0].strip()
    parts: list[int] = []
    for segment in core.split("."):
        try:
            parts.append(int(segment))
        except ValueError:
            parts.append(0)
    return tuple(parts) if parts else (0,)


def version_lt(a: str, b: str) -> bool:
    """Retourne True si la version a est strictement inférieure à b."""
    pa, pb = parse_version(a), parse_version(b)
    width = max(len(pa), len(pb))
    pa += (0,) * (width - len(pa))
    pb += (0,) * (width - len(pb))
    return pa < pb


class RuntimeConfigView(APIView):
    """Config runtime d'une app cliente : forced-update, maintenance, kill switch, flags.

    GET /api/app/runtime-config/?app=<app|clients|driver|admin>&platform=android&version=1.2.0

    Public (AllowAny) : doit être joignable AVANT toute authentification, car la
    porte (AppGate) s'exécute au tout premier démarrage. Fail-open : si aucune
    AppRelease n'est configurée, on ne bloque jamais l'app.
    """

    permission_classes = [permissions.AllowAny]
    authentication_classes: list = []

    def get(self, request):
        app = (request.query_params.get("app") or "").strip()
        platform = (request.query_params.get("platform") or AppPlatform.ANDROID).strip()
        client_version = (request.query_params.get("version") or "0.0.0").strip()

        release = (
            AppRelease.objects.filter(app=app, platform=platform, is_active=True).first()
            if app
            else None
        )

        if release is None:
            # Fail-open : pas de config => app pleinement autorisée.
            return Response(
                {
                    "app": app,
                    "platform": platform,
                    "config_version": 0,
                    "latest_version": client_version,
                    "min_supported_version": "0.0.0",
                    "update_available": False,
                    "update_required": False,
                    "download_url": "",
                    "update_message": {},
                    "maintenance": False,
                    "maintenance_message": {},
                    "kill_switch": False,
                    "feature_flags": {},
                }
            )

        update_required = version_lt(client_version, release.min_supported_version)
        update_available = version_lt(client_version, release.latest_version)

        return Response(
            {
                "app": release.app,
                "platform": release.platform,
                "config_version": release.config_version,
                "latest_version": release.latest_version,
                "min_supported_version": release.min_supported_version,
                "update_available": update_available,
                "update_required": update_required,
                "download_url": release.download_url,
                "update_message": release.update_message or {},
                "maintenance": release.maintenance,
                "maintenance_message": release.maintenance_message or {},
                "kill_switch": release.kill_switch,
                "feature_flags": release.feature_flags or {},
            }
        )
