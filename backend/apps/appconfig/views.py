from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.security import (
    has_action_permission,
    verify_sensitive_action_challenge,
    write_audit_log,
)
from .models import (
    PLATFORM_SETTING_DEFAULTS,
    AppPlatform,
    AppRelease,
    PlatformSetting,
    get_platform_setting,
    set_platform_setting,
)


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


# ---------------------------------------------------------------------------
# Paramètres plateforme (docs 01/05/16/17) — lecture + écriture admin
# ---------------------------------------------------------------------------


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _validate_rate(value) -> bool:
    return _is_number(value) and 0 <= value <= 0.5


def _validate_category_rates(value) -> bool:
    return isinstance(value, dict) and all(
        isinstance(k, str) and _validate_rate(v) for k, v in value.items()
    )


def _validate_kyc_limits(value) -> bool:
    if not isinstance(value, dict) or not value:
        return False
    for level, limits in value.items():
        if not str(level).isdigit() or not isinstance(limits, dict):
            return False
        for field in ("deposit_per_tx", "withdraw_per_tx", "per_day"):
            if not _is_number(limits.get(field)) or limits[field] <= 0:
                return False
    return True


# Registre fermé clé → validateur. Une valeur refusée n'est jamais écrite :
# un paramètre financier corrompu casserait checkout et retraits.
_SETTING_VALIDATORS = {
    "commission.default_rate": _validate_rate,
    "commission.category_rates": _validate_category_rates,
    "commission.logistics_rate": _validate_rate,
    "commission.rental_rate": _validate_rate,
    "withdrawal.fee_percent": lambda v: _is_number(v) and 0 <= v <= 10,
    "withdrawal.fee_min": lambda v: _is_number(v) and 0 <= v <= 10000,
    "kyc.limits": _validate_kyc_limits,
    "wallet.dormancy_threshold": lambda v: _is_number(v) and v > 0,
    "wallet.dormancy_delay_days": lambda v: isinstance(v, int) and 1 <= v <= 365,
    "wallet.dormancy_penalty_percent": lambda v: _is_number(v) and 0 <= v <= 10,
    "wallet.dormancy_enabled": lambda v: isinstance(v, bool),
    "orders.seller_validation_hours": lambda v: isinstance(v, int) and 1 <= v <= 168,
    "logistics.dispatch_offer_minutes": lambda v: isinstance(v, int) and 1 <= v <= 120,
}


class PlatformSettingsView(APIView):
    """GET/PUT /api/admin/platform-settings/ — configuration à chaud.

    GET : valeurs effectives (défaut ou surcharge DB) de tout le registre.
    PUT : {"key": ..., "value": ..., "challenge_token": ..., "verification_code": ...}
    L'écriture exige le rôle admin ET un step-up 2FA (doc 17 : la modification
    des frais/commissions est une action sensible). Chaque changement est
    historisé (PlatformSettingHistory) et audité.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if not has_action_permission(request.user, "admin.settings.manage"):
            return Response({"detail": "Action reservee aux administrateurs."}, status=status.HTTP_403_FORBIDDEN)
        overrides = {row.key: row for row in PlatformSetting.objects.all()}
        payload = []
        for key, default in PLATFORM_SETTING_DEFAULTS.items():
            row = overrides.get(key)
            payload.append(
                {
                    "key": key,
                    "value": row.value if row else default,
                    "is_default": row is None,
                    "default": default,
                    "updated_at": row.updated_at.isoformat() if row else None,
                }
            )
        return Response({"settings": payload})

    def put(self, request):
        if not has_action_permission(request.user, "admin.settings.manage"):
            return Response({"detail": "Action reservee aux administrateurs."}, status=status.HTTP_403_FORBIDDEN)
        verified, step_up_message = verify_sensitive_action_challenge(
            user=request.user,
            action_key="admin.settings.manage",
            challenge_token=str(request.data.get("challenge_token") or ""),
            verification_code=str(request.data.get("verification_code") or ""),
        )
        if not verified:
            return Response({"detail": step_up_message}, status=status.HTTP_403_FORBIDDEN)

        key = str(request.data.get("key") or "").strip()
        validator = _SETTING_VALIDATORS.get(key)
        if key not in PLATFORM_SETTING_DEFAULTS or validator is None:
            return Response({"detail": f"Parametre inconnu: {key}"}, status=status.HTTP_400_BAD_REQUEST)
        if "value" not in request.data:
            return Response({"detail": "Champ value requis."}, status=status.HTTP_400_BAD_REQUEST)
        value = request.data["value"]
        if not validator(value):
            return Response({"detail": f"Valeur invalide pour {key}."}, status=status.HTTP_400_BAD_REQUEST)

        set_platform_setting(key, value, actor=request.user)
        write_audit_log(
            actor=request.user,
            action="Modification parametre plateforme",
            action_key="admin.settings.manage",
            metadata={"setting": key, "value": value},
        )
        return Response({"key": key, "value": get_platform_setting(key)})
