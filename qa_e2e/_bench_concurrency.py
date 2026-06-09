"""Mission 2 — illustrative concurrency probe against the LOCAL backend.

HEAVY CAVEAT: this hits the single-process dev server (runserver/Daphne) whose
sync ORM work runs against the Frankfurt DB at ~200-295ms/query. Numbers reflect
the LOCAL stack + intercontinental link, NOT Render production capacity. Used
only to show saturation behaviour + that the harness works."""
import time, statistics, sys
from concurrent.futures import ThreadPoolExecutor
import requests

BASE = "http://127.0.0.1:8000"
PATH = "/api/products/"  # public, read-only, the 60% catalogue path
HDRS = {"User-Agent": "conc-bench", "X-App-Client": "bench"}


def one():
    t = time.time()
    try:
        r = requests.get(BASE + PATH, headers=HDRS, timeout=60)
        return (time.time() - t) * 1000, r.status_code
    except Exception as e:
        return (time.time() - t) * 1000, f"ERR:{type(e).__name__}"


def run_level(concurrency, total):
    lat, codes = [], []
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=concurrency) as ex:
        for ms, code in ex.map(lambda _: one(), range(total)):
            lat.append(ms); codes.append(code)
    wall = time.time() - t0
    ok = sum(1 for c in codes if c == 200)
    errs = len(codes) - ok
    lat_sorted = sorted(lat)
    def pct(p):
        return round(lat_sorted[min(len(lat_sorted) - 1, int(len(lat_sorted) * p))], 0)
    rps = round(total / wall, 1)
    print(f"conc={concurrency:>3} n={total:>3} | RPS={rps:>5} | "
          f"p50={pct(0.5):>6}ms p95={pct(0.95):>7}ms p99={pct(0.99):>7}ms max={round(max(lat)):>6}ms | "
          f"ok={ok} err={errs}")
    return {"concurrency": concurrency, "total": total, "rps": rps,
            "p50": pct(0.5), "p95": pct(0.95), "p99": pct(0.99), "ok": ok, "err": errs}


if __name__ == "__main__":
    print(f"Target {BASE}{PATH} (LOCAL dev-server + Frankfurt DB ~200ms/query)")
    out = []
    for conc, total in [(1, 5), (10, 30), (25, 50), (50, 100)]:
        out.append(run_level(conc, total))
    import json, os
    with open(os.path.join(os.path.dirname(__file__), "artifacts", "bench_concurrency.json"), "w") as f:
        json.dump(out, f, indent=2)
