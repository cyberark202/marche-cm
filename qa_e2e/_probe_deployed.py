"""Diagnose the deployed Render backend: which paths answer, what status, what
server banner. Helps decide whether Mission 2 can target it."""
import requests, time

BASE = "https://marche-cm-backend.onrender.com"
HDRS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) QA-Probe",
    "X-Correlation-ID": "probe-1",
    "X-App-Client": "qa-e2e",
}
paths = ["/api/health/", "/api/ui-config/", "/api/schema/", "/", "/api/", "/admin/login/"]
s = requests.Session()
for p in paths:
    try:
        t = time.time()
        r = s.get(BASE + p, headers=HDRS, timeout=30, allow_redirects=False)
        dt = round((time.time()-t)*1000)
        server = r.headers.get("Server", "")
        loc = r.headers.get("Location", "")
        ct = r.headers.get("Content-Type", "")
        print(f"{p:18} -> {r.status_code} ({dt}ms) server={server!r} ct={ct!r} loc={loc!r} len={len(r.content)}")
        if p == "/api/health/":
            print("    body:", r.text[:200])
    except Exception as e:
        print(f"{p:18} -> ERR {type(e).__name__}: {e}")
