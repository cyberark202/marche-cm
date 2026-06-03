"""Final live confirmations:
 (A) Shipment dispute with the CORRECT field names (reason/details).
 (B) Admin suspend -> buyer login blocked -> unsuspend -> login restored (M-6).
Always unsuspends in a finally block so prod is left clean."""
import os, sys, time, uuid
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.chdir(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("QA_BASE", "http://127.0.0.1:8000")
from qa import Client, S, B, django_setup

PWD = "ChangeMe123!"

adm = Client("admin"); adm.login("admin@marche-cm.local", PWD)
buy = Client("buyer"); buy.login("buyer@marche-cm.local", PWD)
print("tokens adm/buy:", bool(adm.access), bool(buy.access))

# --- (A) open dispute on an existing buyer shipment with correct fields ---
django_setup()
from apps.logistics.models import Shipment
sh = Shipment.objects.filter(order__buyer__email__iexact="buyer@marche-cm.local").order_by("-id").first()
print("dispute target shipment:", (sh.id if sh else None), "state:", (sh.status if sh else None))
if sh:
    r = buy.req("POST", f"/api/shipments/{sh.id}/open_dispute/",
                json_body={"reason": "QUALITY_DEFECT", "details": "Produit defectueux QA (verif finale)"},
                note="open dispute correct fields")
    print(f"OPEN_DISPUTE (reason/details) -> {S(r)} body={B(r,180)}")

# --- (B) suspend / unsuspend flow ---
buyer_id = 8
try:
    r = adm.req("POST", f"/api/users/{buyer_id}/suspend/", json_body={"reason": "QA verif M-6"}, note="suspend")
    print(f"SUSPEND -> {S(r)} body={B(r,120)}")
    # suspended buyer must not be able to log in
    blocked = Client("buyer2")
    rb = blocked.req("POST", "/api/auth/login/", json_body={"email": "buyer@marche-cm.local", "password": PWD},
                     auth=False, note="login while suspended")
    print(f"LOGIN WHILE SUSPENDED -> {S(rb)} body={B(rb,120)}")
finally:
    r = adm.req("POST", f"/api/users/{buyer_id}/unsuspend/", json_body={}, note="unsuspend")
    print(f"UNSUSPEND -> {S(r)} body={B(r,120)}")
    restored = Client("buyer3")
    rr = restored.req("POST", "/api/auth/login/", json_body={"email": "buyer@marche-cm.local", "password": PWD},
                      auth=False, note="login after unsuspend")
    print(f"LOGIN AFTER UNSUSPEND -> {S(rr)} hasToken={bool(rr is not None and rr.status_code==200 and rr.json().get('access'))}")
