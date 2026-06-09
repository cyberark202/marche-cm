"""Create a REAL NotchPay LIVE top-up for a small amount. The owner approves the
Mobile Money debit on their phone; the webhook (ngrok -> local) then credits the
wallet. Prints the checkout URL / reference and the pre-topup balance so the
credit can be verified afterwards."""
import os, sys, time, uuid, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("QA_BASE", "http://127.0.0.1:8000")
import requests
from qa import Client, django_setup

BASE = "http://127.0.0.1:8000"
PWD = "ChangeMe123!"
BUY = "buyer@marche-cm.local"
PHONE = os.environ.get("MOMO_PHONE", "+237670766331")
AMOUNT = os.environ.get("MOMO_AMOUNT", "500")

buy = Client("buyer"); buy.login(BUY, PWD)

# balance before
django_setup()
from apps.accounts.models import User
from apps.wallets.models import Wallet
u = User.objects.get(email__iexact=BUY)
w, _ = Wallet.objects.get_or_create(owner=u)
w.refresh_from_db()
print(f"WALLET BEFORE: available={w.available_balance} (wallet_id={w.id}, user_id={u.id})")

h = {"X-Correlation-ID": str(uuid.uuid4()), "X-Request-Nonce": uuid.uuid4().hex,
     "X-Request-Timestamp": str(int(time.time()*1000)), "X-Device-ID": "topup",
     "X-App-Client": "topup", "User-Agent": "topup", "Content-Type": "application/json",
     "Authorization": f"Bearer {buy.access}"}
payload = {"amount": AMOUNT, "provider": "MOBILE_MONEY", "source_phone": PHONE, "pin": "1234"}
print("POST /api/wallets/topup/", payload)
r = requests.post(f"{BASE}/api/wallets/topup/", headers=h, data=json.dumps(payload), timeout=120)
print(f"STATUS {r.status_code}")
try:
    j = r.json()
    print("RESPONSE:", json.dumps(j, ensure_ascii=False, indent=2)[:1200])
except Exception:
    print("BODY:", r.text[:800])
