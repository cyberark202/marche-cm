"""Measure per-operation RTT to the prod stores + deployed backend, to gauge
load-test feasibility from this client."""
import os, time, statistics
from urllib.parse import urlparse
from dotenv import dotenv_values

HERE = os.path.dirname(__file__)
cfg = dotenv_values(os.path.abspath(os.path.join(HERE, "..", "backend", "marche-cm.env")))
db_url = (cfg.get("DATABASE_URL") or "").strip()
redis_url = (cfg.get("REDIS_URL") or "").strip()
public = (cfg.get("BACKEND_PUBLIC_URL") or "").strip()

def stats(name, samples):
    if not samples:
        print(f"{name}: no samples"); return
    samples_ms = [round(s*1000,1) for s in samples]
    print(f"{name}: n={len(samples)} min={min(samples_ms)} p50={round(statistics.median(samples_ms),1)} max={max(samples_ms)} ms")

# PG per-query RTT on a warm connection
try:
    import psycopg
    with psycopg.connect(db_url, connect_timeout=15) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")  # warm
            xs = []
            for _ in range(10):
                t=time.time(); cur.execute("SELECT 1"); cur.fetchone(); xs.append(time.time()-t)
    stats("PG SELECT1 (warm)", xs)
except Exception as e:
    print("PG probe FAIL", type(e).__name__, e)

# Redis per-PING RTT on a warm connection
try:
    import redis
    r = redis.from_url(redis_url, socket_connect_timeout=15, ssl_cert_reqs=None)
    r.ping()  # warm
    xs=[]
    for _ in range(10):
        t=time.time(); r.ping(); xs.append(time.time()-t)
    stats("REDIS PING (warm)", xs)
except Exception as e:
    print("REDIS probe FAIL", type(e).__name__, e)

# HTTP latency to deployed backend health endpoint
try:
    import requests
    url = public.rstrip('/') + "/api/health/"
    s = requests.Session()
    r0 = s.get(url, timeout=30)  # warm + status
    print(f"HTTP {url} -> {r0.status_code}")
    xs=[]
    for _ in range(8):
        t=time.time(); s.get(url, timeout=30); xs.append(time.time()-t)
    stats("HTTP /api/health/ (warm)", xs)
except Exception as e:
    print("HTTP probe FAIL", type(e).__name__, e)
