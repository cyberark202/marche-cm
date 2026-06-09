"""Mission 2 — per-endpoint SQL query-count profiler (N+1 detector).

Uses Django's in-process test Client + CaptureQueriesContext, so the metric is
RTT-INDEPENDENT (the ~295ms Frankfurt round-trip and the single-process dev
server do not distort query COUNTS). High/duplicated counts on list endpoints
are the N+1 signature feeding OPTIMIZATION_PLAN.md.
"""
import os, sys, time, json
from collections import Counter

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend")))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
# test Client uses host 'testserver'; allow it regardless of ALLOWED_HOSTS.
os.environ["ALLOWED_HOSTS"] = "testserver,127.0.0.1,localhost"
os.environ["SECURE_SSL_REDIRECT"] = "False"
import django; django.setup()

from django.test import Client
from django.test.utils import CaptureQueriesContext
from django.db import connection

c = Client()


def login(email, pwd="ChangeMe123!"):
    r = c.post("/api/auth/login/", data=json.dumps({"email": email, "password": pwd}),
               content_type="application/json")
    return r.json().get("access") if r.status_code == 200 else None


def profile(method, path, token=None, body=None, label=None):
    headers = {"HTTP_USER_AGENT": "bench", "HTTP_X_APP_CLIENT": "bench"}
    if token:
        headers["HTTP_AUTHORIZATION"] = f"Bearer {token}"
    with CaptureQueriesContext(connection) as ctx:
        t = time.time()
        if method == "GET":
            r = c.get(path, **headers)
        else:
            r = c.post(path, data=json.dumps(body or {}), content_type="application/json", **headers)
        dt = round((time.time() - t) * 1000)
    n = len(ctx.captured_queries)
    # N+1 signature: collapse each SQL to its template (strip literals) and count repeats
    templates = Counter()
    for q in ctx.captured_queries:
        sql = q["sql"]
        # crude normalisation: cut at WHERE/VALUES to group similar statements
        head = sql.split(" WHERE ")[0][:80]
        templates[head] += 1
    top = templates.most_common(1)[0] if templates else ("", 0)
    n1 = f"  ⚠ N+1? '{top[0][:48]}' x{top[1]}" if top[1] >= 5 else ""
    status = r.status_code
    # try to size the result
    size = ""
    try:
        j = r.json()
        if isinstance(j, dict) and "count" in j:
            size = f" items={j.get('count')}"
        elif isinstance(j, list):
            size = f" items={len(j)}"
    except Exception:
        pass
    print(f"{(label or path):42} {status} {n:>4} queries  {dt:>6}ms{size}{n1}")
    return {"path": label or path, "status": status, "queries": n, "ms": dt,
            "top_template": top[0], "top_count": top[1]}


buy = login("buyer@marche-cm.local")
sup = login("supplier@marche-cm.local")
print("auth buyer/supplier:", bool(buy), bool(sup))
print(f"{'ENDPOINT':42} {'ST':>3} {'QRY':>4} {'TIME':>8}")
print("-" * 80)

results = []
results.append(profile("GET", "/api/products/", sup, label="GET /products (catalogue list)"))
results.append(profile("GET", "/api/products/?search=riz", sup, label="GET /products?search=riz"))
results.append(profile("GET", "/api/products/?category_name=QA&ordering=-created_at", sup, label="GET /products?filter+order"))
# product detail (first product id)
from apps.catalog.models import Product
pid = Product.objects.values_list("id", flat=True).first()
if pid:
    results.append(profile("GET", f"/api/products/{pid}/", sup, label=f"GET /products/{{id}} detail"))
results.append(profile("GET", "/api/products/mine/", sup, label="GET /products/mine"))
results.append(profile("GET", "/api/wallets/", buy, label="GET /wallets (balance)"))
results.append(profile("GET", "/api/wallets/transactions/", buy, label="GET /wallets/transactions"))
results.append(profile("GET", "/api/orders/", buy, label="GET /orders (buyer list)"))
results.append(profile("GET", "/api/notifications/", buy, label="GET /notifications"))
results.append(profile("GET", "/api/chat/rooms/", buy, label="GET /chat/rooms"))
results.append(profile("GET", "/api/ui-config/", None, label="GET /ui-config (anon)"))
results.append(profile("GET", "/api/auth/me/", buy, label="GET /auth/me"))

with open(os.path.join(os.path.dirname(__file__), "artifacts", "bench_queries.json"), "w", encoding="utf-8") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)
print("-" * 80)
worst = sorted(results, key=lambda r: r["queries"], reverse=True)[:3]
print("TOP query-count endpoints:", [(w["path"], w["queries"]) for w in worst])
