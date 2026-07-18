# -*- coding: utf-8 -*-
import json
import sys
import urllib.request

BASE = "http://127.0.0.1:8000"


def post(path, payload, token=None):
    data = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


st, body = post("/api/auth/login/", {"email": "buyer@marche-cm.local", "password": "ChangeMe123!"})
print("login:", st)
token = body.get("access")
if not token:
    print("LOGIN FAILED", body); sys.exit(1)

st, body = post("/api/orders/", {
    "product": 9,
    "quantity": 1,
    "join_grouping": False,
    "preferred_transit_agent": 33,
    "transport_mode": "AIR",
}, token=token)
print("create order:", st)
print(json.dumps({k: body.get(k) for k in ("id", "order_type", "status", "escrow_status", "total_price", "logistics_price", "preferred_transit_agent", "seller", "buyer")}, indent=2, ensure_ascii=False))
if st >= 400:
    print("FULL ERROR:", json.dumps(body, ensure_ascii=False))
