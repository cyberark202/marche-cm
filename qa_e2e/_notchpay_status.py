"""Query NotchPay API directly for the payment status of our two top-up refs,
to confirm the LIVE payment succeeded even if the webhook hasn't reached us."""
import os, sys, json, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))
import django; django.setup()
from django.conf import settings

API = (settings.NOTCHPAY_API_BASE or "https://api.notchpay.co").rstrip("/")
KEY = settings.NOTCHPAY_PUBLIC_KEY
print("api:", API, "key set:", bool(KEY))

for ref in ("trx.89vFSjHhvuszmu9tXL2MBmxn", "trx.E50Hk1WJd5DoadF16KoHrPTl"):
    url = f"{API}/payments/{ref}"
    req = urllib.request.Request(url, headers={"Authorization": KEY, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:  # nosec B310
            data = json.loads(resp.read().decode())
        tx = data.get("transaction", data)
        print(f"{ref}: status={tx.get('status')} amount={tx.get('amount')} "
              f"channel={tx.get('channel')} sandbox={tx.get('sandbox')}")
    except Exception as e:
        body = ""
        try:
            body = e.read().decode()[:300]
        except Exception:
            pass
        print(f"{ref}: ERROR {type(e).__name__}: {e} {body}")
