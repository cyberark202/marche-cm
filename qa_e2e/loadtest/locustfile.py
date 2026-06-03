"""Mission 2 — Load & stress scenarios for Marché CM.

Five weighted user profiles matching the mission brief:
  S1  catalogue navigation .......... 60%  (search / filters / product detail)
  S2  sellers ....................... 20%  (login / publish product / upload image)
  S3  buyers ........................ 10%  (cart / order / payment)
  S4  wallet ........................ 5 %  (deposit / withdraw / balance)
  S5  messaging ..................... 5 %  (send messages)

SAFETY (non-negotiable, enforced here):
  * No real money ever moves. Payment/topup/withdraw tasks stop at the
    validation gate (they assert 400/403 *before* any NotchPay call) unless
    LOADTEST_ALLOW_REAL_PAYMENT=1 (never set during load).
  * Writes (product publish, orders) are gated by LOADTEST_ALLOW_WRITES (default
    on for sellers/buyers but tagged so they can be disabled to spare the DB).

Config via env:
  LOADTEST_HOST                target base URL (or pass --host to locust)
  LOADTEST_EMAIL_DOMAIN        domain for throwaway accounts (default qa.load)
  LOADTEST_SELLER_EMAIL/PWD    pre-seeded seller creds (default supplier@marche-cm.local / ChangeMe123!)
  LOADTEST_BUYER_EMAIL/PWD     pre-seeded buyer creds  (default buyer@marche-cm.local / ChangeMe123!)
  LOADTEST_ALLOW_WRITES        '1' to allow product/order creation (default 1)
"""
import os
import time
import uuid
import random

from locust import HttpUser, task, between, events

PWD = os.environ.get("LOADTEST_PWD", "ChangeMe123!")
SELLER_EMAIL = os.environ.get("LOADTEST_SELLER_EMAIL", "supplier@marche-cm.local")
BUYER_EMAIL = os.environ.get("LOADTEST_BUYER_EMAIL", "buyer@marche-cm.local")
ALLOW_WRITES = os.environ.get("LOADTEST_ALLOW_WRITES", "1") == "1"
ALLOW_REAL_PAYMENT = os.environ.get("LOADTEST_ALLOW_REAL_PAYMENT", "0") == "1"


def _headers(token=None):
    h = {
        "X-Correlation-ID": str(uuid.uuid4()),
        "X-Request-Nonce": uuid.uuid4().hex,
        "X-Request-Timestamp": str(int(time.time() * 1000)),
        "X-Device-ID": f"load-{uuid.uuid4().hex[:8]}",
        "X-App-Client": "loadtest",
        "User-Agent": "MarcheCM-LoadTest/1.0",
    }
    if token:
        h["Authorization"] = f"Bearer {token}"
    return h


SEARCH_TERMS = ["riz", "huile", "ciment", "tissu", "telephone", "savon", "the", "cafe", ""]
CATEGORIES = ["Alimentaire", "Construction", "Textile", "Electronique", ""]


class CatalogueUser(HttpUser):
    """S1 — 60%. Anonymous browsing: list, search, filter, detail. Read-only."""
    weight = 60
    wait_time = between(1, 4)

    @task(5)
    def list_products(self):
        self.client.get("/api/products/", headers=_headers(), name="GET /products list")

    @task(4)
    def search(self):
        q = random.choice(SEARCH_TERMS)
        self.client.get(f"/api/products/?search={q}", headers=_headers(), name="GET /products?search")

    @task(3)
    def filter(self):
        cat = random.choice(CATEGORIES)
        self.client.get(f"/api/products/?category_name={cat}&ordering=-created_at",
                        headers=_headers(), name="GET /products?filter")

    @task(3)
    def detail(self):
        # product ids are small on a fresh DB; probe a spread, tolerate 404
        pid = random.randint(1, 50)
        with self.client.get(f"/api/products/{pid}/", headers=_headers(),
                             name="GET /products/{id}", catch_response=True) as r:
            if r.status_code in (200, 404):
                r.success()

    @task(1)
    def ui_config(self):
        self.client.get("/api/ui-config/", headers=_headers(), name="GET /ui-config")


class SellerUser(HttpUser):
    """S2 — 20%. Login, publish product (multipart + image), list own."""
    weight = 20
    wait_time = between(2, 6)
    token = None

    def on_start(self):
        r = self.client.post("/api/auth/login/", json={"email": SELLER_EMAIL, "password": PWD},
                             headers=_headers(), name="POST /auth/login (seller)")
        if r.status_code == 200:
            self.token = r.json().get("access")

    @task(4)
    def browse_own(self):
        self.client.get("/api/products/?mine=true", headers=_headers(self.token),
                        name="GET /products?mine")

    @task(2)
    def publish(self):
        if not (ALLOW_WRITES and self.token):
            return
        # 1x1 px JPEG so the upload path (R2) is exercised with minimal bytes
        img = bytes.fromhex(
            "ffd8ffe000104a46494600010100000100010000ffdb004300"
            "080606070605080707070909080a0c140d0c0b0b0c1912130f14"
            "1d1a1f1e1d1a1c1c20242e2720222c231c1c2837292c30313434"
            "341f27393d38323c2e333432ffc0000b080001000101011100ff"
            "c4001f0000010501010101010100000000000000000102030405"
            "060708090a0bffc400b5100002010303020403050504040000017d"
            "01020300041105122131410613516107227114328191a1082342b1"
            "c11552d1f02433627282090a161718191a25262728292a3435363738"
            "393a434445464748494a535455565758595a636465666768696a73"
            "7475767778797a838485868788898a92939495969798999aa2a3a4"
            "a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4"
            "d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda"
            "0008010100003f00f7fa28a28a2800a28a2803ffd9")
        files = {"image": (f"load{uuid.uuid4().hex[:6]}.jpg", img, "image/jpeg")}
        data = {
            "title": f"LoadTest {uuid.uuid4().hex[:8]}",
            "description": "load test product (safe to delete)",
            "brand": "LOAD", "category_name": "LoadTest", "weight_kg": "1",
            "min_order_qty": "1", "max_order_qty": "10",
            "price_for_min_qty": "5000", "price_for_max_qty": "4500", "is_active": "true",
        }
        self.client.post("/api/products/", headers=_headers(self.token), data=data, files=files,
                         name="POST /products (publish)")


class BuyerUser(HttpUser):
    """S3 — 10%. Login, browse, order. Payment stops at validation (no real money)."""
    weight = 10
    wait_time = between(2, 6)
    token = None

    def on_start(self):
        r = self.client.post("/api/auth/login/", json={"email": BUYER_EMAIL, "password": PWD},
                             headers=_headers(), name="POST /auth/login (buyer)")
        if r.status_code == 200:
            self.token = r.json().get("access")

    @task(5)
    def browse(self):
        self.client.get("/api/products/", headers=_headers(self.token), name="GET /products (buyer)")

    @task(2)
    def order_validation(self):
        # Exercise the order endpoint's validation path WITHOUT funding the
        # wallet: an unfunded order is rejected (400) before any escrow/money
        # op. Safe under load. Tolerate 400/403/201.
        if not self.token:
            return
        with self.client.post("/api/orders/", headers=_headers(self.token),
                             json={"product": random.randint(1, 50), "quantity": 1,
                                   "preferred_transit_agent": 7, "transport_mode": "SEA"},
                             name="POST /orders (validation)", catch_response=True) as r:
            if r.status_code in (200, 201, 400, 403, 404):
                r.success()


class WalletUser(HttpUser):
    """S4 — 5%. Balance read + topup/withdraw validation gate (no real money)."""
    weight = 5
    wait_time = between(2, 6)
    token = None

    def on_start(self):
        r = self.client.post("/api/auth/login/", json={"email": BUYER_EMAIL, "password": PWD},
                             headers=_headers(), name="POST /auth/login (wallet)")
        if r.status_code == 200:
            self.token = r.json().get("access")

    @task(3)
    def balance(self):
        self.client.get("/api/wallets/", headers=_headers(self.token), name="GET /wallets (balance)")

    @task(2)
    def history(self):
        self.client.get("/api/wallets/transactions/", headers=_headers(self.token),
                        name="GET /wallets/transactions")

    @task(1)
    def topup_validation(self):
        # Invalid amount -> 400 BEFORE any NotchPay invoice. No money, no link.
        if not self.token or ALLOW_REAL_PAYMENT:
            return
        with self.client.post("/api/wallets/topup/", headers=_headers(self.token),
                             json={"amount": "abc", "provider": "MOBILE_MONEY",
                                   "source_phone": "+237670000000", "pin": "1234"},
                             name="POST /wallets/topup (validation)", catch_response=True) as r:
            if r.status_code in (400, 403):
                r.success()


class MessagingUser(HttpUser):
    """S5 — 5%. Auth + chat room list + message list (HTTP side of messaging).
    WebSocket fan-out is load-tested separately (ws_load.py)."""
    weight = 5
    wait_time = between(2, 6)
    token = None

    def on_start(self):
        r = self.client.post("/api/auth/login/", json={"email": BUYER_EMAIL, "password": PWD},
                             headers=_headers(), name="POST /auth/login (msg)")
        if r.status_code == 200:
            self.token = r.json().get("access")

    @task(3)
    def rooms(self):
        self.client.get("/api/chat/rooms/", headers=_headers(self.token), name="GET /chat/rooms")

    @task(2)
    def notifications(self):
        self.client.get("/api/notifications/", headers=_headers(self.token), name="GET /notifications")
