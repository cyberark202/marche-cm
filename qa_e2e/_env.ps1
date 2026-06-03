# Shared env for the prod-connected LOCAL run (Mission 1 E2E).
# settings.py loads backend/marche-cm.env (local.env renamed to .bak); these
# $env overrides win because python-dotenv load_dotenv(override=False) does not
# clobber variables already present in the process environment.
$env:PYTHONPATH = "e:\project\Marche CM\backend"
$env:DJANGO_SETTINGS_MODULE = "config.settings"

# Local + ngrok host wiring
$env:ALLOWED_HOSTS = "127.0.0.1,localhost,choirlike-niki-phototactically.ngrok-free.dev"
$env:BACKEND_PUBLIC_URL = "https://choirlike-niki-phototactically.ngrok-free.dev"

# Allow plain-HTTP loopback so the harness can hit http://127.0.0.1:8000 directly
# (ngrok HTTPS is used only for the NotchPay webhook callback).
$env:SECURE_SSL_REDIRECT = "False"
$env:SESSION_COOKIE_SECURE = "False"
$env:CSRF_COOKIE_SECURE = "False"

# Redis (Render Key Value) refuses this machine's IP (not on the allowlist),
# which made every channel_layer/cache/lock op fail with "Client IP address is
# not in the allowlist" and turned realtime fan-out into 500s. For a faithful
# single-process local audit we use in-memory channels + LocMemCache instead
# (the prod DB is untouched). A single space strips to "" in settings.py, which
# selects the in-memory backends — and survives PowerShell's empty-var handling.
# To use the REAL Redis instead, allowlist this IP on Render and restore the
# rediss:// URLs below.
$env:REDIS_URL = " "
$env:CACHE_URL = " "

# Route NotchPay callbacks to the local backend through ngrok.
$env:NOTCHPAY_CHECKOUT_CALLBACK_URL = "https://choirlike-niki-phototactically.ngrok-free.dev/api/wallets/notchpay/checkout/webhook/"
$env:NOTCHPAY_DISBURSE_CALLBACK_URL = "https://choirlike-niki-phototactically.ngrok-free.dev/api/wallets/notchpay/disburse/webhook/"

# CORS/CSRF for the four Flutter web apps + ngrok (DEBUG=False disables the
# auto localhost regex, so list origins explicitly).
$env:CORS_ALLOWED_ORIGINS = "http://localhost:5000,http://localhost:5001,http://localhost:5002,http://localhost:5003,http://127.0.0.1:5000,http://127.0.0.1:5001,http://127.0.0.1:5002,http://127.0.0.1:5003,https://choirlike-niki-phototactically.ngrok-free.dev"
$env:CSRF_TRUSTED_ORIGINS = "https://choirlike-niki-phototactically.ngrok-free.dev,http://localhost:5000,http://localhost:5001,http://localhost:5002,http://localhost:5003"
