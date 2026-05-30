"""
Production pre-flight gate.

Runs a read-only readiness checklist (config + infra connectivity) intended to
be executed against the **target environment** right before a deploy, e.g.:

    python manage.py preflight            # exits 1 if any [FAIL]
    python manage.py preflight --strict   # [WARN] also fails
    python manage.py preflight --warn-only # report only, never non-zero

It performs NO writes to business data — only a cache round-trip and a
`SELECT 1`. Business-logic invariants are covered by the test suite
(`apps/accounts/tests_production_readiness.py`).
"""

import os

from django.conf import settings
from django.core.cache import cache
from django.core.management.base import BaseCommand, CommandError
from django.db import connection
from django.db.migrations.executor import MigrationExecutor

OK = "OK"
WARN = "WARN"
FAIL = "FAIL"


class Command(BaseCommand):
    help = "Production readiness pre-flight (config + infra connectivity)."

    def add_arguments(self, parser):
        parser.add_argument("--strict", action="store_true", help="Treat WARN as FAIL.")
        parser.add_argument(
            "--warn-only",
            action="store_true",
            help="Always exit 0 (report only).",
        )

    def handle(self, *args, **options):
        results: list[tuple[str, str, str]] = []

        def add(level, name, detail=""):
            results.append((level, name, detail))

        self._check_debug(add)
        self._check_secret_key(add)
        self._check_allowed_hosts(add)
        self._check_transport_security(add)
        self._check_cors(add)
        self._check_database(add)
        self._check_cache(add)
        self._check_channels(add)
        self._check_email(add)
        self._check_encryption(add)
        self._check_jwt(add)
        self._check_notchpay(add)
        self._check_debug_bypass(add)
        self._check_migrations(add)

        self._render(results)

        fails = [r for r in results if r[0] == FAIL]
        warns = [r for r in results if r[0] == WARN]
        if options["warn_only"]:
            return
        if fails or (options["strict"] and warns):
            raise CommandError(
                f"Pre-flight NON OK : {len(fails)} FAIL, {len(warns)} WARN. "
                "Corrigez avant de déployer."
            )

    # ── Checks ────────────────────────────────────────────────────────────────

    def _check_debug(self, add):
        if settings.DEBUG:
            add(FAIL, "DEBUG", "DEBUG=True interdit en production.")
        else:
            add(OK, "DEBUG", "False")

    def _check_secret_key(self, add):
        key = getattr(settings, "SECRET_KEY", "") or ""
        if "dev-only" in key or len(key) < 50:
            add(FAIL, "SECRET_KEY", "clé faible/dev (≥50 chars aléatoires requis).")
        else:
            add(OK, "SECRET_KEY", f"{len(key)} chars")

    def _check_allowed_hosts(self, add):
        hosts = list(getattr(settings, "ALLOWED_HOSTS", []) or [])
        if not hosts:
            add(FAIL, "ALLOWED_HOSTS", "vide.")
        elif "*" in hosts:
            add(FAIL, "ALLOWED_HOSTS", "joker '*' interdit en production.")
        else:
            add(OK, "ALLOWED_HOSTS", ", ".join(hosts[:4]))

    def _check_transport_security(self, add):
        flags = {
            "SECURE_SSL_REDIRECT": getattr(settings, "SECURE_SSL_REDIRECT", False),
            "SESSION_COOKIE_SECURE": getattr(settings, "SESSION_COOKIE_SECURE", False),
            "CSRF_COOKIE_SECURE": getattr(settings, "CSRF_COOKIE_SECURE", False),
        }
        off = [k for k, v in flags.items() if not v]
        if off:
            add(WARN, "HTTPS/cookies", "désactivés: " + ", ".join(off))
        else:
            add(OK, "HTTPS/cookies", "SSL redirect + cookies Secure")
        if int(getattr(settings, "SECURE_HSTS_SECONDS", 0) or 0) <= 0:
            add(WARN, "HSTS", "SECURE_HSTS_SECONDS=0")
        else:
            add(OK, "HSTS", f"{settings.SECURE_HSTS_SECONDS}s")

    def _check_cors(self, add):
        if getattr(settings, "CORS_ALLOW_ALL_ORIGINS", False):
            add(FAIL, "CORS", "CORS_ALLOW_ALL_ORIGINS=True interdit.")
        else:
            origins = getattr(settings, "CORS_ALLOWED_ORIGINS", []) or []
            add(OK, "CORS", f"{len(origins)} origine(s) autorisée(s)")

    def _check_database(self, add):
        try:
            with connection.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            add(OK, "Database", connection.vendor)
        except Exception as exc:  # noqa: BLE001 — surface any connectivity error
            add(FAIL, "Database", f"injoignable: {exc}")

    def _check_cache(self, add):
        backend = settings.CACHES.get("default", {}).get("BACKEND", "")
        if "locmem" in backend.lower():
            add(WARN, "Cache", "LocMem — throttling non distribué (Redis requis en multi-instance).")
        else:
            add(OK, "Cache", backend.split(".")[-1])
        # Round-trip (proves the backend is reachable).
        try:
            cache.set("preflight:probe", "1", 5)
            if cache.get("preflight:probe") == "1":
                add(OK, "Cache round-trip", "set/get OK")
                cache.delete("preflight:probe")
            else:
                add(FAIL, "Cache round-trip", "valeur non relue.")
        except Exception as exc:  # noqa: BLE001
            add(FAIL, "Cache round-trip", str(exc))

    def _check_channels(self, add):
        backend = (
            settings.CHANNEL_LAYERS.get("default", {}).get("BACKEND", "")
            if getattr(settings, "CHANNEL_LAYERS", None)
            else ""
        )
        if "redis" in backend.lower():
            add(OK, "Channels", "Redis")
        else:
            add(WARN, "Channels", "InMemory — WebSocket non distribué (Redis requis en multi-instance).")

    def _check_email(self, add):
        backend = getattr(settings, "EMAIL_BACKEND", "")
        if backend.endswith("console.EmailBackend") or backend.endswith("dummy.EmailBackend"):
            add(FAIL, "Email", "backend console/dummy — codes 2FA non délivrés.")
        else:
            add(OK, "Email", backend.split(".")[-2] if "." in backend else backend)

    def _check_encryption(self, add):
        key = os.getenv("DATA_ENCRYPTION_KEY", "").strip()
        if not key:
            add(FAIL, "PII encryption", "DATA_ENCRYPTION_KEY absent.")
        else:
            add(OK, "PII encryption", "DATA_ENCRYPTION_KEY défini")

    def _check_jwt(self, add):
        algo = (getattr(settings, "SIMPLE_JWT", {}) or {}).get("ALGORITHM", "HS256")
        if algo == "HS256":
            add(WARN, "JWT", "HS256 (clé symétrique = SECRET_KEY) — RS256 recommandé.")
        else:
            add(OK, "JWT", algo)

    def _check_notchpay(self, add):
        if not getattr(settings, "NOTCHPAY_ENABLED", False):
            add(WARN, "NotchPay", "désactivé (paiements indisponibles).")
            return
        checkout = str(getattr(settings, "NOTCHPAY_CHECKOUT_WEBHOOK_SECRET", "") or "").strip()
        disburse = str(getattr(settings, "NOTCHPAY_DISBURSE_WEBHOOK_SECRET", "") or "").strip()
        missing = []
        if not checkout:
            missing.append("CHECKOUT")
        if not disburse:
            missing.append("DISBURSE")
        if missing:
            add(FAIL, "NotchPay webhooks", "secret(s) manquant(s): " + ", ".join(missing))
        else:
            add(OK, "NotchPay webhooks", "secrets configurés")

    def _check_debug_bypass(self, add):
        if getattr(settings, "ENABLE_DEBUG_BYPASS", False):
            add(FAIL, "Debug bypass", "ENABLE_DEBUG_BYPASS actif — interdit en production.")
        else:
            add(OK, "Debug bypass", "désactivé")

    def _check_migrations(self, add):
        try:
            executor = MigrationExecutor(connection)
            targets = executor.loader.graph.leaf_nodes()
            plan = executor.migration_plan(targets)
            if plan:
                add(WARN, "Migrations", f"{len(plan)} migration(s) non appliquée(s).")
            else:
                add(OK, "Migrations", "à jour")
        except Exception as exc:  # noqa: BLE001
            add(WARN, "Migrations", f"vérification impossible: {exc}")

    # ── Rendering ───────────────────────────────────────────────────────────────

    def _render(self, results):
        styles = {
            OK: self.style.SUCCESS,
            WARN: self.style.WARNING,
            FAIL: self.style.ERROR,
        }
        self.stdout.write("PRÉFLIGHT PRODUCTION — Marché CM")
        self.stdout.write("=" * 60)
        for level, name, detail in results:
            tag = styles[level](f"[{level:^4}]")
            line = f"{tag} {name:<22} {detail}"
            self.stdout.write(line)
        self.stdout.write("=" * 60)
        n_ok = sum(1 for r in results if r[0] == OK)
        n_warn = sum(1 for r in results if r[0] == WARN)
        n_fail = sum(1 for r in results if r[0] == FAIL)
        self.stdout.write(f"OK={n_ok}  WARN={n_warn}  FAIL={n_fail}")
