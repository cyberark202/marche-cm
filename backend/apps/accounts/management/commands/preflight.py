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
        self._check_storage(add)
        self._check_reconciliation(add)
        self._check_finops_alerts(add)
        self._check_trusted_proxies(add)
        self._check_wallet_pin(add)
        self._check_google(add)
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

    def _check_storage(self, add):
        use_s3 = getattr(settings, "USE_S3_STORAGE", False)
        require_remote = getattr(settings, "REQUIRE_REMOTE_PROOF_STORAGE", False)
        if not use_s3:
            if require_remote:
                add(FAIL, "Stockage fichiers",
                    "REQUIRE_REMOTE_PROOF_STORAGE=True mais USE_S3_STORAGE=False.")
            else:
                add(WARN, "Stockage fichiers",
                    "stockage local — éphémère sur Render (fichiers perdus au redéploiement).")
            return
        bucket = str(
            getattr(settings, "AWS_STORAGE_BUCKET_NAME", "")
            or os.getenv("AWS_STORAGE_BUCKET_NAME", "")
        ).strip()
        endpoint = str(
            getattr(settings, "AWS_S3_ENDPOINT_URL", "")
            or os.getenv("AWS_S3_ENDPOINT_URL", "")
        ).strip()
        placeholders = {"r2 account token", "bucket", "changeme", "your-bucket"}
        if not bucket:
            add(FAIL, "Stockage fichiers", "AWS_STORAGE_BUCKET_NAME vide.")
        elif " " in bucket or bucket.lower() in placeholders:
            add(FAIL, "Stockage fichiers",
                f"nom de bucket invalide/placeholder: '{bucket}' "
                "(un nom de bucket R2/S3 ne contient pas d'espace).")
        elif not endpoint:
            add(FAIL, "Stockage fichiers", "AWS_S3_ENDPOINT_URL vide.")
        else:
            add(OK, "Stockage fichiers", f"S3/R2 bucket '{bucket}'")

    def _check_reconciliation(self, add):
        require = getattr(settings, "RECONCILIATION_REQUIRE_PROVIDER_BALANCE", False)
        url = str(getattr(settings, "FINOPS_PROVIDER_BALANCE_URL", "") or "").strip()
        real = os.getenv("FINOPS_PROVIDER_REAL_BALANCE", "").strip()
        if require and not url and not real:
            add(FAIL, "Réconciliation",
                "RECONCILIATION_REQUIRE_PROVIDER_BALANCE=True mais aucune source de solde "
                "(FINOPS_PROVIDER_BALANCE_URL / FINOPS_PROVIDER_REAL_BALANCE vides).")
        else:
            add(OK, "Réconciliation", "source de solde fournisseur configurée"
                if require else "solde fournisseur non requis")

    def _check_finops_alerts(self, add):
        enabled = any([
            getattr(settings, "FINOPS_ALERT_ON_RECON_ALERT", False),
            getattr(settings, "FINOPS_ALERT_ON_RETRIES_BACKLOG", False),
            getattr(settings, "FINOPS_ALERT_ON_RETRIES_FAILURE", False),
        ])
        emails = getattr(settings, "FINOPS_ALERT_EMAILS", []) or []
        webhook = str(getattr(settings, "FINOPS_ALERT_WEBHOOK_URL", "") or "").strip()
        if enabled and not emails and not webhook:
            add(WARN, "Alertes FinOps",
                "activées mais aucun destinataire (EMAILS/WEBHOOK_URL vides) — alertes perdues.")
        else:
            add(OK, "Alertes FinOps",
                "destinataire configuré" if (emails or webhook) else "désactivées")

    def _check_trusted_proxies(self, add):
        proxies = getattr(settings, "TRUSTED_PROXIES", []) or []
        if not proxies:
            add(WARN, "Trusted proxies",
                "TRUSTED_PROXIES vide — rate-limit/anti-fraude par IP dégradés derrière le proxy.")
        else:
            add(OK, "Trusted proxies", f"{len(proxies)} configuré(s)")

    def _check_wallet_pin(self, add):
        n = int(getattr(settings, "WALLET_PIN_VERIFY_MIN_LENGTH", 4) or 4)
        if n < 6:
            add(WARN, "Wallet PIN",
                f"vérif min {n} chiffres (<6) — passer à 6 après migration des anciens PIN.")
        else:
            add(OK, "Wallet PIN", f"min {n} chiffres")

    def _check_google(self, add):
        cid = str(getattr(settings, "GOOGLE_CLIENT_ID", "") or "").strip()
        if not cid:
            add(WARN, "Google Sign-In",
                "GOOGLE_CLIENT_ID vide — connexion Google indisponible (masquer le bouton ou renseigner l'ID).")
        else:
            add(OK, "Google Sign-In", "client ID configuré")

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
