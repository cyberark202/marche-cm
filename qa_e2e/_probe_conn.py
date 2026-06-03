"""Connectivity probe for the production data stores (read-only).

Loads backend/marche-cm.env explicitly (NOT the local override) and verifies we
can reach the Render Postgres + Redis from this machine. Prints only safe
diagnostics — never the credentials themselves.
"""
import os
import sys
from urllib.parse import urlparse
from dotenv import dotenv_values

HERE = os.path.dirname(__file__)
ENV = os.path.abspath(os.path.join(HERE, "..", "backend", "marche-cm.env"))
cfg = dotenv_values(ENV)

db_url = (cfg.get("DATABASE_URL") or "").strip()
redis_url = (cfg.get("REDIS_URL") or "").strip()

print("== ENV ==", ENV)
p = urlparse(db_url)
print(f"PG host={p.hostname} port={p.port} db={(p.path or '').lstrip('/')}")
rp = urlparse(redis_url)
print(f"REDIS scheme={rp.scheme} host={rp.hostname} port={rp.port}")

# ── Postgres ───────────────────────────────────────────────────────────────
try:
    import psycopg
    t = __import__("time").time()
    with psycopg.connect(db_url, connect_timeout=10) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT version()")
            ver = cur.fetchone()[0]
            cur.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
            ntables = cur.fetchone()[0]
            # row counts on key tables, tolerant of missing tables
            counts = {}
            for tbl in ("accounts_user", "catalog_product", "orders_order",
                        "wallets_wallet", "escrow_escrowhold", "disputes_disputecase"):
                try:
                    cur.execute(f"SELECT count(*) FROM {tbl}")
                    counts[tbl] = cur.fetchone()[0]
                except Exception as e:
                    counts[tbl] = f"ERR {type(e).__name__}"
                    conn.rollback()
    dt = round((__import__("time").time() - t) * 1000)
    print(f"PG OK ({dt}ms) {ver.split(',')[0]}")
    print(f"PG public tables: {ntables}")
    for k, v in counts.items():
        print(f"   {k}: {v}")
except Exception as e:
    print(f"PG FAIL: {type(e).__name__}: {e}")

# ── Redis ──────────────────────────────────────────────────────────────────
try:
    import redis
    t = __import__("time").time()
    r = redis.from_url(redis_url, socket_connect_timeout=10, ssl_cert_reqs=None)
    pong = r.ping()
    dbsize = r.dbsize()
    dt = round((__import__("time").time() - t) * 1000)
    print(f"REDIS OK ({dt}ms) ping={pong} dbsize={dbsize}")
except Exception as e:
    print(f"REDIS FAIL: {type(e).__name__}: {e}")
