from pathlib import Path
import os
import json
from datetime import timedelta
from urllib.parse import unquote, urlparse
from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

def _env_bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


def _env_list(name: str, default: str = "") -> list[str]:
    return [value.strip() for value in os.getenv(name, default).split(",") if value.strip()]


def _env_json(name: str, default: str = "{}") -> dict:
    raw_value = os.getenv(name, default).strip()
    if not raw_value:
        return {}
    try:
        parsed = json.loads(raw_value)
    except json.JSONDecodeError as exc:
        raise ImproperlyConfigured(f"{name} must be valid JSON.") from exc
    if not isinstance(parsed, dict):
        raise ImproperlyConfigured(f"{name} must be a JSON object.")
    return parsed


def _env_int(name: str, default: int) -> int:
    raw_value = os.getenv(name, "").strip()
    if not raw_value:
        return default
    try:
        return int(raw_value)
    except ValueError as exc:
        raise ImproperlyConfigured(f"{name} must be an integer.") from exc


def _env_str_alias(primary_name: str, fallback_name: str, default: str = "") -> str:
    value = os.getenv(primary_name)
    if value is None:
        value = os.getenv(fallback_name, default)
    return value.strip()


def _env_bool_alias(primary_name: str, fallback_name: str, default: bool = False) -> bool:
    value = os.getenv(primary_name)
    if value is None:
        return _env_bool(fallback_name, default)
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _env_list_alias(primary_name: str, fallback_name: str, default: str = "") -> list[str]:
    value = os.getenv(primary_name)
    if value is None:
        return _env_list(fallback_name, default)
    return [item.strip() for item in value.split(",") if item.strip()]


def _database_from_url(database_url: str) -> dict[str, object]:
    parsed = urlparse(database_url)
    scheme = parsed.scheme.lower()
    if scheme in {"postgres", "postgresql", "pgsql"}:
        db_name = (parsed.path or "").lstrip("/")
        if not db_name:
            raise ImproperlyConfigured("DATABASE_URL is missing database name.")
        return {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": unquote(db_name),
            "USER": unquote(parsed.username or ""),
            "PASSWORD": unquote(parsed.password or ""),
            "HOST": parsed.hostname or "",
            "PORT": str(parsed.port or ""),
        }
    if scheme == "sqlite":
        raw_path = parsed.path or ""
        if not raw_path or raw_path == "/":
            raise ImproperlyConfigured("DATABASE_URL sqlite path is missing.")
        if parsed.netloc and parsed.netloc not in {"", "localhost"}:
            raw_path = f"//{parsed.netloc}{raw_path}"
        return {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": unquote(raw_path),
        }
    raise ImproperlyConfigured(
        "DATABASE_URL scheme must be postgres/postgresql or sqlite."
    )


DEBUG = _env_bool("DEBUG", False)
SECRET_KEY = os.getenv("SECRET_KEY", "").strip()
if not SECRET_KEY:
    if DEBUG:
        SECRET_KEY = "dev-only-secret-key-change-before-production"
    else:
        raise ImproperlyConfigured("SECRET_KEY is required when DEBUG=False.")

# Audit ref: [N-006] development IP removed from the default. Production
# operators MUST set ALLOWED_HOSTS explicitly via env; the default only
# covers local-loopback hostnames for dev runs.
ALLOWED_HOSTS = _env_list("ALLOWED_HOSTS", "127.0.0.1,localhost")

# Audit ref: [N-005] reverse-proxy IPs that are allowed to set X-Forwarded-For.
# Empty by default — the canonical _client_ip helper refuses XFF when REMOTE_ADDR
# is not in this list, so an attacker connecting directly cannot forge their IP.
TRUSTED_PROXIES = _env_list("TRUSTED_PROXIES", "")
BACKEND_PUBLIC_URL = os.getenv("BACKEND_PUBLIC_URL", "http://127.0.0.1:8000")
# Audit ref: [M-003] reject plaintext HTTP for callback URLs in production —
# NotchPay would otherwise be told to deliver payment receipts and OAuth
# redirects over an unencrypted channel.
if not DEBUG and BACKEND_PUBLIC_URL.lower().startswith("http://"):
    raise ImproperlyConfigured(
        "BACKEND_PUBLIC_URL must use HTTPS in production. "
        "Set it to https://<your-domain> in the deployment env."
    )
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
DATA_ENCRYPTION_KEY = os.getenv("DATA_ENCRYPTION_KEY", "").strip()
DATA_ENCRYPTION_FALLBACK_KEYS = _env_list("DATA_ENCRYPTION_FALLBACK_KEYS")
AUTH_LOCKDOWN = _env_bool("AUTH_LOCKDOWN", False)

# Debug authentication bypass — hardened against accidental production activation.
# Audit ref: [H-001] DebugBypassAuthentication peut créer un superuser
# Rules:
#   1. The env var ENABLE_DEBUG_BYPASS=1 is REFUSED at startup if DEBUG=False.
#   2. The auth class is NEVER registered when DEBUG=False, even if the env vars leak.
#   3. DEBUG_BYPASS_TOKEN is REFUSED at startup if shorter than 32 chars (entropy).
_debug_bypass_env_enabled = _env_bool("ENABLE_DEBUG_BYPASS", False)
DEBUG_BYPASS_TOKEN = os.getenv("DEBUG_BYPASS_TOKEN", "").strip()
if not DEBUG and _debug_bypass_env_enabled:
    raise ImproperlyConfigured(
        "ENABLE_DEBUG_BYPASS=1 is forbidden when DEBUG=False. "
        "This switch creates an instant superuser and must NEVER be active in production."
    )
if _debug_bypass_env_enabled and DEBUG_BYPASS_TOKEN and len(DEBUG_BYPASS_TOKEN) < 32:
    raise ImproperlyConfigured(
        "DEBUG_BYPASS_TOKEN must be at least 32 characters (use secrets.token_urlsafe(32))."
    )
ENABLE_DEBUG_BYPASS = DEBUG and _debug_bypass_env_enabled and bool(DEBUG_BYPASS_TOKEN)

# Keep common local dev hosts accepted (Android emulator, localhost variants),
# avoiding DisallowedHost errors while testing mobile builds against local API.
if DEBUG:
    for host in ("127.0.0.1", "localhost", "10.0.2.2", "10.0.3.2", "[::1]"):
        if host not in ALLOWED_HOSTS:
            ALLOWED_HOSTS.append(host)

_render_external_hostname = os.getenv("RENDER_EXTERNAL_HOSTNAME", "").strip().lower()
if _render_external_hostname and _render_external_hostname not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(_render_external_hostname)

_public_host = (urlparse(BACKEND_PUBLIC_URL).hostname or "").strip().lower()
if _public_host and _public_host not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(_public_host)

SECURE_SSL_REDIRECT = _env_bool("SECURE_SSL_REDIRECT", not DEBUG)
SESSION_COOKIE_SECURE = _env_bool("SESSION_COOKIE_SECURE", not DEBUG)
# Audit ref: [N-013] Strict SameSite for session and CSRF cookies — Django's
# default "Lax" still lets a top-level GET cross-site request carry the
# session, which is insufficient for a fintech admin surface. Strict forbids
# the cookie from riding any cross-site navigation.
SESSION_COOKIE_SAMESITE = os.getenv("SESSION_COOKIE_SAMESITE", "Strict")
CSRF_COOKIE_SAMESITE = os.getenv("CSRF_COOKIE_SAMESITE", "Strict")
CSRF_COOKIE_SECURE = _env_bool("CSRF_COOKIE_SECURE", not DEBUG)
SECURE_HSTS_SECONDS = int(os.getenv("SECURE_HSTS_SECONDS", "31536000" if not DEBUG else "0"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = _env_bool("SECURE_HSTS_INCLUDE_SUBDOMAINS", not DEBUG)
SECURE_HSTS_PRELOAD = _env_bool("SECURE_HSTS_PRELOAD", not DEBUG)
CSRF_TRUSTED_ORIGINS = _env_list("CSRF_TRUSTED_ORIGINS")
_render_external_url = os.getenv("RENDER_EXTERNAL_URL", "").strip()
if _render_external_url and _render_external_url not in CSRF_TRUSTED_ORIGINS:
    CSRF_TRUSTED_ORIGINS.append(_render_external_url)
if _render_external_hostname:
    render_origin = f"https://{_render_external_hostname}"
    if render_origin not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(render_origin)
if _env_bool("USE_X_FORWARDED_PROTO", not DEBUG):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Browser-origin policy configuration for frontend web clients.
CORS_ALLOW_ALL_ORIGINS = _env_bool("CORS_ALLOW_ALL_ORIGINS", False)
CORS_ALLOWED_ORIGINS = _env_list("CORS_ALLOWED_ORIGINS")
CORS_ALLOWED_ORIGIN_REGEXES = _env_list("CORS_ALLOWED_ORIGIN_REGEXES")

# In local debug, allow localhost dynamic ports (Flutter web/Vite/etc.)
# when no explicit CORS origin configuration is provided.
if DEBUG and not CORS_ALLOW_ALL_ORIGINS and not CORS_ALLOWED_ORIGINS and not CORS_ALLOWED_ORIGIN_REGEXES:
    CORS_ALLOWED_ORIGIN_REGEXES = [
        r"^http://localhost:\d+$",
        r"^http://127\.0\.0\.1:\d+$",
    ]

INSTALLED_APPS = [
    "corsheaders",
    "daphne",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt",
    "rest_framework_simplejwt.token_blacklist",
    "channels",
    "apps.accounts",
    "apps.catalog",
    "apps.orders",
    "apps.wallets",
    "apps.chat",
    "apps.analytics",
    "apps.logistics",
    "apps.notifications",
    "apps.innovation",
    "apps.support",
    "apps.escrow",
    "apps.disputes",
    "apps.ledger",
    "apps.audit",
    "apps.fraud",
    "apps.compliance",
    "apps.realtime",
    "django_celery_beat",
    "django_celery_results",
    "drf_spectacular",
    "core.events",
]

MIDDLEWARE = [
    # Correlation ID first — every downstream log will carry it.
    "config.middleware.CorrelationIDMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    # Security headers after SecurityMiddleware (which sets HSTS/SSL).
    "config.middleware.SecurityHeadersMiddleware",
    # Block oversized requests before sessions/auth parse the body.
    "config.middleware.RequestSizeLimitMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    # Suspicious activity detection last — has full request context.
    "config.middleware.SuspiciousRequestMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    }
]

DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
DB_ENGINE = os.getenv("DB_ENGINE", "sqlite").strip().lower()
DB_CONN_MAX_AGE = _env_int("DB_CONN_MAX_AGE", 60 if not DEBUG else 0)
DB_CONNECT_TIMEOUT = _env_int("DB_CONNECT_TIMEOUT", 5)

if DATABASE_URL:
    default_database = _database_from_url(DATABASE_URL)
elif DB_ENGINE in {"postgres", "postgresql", "pgsql"}:
    default_database = {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.getenv("DB_NAME", "").strip(),
        "USER": os.getenv("DB_USER", "").strip(),
        "PASSWORD": os.getenv("DB_PASSWORD", "").strip(),
        "HOST": os.getenv("DB_HOST", "127.0.0.1").strip(),
        "PORT": os.getenv("DB_PORT", "5432").strip(),
    }
    if not default_database["NAME"]:
        raise ImproperlyConfigured("DB_NAME is required when DB_ENGINE=postgres.")
else:
    default_database = {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }

if default_database["ENGINE"] == "django.db.backends.postgresql":
    default_database["CONN_MAX_AGE"] = DB_CONN_MAX_AGE
    default_database["OPTIONS"] = {
        "connect_timeout": DB_CONNECT_TIMEOUT,
    }
else:
    default_database["CONN_MAX_AGE"] = 0

DATABASES = {"default": default_database}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "fr-fr"
TIME_ZONE = "Africa/Abidjan"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
USE_S3_STORAGE = _env_bool("USE_S3_STORAGE", False)
DEFAULT_FILE_STORAGE = os.getenv("DEFAULT_FILE_STORAGE", "django.core.files.storage.FileSystemStorage").strip()
REQUIRE_REMOTE_PROOF_STORAGE = _env_bool("REQUIRE_REMOTE_PROOF_STORAGE", not DEBUG)
if USE_S3_STORAGE:
    if "storages" not in INSTALLED_APPS:
        INSTALLED_APPS.append("storages")
    DEFAULT_FILE_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"
    AWS_STORAGE_BUCKET_NAME = os.getenv("AWS_STORAGE_BUCKET_NAME", "").strip()
    AWS_S3_REGION_NAME = os.getenv("AWS_S3_REGION_NAME", "").strip() or None
    AWS_S3_ENDPOINT_URL = os.getenv("AWS_S3_ENDPOINT_URL", "").strip() or None
    AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "").strip()
    AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "").strip()
    AWS_S3_ADDRESSING_STYLE = os.getenv("AWS_S3_ADDRESSING_STYLE", "auto").strip()
    AWS_DEFAULT_ACL = None
    AWS_QUERYSTRING_AUTH = False
    # Public media URL: use a custom domain (CDN) when available, otherwise
    # derive from the endpoint + bucket (works for Cloudflare R2 public buckets).
    _s3_custom_domain = os.getenv("AWS_S3_CUSTOM_DOMAIN", "").strip()
    if _s3_custom_domain:
        MEDIA_URL = f"https://{_s3_custom_domain}/"
    elif AWS_S3_ENDPOINT_URL and AWS_STORAGE_BUCKET_NAME:
        MEDIA_URL = f"{AWS_S3_ENDPOINT_URL.rstrip('/')}/{AWS_STORAGE_BUCKET_NAME}/"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
AUTH_USER_MODEL = "accounts.User"

_auth_classes = ["rest_framework_simplejwt.authentication.JWTAuthentication"]
if ENABLE_DEBUG_BYPASS:
    _auth_classes.insert(0, "config.debug_authentication.DebugBypassAuthentication")

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": tuple(_auth_classes),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_THROTTLE_CLASSES": (
        # Global limits applied to every request regardless of endpoint.
        "config.throttles.GlobalAnonThrottle",
        "config.throttles.GlobalUserThrottle",
        # Endpoint-specific scoped throttles are applied via @throttle_classes decorator.
    ),
    "DEFAULT_THROTTLE_RATES": {},   # Rates live in throttle class definitions.
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
    # OpenAPI schema generator. Required by drf-spectacular — without it the
    # generator raises E001 on every APIView (e.g. the CSV AuditLogExportView)
    # because DRF's stock AutoSchema is incompatible.
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    # Never expose internal Python exception details to clients.
    "EXCEPTION_HANDLER": "config.exceptions.security_exception_handler",
}

# Access token lifetime: 15 min default (fintech best practice).
# Refresh token: 7 days with rotation (client handles silent refresh via interceptor).
JWT_ACCESS_TOKEN_MINUTES = _env_int("JWT_ACCESS_TOKEN_MINUTES", 15)
JWT_REFRESH_TOKEN_DAYS = _env_int("JWT_REFRESH_TOKEN_DAYS", 7)
# Legacy hour-based env vars kept for backward compat during migration.
_legacy_access_hours = _env_int("JWT_ACCESS_TOKEN_HOURS", 0)
_legacy_refresh_hours = _env_int("JWT_REFRESH_TOKEN_HOURS", 0)
if _legacy_access_hours > 0 and JWT_ACCESS_TOKEN_MINUTES == 15:
    JWT_ACCESS_TOKEN_MINUTES = _legacy_access_hours * 60
if _legacy_refresh_hours > 0 and JWT_REFRESH_TOKEN_DAYS == 7:
    JWT_REFRESH_TOKEN_DAYS = max(1, _legacy_refresh_hours // 24)

if JWT_ACCESS_TOKEN_MINUTES <= 0 or JWT_REFRESH_TOKEN_DAYS <= 0:
    raise ImproperlyConfigured("JWT_ACCESS_TOKEN_MINUTES and JWT_REFRESH_TOKEN_DAYS must be > 0.")

# Warn operators if they set dangerously long access token lifetimes.
if JWT_ACCESS_TOKEN_MINUTES > 60 and not DEBUG:
    import warnings
    warnings.warn(
        f"JWT_ACCESS_TOKEN_MINUTES={JWT_ACCESS_TOKEN_MINUTES} exceeds 60 minutes. "
        "Fintech best practice is ≤15 minutes to limit token theft exposure.",
        stacklevel=1,
    )

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=JWT_ACCESS_TOKEN_MINUTES),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=JWT_REFRESH_TOKEN_DAYS),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    # Use RS256 in production (asymmetric) if SIGNING_KEY is set to an RSA private key.
    # Falls back to HS256 (symmetric) with SECRET_KEY.
    "ALGORITHM": os.getenv("JWT_ALGORITHM", "HS256"),
    "SIGNING_KEY": os.getenv("JWT_SIGNING_KEY", "").strip() or None,
    # Additional security claims
    "UPDATE_LAST_LOGIN": True,
    "JTI_CLAIM": "jti",
}
# If no explicit signing key, SimpleJWT falls back to SECRET_KEY (HS256).
if not SIMPLE_JWT["SIGNING_KEY"]:
    del SIMPLE_JWT["SIGNING_KEY"]

MFA_ISSUER_NAME = os.getenv("MFA_ISSUER_NAME", "Marche CM")
DEVICE_FINGERPRINT_SECRET = os.getenv("DEVICE_FINGERPRINT_SECRET", "").strip()
SECURITY_HARD_BLOCK_SCANNERS = _env_bool("SECURITY_HARD_BLOCK_SCANNERS", not DEBUG)

REDIS_URL = os.getenv("REDIS_URL", "").strip()
CHANNEL_REDIS_PREFIX = os.getenv("CHANNEL_REDIS_PREFIX", "marche_cm").strip() or "marche_cm"
CHANNEL_CAPACITY = _env_int("CHANNEL_CAPACITY", 1500)
CHANNEL_EXPIRY_SECONDS = _env_int("CHANNEL_EXPIRY_SECONDS", 60)
CHANNEL_GROUP_EXPIRY_SECONDS = _env_int("CHANNEL_GROUP_EXPIRY_SECONDS", 86400)

if REDIS_URL:
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {
                "hosts": [REDIS_URL],
                "prefix": CHANNEL_REDIS_PREFIX,
                "capacity": CHANNEL_CAPACITY,
                "expiry": CHANNEL_EXPIRY_SECONDS,
                "group_expiry": CHANNEL_GROUP_EXPIRY_SECONDS,
            },
        }
    }
else:
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels.layers.InMemoryChannelLayer",
        }
    }

CACHE_URL = os.getenv("CACHE_URL", "").strip() or REDIS_URL
if CACHE_URL:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": CACHE_URL,
        }
    }
else:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "marche-cm-cache",
        }
    }

EMAIL_BACKEND = os.getenv("EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend")
DEFAULT_FROM_EMAIL = os.getenv("DEFAULT_FROM_EMAIL", "no-reply@marche-cm.local")
EMAIL_HOST = os.getenv("EMAIL_HOST", "")
EMAIL_PORT = int(os.getenv("EMAIL_PORT", "587"))
EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD", "")
EMAIL_USE_TLS = _env_bool("EMAIL_USE_TLS", True)
EMAIL_USE_SSL = _env_bool("EMAIL_USE_SSL", False)

NOTCHPAY_ENABLED = _env_bool_alias("NOTCHPAY_ENABLED", "PAYDUNYA_ENABLED", False)
NOTCHPAY_MODE = _env_str_alias("NOTCHPAY_MODE", "PAYDUNYA_MODE", "test").lower()
if NOTCHPAY_MODE not in {"test", "live"}:
    raise ImproperlyConfigured("NOTCHPAY_MODE must be 'test' or 'live'.")
NOTCHPAY_API_BASE = _env_str_alias("NOTCHPAY_API_BASE", "PAYDUNYA_API_BASE", "https://api.notchpay.co")
NOTCHPAY_CURRENCY = _env_str_alias("NOTCHPAY_CURRENCY", "PAYDUNYA_CURRENCY", "XAF").upper()

NOTCHPAY_TEST_PUBLIC_KEY = _env_str_alias("NOTCHPAY_TEST_PUBLIC_KEY", "PAYDUNYA_TEST_PUBLIC_KEY")
NOTCHPAY_TEST_PRIVATE_KEY = _env_str_alias("NOTCHPAY_TEST_PRIVATE_KEY", "PAYDUNYA_TEST_PRIVATE_KEY")
NOTCHPAY_LIVE_PUBLIC_KEY = _env_str_alias("NOTCHPAY_LIVE_PUBLIC_KEY", "PAYDUNYA_LIVE_PUBLIC_KEY")
NOTCHPAY_LIVE_PRIVATE_KEY = _env_str_alias("NOTCHPAY_LIVE_PRIVATE_KEY", "PAYDUNYA_LIVE_PRIVATE_KEY")

if NOTCHPAY_MODE == "live":
    _default_notchpay_public_key = NOTCHPAY_LIVE_PUBLIC_KEY
    _default_notchpay_private_key = NOTCHPAY_LIVE_PRIVATE_KEY
else:
    _default_notchpay_public_key = NOTCHPAY_TEST_PUBLIC_KEY
    _default_notchpay_private_key = NOTCHPAY_TEST_PRIVATE_KEY

NOTCHPAY_PUBLIC_KEY = _env_str_alias("NOTCHPAY_PUBLIC_KEY", "PAYDUNYA_PUBLIC_KEY", _default_notchpay_public_key)
NOTCHPAY_PRIVATE_KEY = _env_str_alias("NOTCHPAY_PRIVATE_KEY", "PAYDUNYA_PRIVATE_KEY", _default_notchpay_private_key)

if not NOTCHPAY_PUBLIC_KEY:
    NOTCHPAY_PUBLIC_KEY = _env_str_alias("PAYDUNYA_MASTER_KEY", "PAYDUNYA_PUBLIC_KEY")
if not NOTCHPAY_PRIVATE_KEY:
    NOTCHPAY_PRIVATE_KEY = _env_str_alias("PAYDUNYA_PRIVATE_KEY", "PAYDUNYA_TOKEN")

NOTCHPAY_WEBHOOK_TOKEN = _env_str_alias("NOTCHPAY_WEBHOOK_TOKEN", "PAYDUNYA_WEBHOOK_TOKEN")
NOTCHPAY_CHECKOUT_WEBHOOK_SECRET = _env_str_alias(
    "NOTCHPAY_CHECKOUT_WEBHOOK_SECRET",
    "PAYDUNYA_CHECKOUT_WEBHOOK_SECRET",
)
NOTCHPAY_DISBURSE_WEBHOOK_SECRET = _env_str_alias(
    "NOTCHPAY_DISBURSE_WEBHOOK_SECRET",
    "PAYDUNYA_DISBURSE_WEBHOOK_SECRET",
    NOTCHPAY_CHECKOUT_WEBHOOK_SECRET,
)

NOTCHPAY_CHECKOUT_CALLBACK_URL = _env_str_alias(
    "NOTCHPAY_CHECKOUT_CALLBACK_URL",
    "PAYDUNYA_CHECKOUT_CALLBACK_URL",
    BACKEND_PUBLIC_URL,
)
NOTCHPAY_CHECKOUT_RETURN_URL = _env_str_alias(
    "NOTCHPAY_CHECKOUT_RETURN_URL",
    "PAYDUNYA_CHECKOUT_RETURN_URL",
    NOTCHPAY_CHECKOUT_CALLBACK_URL,
)
NOTCHPAY_CHECKOUT_CANCEL_URL = _env_str_alias("NOTCHPAY_CHECKOUT_CANCEL_URL", "PAYDUNYA_CHECKOUT_CANCEL_URL")
NOTCHPAY_CHECKOUT_CHANNELS = _env_list_alias("NOTCHPAY_CHECKOUT_CHANNELS", "PAYDUNYA_CHECKOUT_CHANNELS")

NOTCHPAY_DISBURSE_CALLBACK_URL = _env_str_alias(
    "NOTCHPAY_DISBURSE_CALLBACK_URL",
    "PAYDUNYA_DISBURSE_CALLBACK_URL",
    f"{BACKEND_PUBLIC_URL.rstrip('/')}/api/wallets/notchpay/disburse/webhook/",
)

NOTCHPAY_MTN_NUMBER = _env_str_alias("NOTCHPAY_MTN_NUMBER", "PAYDUNYA_MTN_NUMBER", "")
NOTCHPAY_ORANGE_NUMBER = _env_str_alias("NOTCHPAY_ORANGE_NUMBER", "PAYDUNYA_ORANGE_NUMBER", "")
NOTCHPAY_DEFAULT_COUNTRY_CODE = _env_str_alias("NOTCHPAY_DEFAULT_COUNTRY_CODE", "PAYDUNYA_DEFAULT_COUNTRY_CODE")
NOTCHPAY_WITHDRAW_CHANNEL_MTN = _env_str_alias("NOTCHPAY_WITHDRAW_CHANNEL_MTN", "PAYDUNYA_WITHDRAW_MODE_MTN", "cm.mtn")
NOTCHPAY_WITHDRAW_CHANNEL_ORANGE = _env_str_alias("NOTCHPAY_WITHDRAW_CHANNEL_ORANGE", "PAYDUNYA_WITHDRAW_MODE_ORANGE", "cm.orange")
NOTCHPAY_WITHDRAW_CHANNEL_VISA = _env_str_alias("NOTCHPAY_WITHDRAW_CHANNEL_VISA", "PAYDUNYA_WITHDRAW_MODE_VISA")
NOTCHPAY_WITHDRAW_CHANNEL_MASTERCARD = _env_str_alias(
    "NOTCHPAY_WITHDRAW_CHANNEL_MASTERCARD",
    "PAYDUNYA_WITHDRAW_MODE_MASTERCARD",
)
NOTCHPAY_WITHDRAW_CHANNEL_PAYPAL = _env_str_alias("NOTCHPAY_WITHDRAW_CHANNEL_PAYPAL", "PAYDUNYA_WITHDRAW_MODE_PAYPAL")
NOTCHPAY_ONLY_MTN = _env_bool_alias("NOTCHPAY_ONLY_MTN", "PAYDUNYA_ONLY_MTN", False)
NOTCHPAY_AUTO_PAYOUT = _env_bool_alias("NOTCHPAY_AUTO_PAYOUT", "PAYDUNYA_AUTO_PAYOUT", False)

NOTCHPAY_STORE_NAME = _env_str_alias("NOTCHPAY_STORE_NAME", "PAYDUNYA_STORE_NAME", "Marche CM")
NOTCHPAY_STORE_TAGLINE = _env_str_alias("NOTCHPAY_STORE_TAGLINE", "PAYDUNYA_STORE_TAGLINE")
NOTCHPAY_STORE_POSTAL_ADDRESS = _env_str_alias("NOTCHPAY_STORE_POSTAL_ADDRESS", "PAYDUNYA_STORE_POSTAL_ADDRESS")
NOTCHPAY_STORE_PHONE = _env_str_alias("NOTCHPAY_STORE_PHONE", "PAYDUNYA_STORE_PHONE")
NOTCHPAY_STORE_WEBSITE = _env_str_alias("NOTCHPAY_STORE_WEBSITE", "PAYDUNYA_STORE_WEBSITE")
NOTCHPAY_STORE_LOGO_URL = _env_str_alias("NOTCHPAY_STORE_LOGO_URL", "PAYDUNYA_STORE_LOGO_URL")

# Backward-compat aliases (to avoid breaking code paths not yet migrated).
PAYDUNYA_ENABLED = NOTCHPAY_ENABLED
PAYDUNYA_MODE = NOTCHPAY_MODE
PAYDUNYA_API_BASE = NOTCHPAY_API_BASE
PAYDUNYA_PUBLIC_KEY = NOTCHPAY_PUBLIC_KEY
PAYDUNYA_PRIVATE_KEY = NOTCHPAY_PRIVATE_KEY
PAYDUNYA_WEBHOOK_TOKEN = NOTCHPAY_WEBHOOK_TOKEN
PAYDUNYA_CHECKOUT_WEBHOOK_SECRET = NOTCHPAY_CHECKOUT_WEBHOOK_SECRET
PAYDUNYA_DISBURSE_WEBHOOK_SECRET = NOTCHPAY_DISBURSE_WEBHOOK_SECRET
PAYDUNYA_MTN_NUMBER = NOTCHPAY_MTN_NUMBER
PAYDUNYA_ORANGE_NUMBER = NOTCHPAY_ORANGE_NUMBER
PAYDUNYA_DEFAULT_COUNTRY_CODE = NOTCHPAY_DEFAULT_COUNTRY_CODE
PAYDUNYA_WITHDRAW_MODE_MTN = NOTCHPAY_WITHDRAW_CHANNEL_MTN
PAYDUNYA_WITHDRAW_MODE_ORANGE = NOTCHPAY_WITHDRAW_CHANNEL_ORANGE
PAYDUNYA_WITHDRAW_MODE_VISA = NOTCHPAY_WITHDRAW_CHANNEL_VISA
PAYDUNYA_WITHDRAW_MODE_MASTERCARD = NOTCHPAY_WITHDRAW_CHANNEL_MASTERCARD
PAYDUNYA_WITHDRAW_MODE_PAYPAL = NOTCHPAY_WITHDRAW_CHANNEL_PAYPAL
PAYDUNYA_ONLY_MTN = NOTCHPAY_ONLY_MTN
PAYDUNYA_AUTO_PAYOUT = NOTCHPAY_AUTO_PAYOUT
PAYDUNYA_CHECKOUT_CALLBACK_URL = NOTCHPAY_CHECKOUT_CALLBACK_URL
PAYDUNYA_CHECKOUT_RETURN_URL = NOTCHPAY_CHECKOUT_RETURN_URL
PAYDUNYA_CHECKOUT_CANCEL_URL = NOTCHPAY_CHECKOUT_CANCEL_URL
PAYDUNYA_CHECKOUT_CHANNELS = NOTCHPAY_CHECKOUT_CHANNELS
PAYDUNYA_DISBURSE_CALLBACK_URL = NOTCHPAY_DISBURSE_CALLBACK_URL
PAYDUNYA_STORE_NAME = NOTCHPAY_STORE_NAME
PAYDUNYA_STORE_TAGLINE = NOTCHPAY_STORE_TAGLINE
PAYDUNYA_STORE_POSTAL_ADDRESS = NOTCHPAY_STORE_POSTAL_ADDRESS
PAYDUNYA_STORE_PHONE = NOTCHPAY_STORE_PHONE
PAYDUNYA_STORE_WEBSITE = NOTCHPAY_STORE_WEBSITE
PAYDUNYA_STORE_LOGO_URL = NOTCHPAY_STORE_LOGO_URL
WALLET_MTN_TRANSFER_CODE_TEMPLATE = os.getenv("WALLET_MTN_TRANSFER_CODE_TEMPLATE", "")
WALLET_ORANGE_TRANSFER_CODE_TEMPLATE = os.getenv("WALLET_ORANGE_TRANSFER_CODE_TEMPLATE", "")

FINOPS_PROVIDER_REAL_BALANCE = os.getenv("FINOPS_PROVIDER_REAL_BALANCE", "").strip()
FINOPS_PROVIDER_BALANCE_URL = os.getenv("FINOPS_PROVIDER_BALANCE_URL", "").strip()
FINOPS_PROVIDER_BALANCE_HTTP_METHOD = os.getenv("FINOPS_PROVIDER_BALANCE_HTTP_METHOD", "GET").strip().upper()
FINOPS_PROVIDER_BALANCE_TIMEOUT_SECONDS = _env_int("FINOPS_PROVIDER_BALANCE_TIMEOUT_SECONDS", 15)
FINOPS_PROVIDER_BALANCE_AUTH_HEADER = os.getenv("FINOPS_PROVIDER_BALANCE_AUTH_HEADER", "Authorization").strip()
FINOPS_PROVIDER_BALANCE_AUTH_TOKEN = os.getenv("FINOPS_PROVIDER_BALANCE_AUTH_TOKEN", "").strip()
FINOPS_PROVIDER_BALANCE_HEADERS = _env_json("FINOPS_PROVIDER_BALANCE_HEADERS", "{}")
FINOPS_PROVIDER_BALANCE_JSON_PATH = os.getenv("FINOPS_PROVIDER_BALANCE_JSON_PATH", "balance").strip()
FINOPS_ALERT_EMAILS = _env_list("FINOPS_ALERT_EMAILS")
FINOPS_ALERT_WEBHOOK_URL = os.getenv("FINOPS_ALERT_WEBHOOK_URL", "").strip()
FINOPS_ALERT_WEBHOOK_TIMEOUT_SECONDS = _env_int("FINOPS_ALERT_WEBHOOK_TIMEOUT_SECONDS", 10)
FINOPS_ALERT_ON_RECON_ALERT = _env_bool("FINOPS_ALERT_ON_RECON_ALERT", True)
FINOPS_ALERT_ON_RETRIES_FAILURE = _env_bool("FINOPS_ALERT_ON_RETRIES_FAILURE", True)
FINOPS_ALERT_ON_RETRIES_BACKLOG = _env_bool("FINOPS_ALERT_ON_RETRIES_BACKLOG", True)
FINOPS_RETRIES_BACKLOG_THRESHOLD = _env_int("FINOPS_RETRIES_BACKLOG_THRESHOLD", 10)

NOMINATIM_ENABLED = _env_bool("NOMINATIM_ENABLED", True)
NOMINATIM_BASE_URL = os.getenv("NOMINATIM_BASE_URL", "https://nominatim.openstreetmap.org")
NOMINATIM_USER_AGENT = os.getenv("NOMINATIM_USER_AGENT", "MarcheCM/1.0 (+admin@marche-cm.local)")
NOMINATIM_EMAIL = os.getenv("NOMINATIM_EMAIL", "")
NOMINATIM_TIMEOUT_SECONDS = int(os.getenv("NOMINATIM_TIMEOUT_SECONDS", "10"))

KYC_LIMITS = {
    0: {"per_transaction": 25000, "per_day": 50000},
    1: {"per_transaction": 200000, "per_day": 500000},
    2: {"per_transaction": 1500000, "per_day": 5000000},
}
WALLET_PIN_MAX_ATTEMPTS = _env_int("WALLET_PIN_MAX_ATTEMPTS", 5)
WALLET_PIN_LOCK_MINUTES = _env_int("WALLET_PIN_LOCK_MINUTES", 10)
SENSITIVE_ACTION_2FA_ENABLED = _env_bool("SENSITIVE_ACTION_2FA_ENABLED", True)
SENSITIVE_ACTION_CODE_TTL_MINUTES = _env_int("SENSITIVE_ACTION_CODE_TTL_MINUTES", 10)
SENSITIVE_ACTION_CODE_MAX_ATTEMPTS = _env_int("SENSITIVE_ACTION_CODE_MAX_ATTEMPTS", 5)
RECONCILIATION_REQUIRE_PROVIDER_BALANCE = _env_bool("RECONCILIATION_REQUIRE_PROVIDER_BALANCE", not DEBUG)
MAX_UPLOAD_IMAGE_MB = _env_int("MAX_UPLOAD_IMAGE_MB", 5)
MAX_UPLOAD_VIDEO_MB = _env_int("MAX_UPLOAD_VIDEO_MB", 200)
MAX_UPLOAD_DOCUMENT_MB = _env_int("MAX_UPLOAD_DOCUMENT_MB", 20)
UPLOAD_SCRUB_IMAGE_METADATA = _env_bool("UPLOAD_SCRUB_IMAGE_METADATA", True)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "structured": {
            "format": '{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "structured",
        }
    },
    "root": {"handlers": ["console"], "level": "INFO"},
}

# ---------------------------------------------------------------------------
# Startup safety validator — auto-payout (OWASP ASVS V10.2 / deny-by-default)
# ---------------------------------------------------------------------------
# Placeholder phone numbers that were previously hardcoded as defaults.
# These must NEVER appear in a live auto-payout configuration.
_PLACEHOLDER_PHONE_NUMBERS: frozenset[str] = frozenset({
    "670766331",
    "695605502",
})


def _validate_autopayout_config() -> None:
    """
    Refuse to start if auto-payout is enabled in live mode without valid phone
    numbers.  This prevents silent misconfiguration from sending money to wrong
    accounts or failing at payout time instead of at startup.

    Rules (deny-by-default):
      - NOTCHPAY_AUTO_PAYOUT=True is only allowed when NOTCHPAY_ENABLED=True.
      - In live mode (NOTCHPAY_MODE="live"), both phone numbers must be
        explicitly set and must not be placeholder values.
    """
    if not NOTCHPAY_AUTO_PAYOUT:
        return

    if not NOTCHPAY_ENABLED:
        raise ImproperlyConfigured(
            "NOTCHPAY_AUTO_PAYOUT=True requires NOTCHPAY_ENABLED=True. "
            "Either enable NotchPay or disable auto-payout."
        )

    if NOTCHPAY_MODE != "live":
        return  # sandbox/test — phone numbers are dummy by design

    errors: list[str] = []
    for env_var, value in (
        ("NOTCHPAY_MTN_NUMBER", NOTCHPAY_MTN_NUMBER),
        ("NOTCHPAY_ORANGE_NUMBER", NOTCHPAY_ORANGE_NUMBER),
    ):
        if not value or not value.strip():
            errors.append(f"{env_var} must be set when auto-payout is enabled in live mode.")
        elif value.strip() in _PLACEHOLDER_PHONE_NUMBERS:
            errors.append(
                f"{env_var}={value!r} is a placeholder value and cannot be used in live mode. "
                "Set a real payout phone number."
            )

    if errors:
        raise ImproperlyConfigured(
            "Auto-payout misconfiguration — refusing to start:\n"
            + "\n".join(f"  • {e}" for e in errors)
        )


_validate_autopayout_config()


# ---------------------------------------------------------------------------
# Startup webhook secret validator — H3 / PCI-DSS Req. 6.4
# ---------------------------------------------------------------------------
# In production (DEBUG=False), both webhook HMAC secrets MUST be configured.
# Without them the webhook verification layer rejects every incoming call,
# meaning no topup or withdrawal will ever be confirmed.  Fail at startup
# rather than silently dropping all payments in production.
# ---------------------------------------------------------------------------

def _validate_webhook_secrets() -> None:
    if DEBUG:
        return  # Local dev: verification layer still enforces auth on each call.
    if not NOTCHPAY_ENABLED:
        return  # NotchPay disabled — webhooks not in use.
    missing: list[str] = []
    if not NOTCHPAY_CHECKOUT_WEBHOOK_SECRET:
        missing.append("NOTCHPAY_CHECKOUT_WEBHOOK_SECRET")
    if not NOTCHPAY_DISBURSE_WEBHOOK_SECRET:
        missing.append("NOTCHPAY_DISBURSE_WEBHOOK_SECRET")
    if missing:
        raise ImproperlyConfigured(
            "Webhook HMAC secrets manquants — refus de demarrer en production:\n"
            + "\n".join(f"  • {s} doit etre defini" for s in missing)
            + "\nSans ces secrets, aucun paiement ne peut etre confirme via webhook."
        )


_validate_webhook_secrets()


# ---------------------------------------------------------------------------
# JWT algorithm check — M3 / OWASP ASVS V3.5.3
# ---------------------------------------------------------------------------
# Migration to RS256:
#   openssl genrsa -out jwt_private.pem 2048
#   openssl rsa -in jwt_private.pem -pubout -out jwt_public.pem
#   Set: JWT_ALGORITHM=RS256  JWT_SIGNING_KEY=<private>  JWT_VERIFYING_KEY=<public>
# ---------------------------------------------------------------------------

_jwt_verifying_key = os.getenv("JWT_VERIFYING_KEY", "").strip() or None
if _jwt_verifying_key:
    SIMPLE_JWT["VERIFYING_KEY"] = _jwt_verifying_key

if not DEBUG and SIMPLE_JWT.get("ALGORITHM", "HS256") == "HS256":
    # Audit ref: [H-002] JWT HS256 par défaut + warning seulement
    # HS256 = symmetric. A leak of SECRET_KEY (env dump, logs, backup) lets an
    # attacker forge any token. RS256/ES256 confine the blast radius to the
    # private signing key, which never leaves the secrets manager.
    if not _env_bool("ALLOW_HS256_IN_PRODUCTION", False):
        raise ImproperlyConfigured(
            "JWT_ALGORITHM=HS256 is forbidden in production. "
            "Generate an RSA keypair and set JWT_ALGORITHM=RS256, "
            "JWT_SIGNING_KEY=<private PEM>, JWT_VERIFYING_KEY=<public PEM>. "
            "Set ALLOW_HS256_IN_PRODUCTION=1 ONLY for an explicit, time-boxed migration window."
        )
    import warnings as _warnings
    _warnings.warn(
        "ALLOW_HS256_IN_PRODUCTION=1: JWT HS256 in production accepted under explicit override. "
        "This MUST be a temporary migration setting. Migrate to RS256 ASAP.",
        stacklevel=1,
    )

# RS256/ES256 require both SIGNING_KEY (private) and VERIFYING_KEY (public).
_jwt_algo = SIMPLE_JWT.get("ALGORITHM", "HS256")
if _jwt_algo in ("RS256", "RS384", "RS512", "ES256", "ES384", "ES512"):
    if not SIMPLE_JWT.get("SIGNING_KEY") or not SIMPLE_JWT.get("VERIFYING_KEY"):
        raise ImproperlyConfigured(
            f"JWT_ALGORITHM={_jwt_algo} requires both JWT_SIGNING_KEY (private PEM) "
            "and JWT_VERIFYING_KEY (public PEM) to be set."
        )

# ---------------------------------------------------------------------------
# Wallet PIN tuning — M8
# ---------------------------------------------------------------------------
# Configurable exponential backoff for PIN lockout to counter parallel brute-force.
WALLET_PIN_LOCK_MINUTES_EXTENDED = _env_int("WALLET_PIN_LOCK_MINUTES_EXTENDED", 60)

# ---------------------------------------------------------------------------
# Celery — broker + result backend
# Celery reads settings prefixed with CELERY_ (namespace="CELERY" in celery.py).
# Defaults fall back to REDIS_URL so a single env var covers both in dev.
# ---------------------------------------------------------------------------
_celery_broker_default = REDIS_URL.replace("/0", "/1") if REDIS_URL else "redis://localhost:6379/1"
_celery_result_default = REDIS_URL.replace("/0", "/2") if REDIS_URL else "redis://localhost:6379/2"

CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", _celery_broker_default).strip()
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", _celery_result_default).strip()

# ---------------------------------------------------------------------------
# Feature flags / runtime knobs read by the remediation patches.
# Audit refs: NEW-001/002, FIN-001, M-007, WS-002.
# ---------------------------------------------------------------------------
LEDGER_DOUBLE_ENTRY_ENABLED = _env_bool("LEDGER_DOUBLE_ENTRY_ENABLED", True)
WEBHOOK_REQUIRE_TIMESTAMP = _env_bool("WEBHOOK_REQUIRE_TIMESTAMP", False)
WEBHOOK_TIMESTAMP_WINDOW_SECONDS = _env_int("WEBHOOK_TIMESTAMP_WINDOW_SECONDS", 300)
WALLET_PIN_MIN_LENGTH = _env_int("WALLET_PIN_MIN_LENGTH", 6)
WALLET_PIN_VERIFY_MIN_LENGTH = _env_int("WALLET_PIN_VERIFY_MIN_LENGTH", 4)
WS_ALLOW_TOKEN_QUERY_STRING = _env_bool("WS_ALLOW_TOKEN_QUERY_STRING", False)
UPLOAD_SCRUB_IMAGE_METADATA = _env_bool("UPLOAD_SCRUB_IMAGE_METADATA", True)

# ---------------------------------------------------------------------------
# drf-spectacular — OpenAPI schema settings
# ---------------------------------------------------------------------------
SPECTACULAR_SETTINGS = {
    "TITLE": "Marché CM API",
    "DESCRIPTION": (
        "API REST du marketplace Marché CM — paiements Mobile Money (NotchPay), "
        "escrow, litiges, logistique et notifications temps réel."
    ),
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "SCHEMA_PATH_PREFIX": r"/api/",
    "COMPONENT_SPLIT_REQUEST": True,
    "ENUM_GENERATE_CHOICE_DESCRIPTION": False,
}
