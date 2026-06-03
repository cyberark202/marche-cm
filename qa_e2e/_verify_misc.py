"""Isolated verification of the env-suspected failures: KYC submit (R2 upload,
long timeout), chat message read by participant, and R2 storage config."""
import os, sys, time, uuid
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("QA_BASE", "http://127.0.0.1:8000")
import requests
from qa import Client, django_setup

BASE = "http://127.0.0.1:8000"
PWD = "ChangeMe123!"
BUY = "buyer@marche-cm.local"


def H(tok=None):
    h = {"X-Correlation-ID": str(uuid.uuid4()), "X-Request-Nonce": uuid.uuid4().hex,
         "X-Request-Timestamp": str(int(time.time()*1000)), "X-Device-ID": "verify",
         "X-App-Client": "verify", "User-Agent": "verify"}
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    return h


buy = Client("buy"); buy.login(BUY, PWD)
sup = Client("sup"); sup.login("supplier@marche-cm.local", PWD)
print("tokens:", bool(buy.access), bool(sup.access))

# --- 1) KYC submit with LONG timeout (R2 upload) ---
t = time.time()
try:
    with open("media/product1.jpg", "rb") as fp, open("media/product2.png", "rb") as sig:
        r = requests.post(f"{BASE}/api/auth/kyc/submit/", headers=H(buy.access),
                          files={"file": ("cni.jpg", fp, "image/jpeg"),
                                 "signature": ("sig.png", sig, "image/png")},
                          data={"doc_type": "CNI", "consent_accepted": "true"}, timeout=240)
    print(f"KYC submit -> {r.status_code} ({round((time.time()-t)*1000)}ms) body={r.text[:200]}")
except Exception as e:
    print(f"KYC submit EXCEPTION after {round((time.time()-t)*1000)}ms: {type(e).__name__}: {e}")

# DB check
django_setup()
from apps.accounts.models import ComplianceDocument as CD, User
u = User.objects.filter(email__iexact=BUY).first()
doc = CD.objects.filter(user=u, doc_type="CNI").order_by("-id").first()
print("KYC DB doc:", (doc.status if doc else None), "id=", (doc.id if doc else None))

# --- 2) Chat: create room, send 3 messages as buyer, read as supplier (participant) ---
r = requests.post(f"{BASE}/api/chat/rooms/", headers={**H(buy.access), "Content-Type": "application/json"},
                  json={"name": "verify room", "participants": [5]}, timeout=60)
room_id = r.json().get("id") if r.status_code == 201 else None
print("room:", room_id, r.status_code)
for i in range(3):
    rr = requests.post(f"{BASE}/api/chat/messages/", headers={**H(buy.access), "Content-Type": "application/json"},
                       json={"room": room_id, "type": "TEXT", "content": f"msg {i}"}, timeout=60)
    print(f"  send msg {i} -> {rr.status_code}")
# read as supplier (participant id=5)
rs = requests.get(f"{BASE}/api/chat/messages/?room={room_id}", headers=H(sup.access), timeout=60)
js = rs.json()
cnt = js.get("count") if isinstance(js, dict) else (len(js) if isinstance(js, list) else "?")
print(f"supplier reads room {room_id}: status={rs.status_code} count={cnt} body={rs.text[:160]}")
# read as buyer (owner)
rb = requests.get(f"{BASE}/api/chat/messages/?room={room_id}", headers=H(buy.access), timeout=60)
jb = rb.json()
cntb = jb.get("count") if isinstance(jb, dict) else (len(jb) if isinstance(jb, list) else "?")
print(f"buyer reads room {room_id}: status={rb.status_code} count={cntb}")

# DB message count
from apps.chat.models import Message
print("DB messages in room:", Message.objects.filter(room_id=room_id).count())

# --- 3) R2 config ---
from django.conf import settings
print("R2 bucket:", repr(getattr(settings, "AWS_STORAGE_BUCKET_NAME", None)))
print("R2 endpoint:", getattr(settings, "AWS_S3_ENDPOINT_URL", None))
print("USE_S3:", getattr(settings, "USE_S3_STORAGE", None))
