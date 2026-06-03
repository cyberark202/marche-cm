"""Shared E2E test harness for Marché CM — real HTTP against live backend.

Logs every request/response to qa_e2e/artifacts/calls.jsonl and prints a
human-readable trace. Test results are recorded via record() and dumped to
results.jsonl so the final report is built from real observations only.
"""
import json
import os
import time
import uuid
import datetime as dt

BASE = os.environ.get("QA_BASE", "http://127.0.0.1:8000")
ART = os.path.join(os.path.dirname(__file__), "artifacts")
os.makedirs(ART, exist_ok=True)
CALLS = os.path.join(ART, "calls.jsonl")
RESULTS = os.path.join(ART, "results.jsonl")

import requests


def _log(path, obj):
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False, default=str) + "\n")


class Client:
    def __init__(self, label="anon"):
        self.s = requests.Session()
        self.label = label
        self.access = None
        self.refresh = None
        self.user = None

    def _headers(self, extra=None, auth=True):
        h = {
            "X-Correlation-ID": str(uuid.uuid4()),
            "X-Request-Nonce": uuid.uuid4().hex,
            "X-Request-Timestamp": str(int(time.time() * 1000)),
            "X-Device-ID": f"qa-device-{self.label}",
            "X-App-Client": "qa-e2e",
        }
        if auth and self.access:
            h["Authorization"] = f"Bearer {self.access}"
        if extra:
            h.update(extra)
        return h

    def req(self, method, path, *, json_body=None, data=None, files=None,
            auth=True, extra_headers=None, expect=None, note=""):
        url = path if path.startswith("http") else BASE + path
        headers = self._headers(extra_headers, auth=auth)
        if files is None and json_body is not None:
            headers["Content-Type"] = "application/json"
        t0 = time.time()
        try:
            r = self.s.request(
                method, url, headers=headers,
                data=json.dumps(json_body) if (json_body is not None and files is None) else data,
                files=files, timeout=60,
            )
        except Exception as e:
            entry = {"ts": dt.datetime.now().isoformat(), "label": self.label,
                     "method": method, "url": url, "error": str(e), "note": note}
            _log(CALLS, entry)
            print(f"[{self.label}] {method} {path} -> EXCEPTION {e}")
            return None
        dur = round((time.time() - t0) * 1000, 1)
        body_preview = r.text[:2000]
        try:
            parsed = r.json()
        except Exception:
            parsed = None
        entry = {
            "ts": dt.datetime.now().isoformat(), "label": self.label,
            "method": method, "url": url, "status": r.status_code,
            "ms": dur, "bytes": len(r.content), "note": note,
            "req_body": json_body if files is None else "<multipart>",
            "resp": parsed if parsed is not None else body_preview,
        }
        _log(CALLS, entry)
        ok = "" if expect is None else (" OK" if r.status_code in (expect if isinstance(expect, (list, tuple)) else [expect]) else f" !!! EXPECTED {expect}")
        print(f"[{self.label}] {method} {path} -> {r.status_code} ({dur}ms, {len(r.content)}b){ok} {note}")
        r._qa = entry
        return r

    def login(self, email, password):
        r = self.req("POST", "/api/auth/login/", json_body={"email": email, "password": password}, auth=False, note=f"login {email}")
        if r is not None and r.status_code == 200:
            d = r.json()
            self.access = d.get("access")
            self.refresh = d.get("refresh")
            self.user = d.get("user")
        return r


def S(r):
    """Safe status accessor — requests.Response is falsy on 4xx/5xx, so never
    use `r if r else` to read status. Returns int status or 'NA'."""
    return r.status_code if r is not None else "NA"


def B(r, n=200):
    return (r.text[:n] if r is not None else "")


def record(test_id, name, severity, passed, expected, observed, endpoint="",
           fe_file="", be_file="", repro="", note=""):
    obj = {
        "test_id": test_id, "name": name, "severity": severity,
        "passed": bool(passed), "expected": expected, "observed": observed,
        "endpoint": endpoint, "fe_file": fe_file, "be_file": be_file,
        "repro": repro, "note": note, "ts": dt.datetime.now().isoformat(),
    }
    _log(RESULTS, obj)
    flag = "PASS" if passed else "FAIL"
    print(f"  >> [{flag}] {test_id} ({severity}) {name}")
    if not passed:
        print(f"     expected: {expected}")
        print(f"     observed: {observed}")
    return obj


def reset_results():
    for p in (CALLS, RESULTS):
        if os.path.exists(p):
            os.remove(p)


# ── Django ORM access for DB-level verification ────────────────────────────
_DJANGO_READY = False


def django_setup():
    """Make Django ORM available so tests can verify DB state directly."""
    global _DJANGO_READY
    if _DJANGO_READY:
        return
    import sys
    backend = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend"))
    if backend not in sys.path:
        sys.path.insert(0, backend)
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    import django
    django.setup()
    _DJANGO_READY = True


def set_sensitive_otp(user_email, action_key, known_code="654321"):
    """After the real request endpoint has issued a challenge, overwrite its
    code_hash with a known value so OTP-gated flows can be exercised E2E.
    Returns (challenge_token, known_code). The email delivery channel (console
    backend in local) is the only thing bypassed; the verify/expiry/single-use
    logic is still exercised for real."""
    django_setup()
    from django.contrib.auth.hashers import make_password
    from django.utils import timezone
    from apps.accounts.models import User
    from apps.accounts.security import SensitiveActionChallenge
    u = User.objects.filter(email__iexact=user_email).first()
    ch = (SensitiveActionChallenge.objects
          .filter(user=u, action_key=action_key, used_at__isnull=True,
                  expires_at__gt=timezone.now())
          .order_by("-id").first())
    if not ch:
        return None, None
    ch.code_hash = make_password(known_code)
    ch.attempts = 0
    ch.save(update_fields=["code_hash", "attempts"])
    return ch.challenge_token, known_code


if __name__ == "__main__":
    # smoke
    c = Client("smoke")
    c.req("GET", "/api/health/", auth=False, expect=200)
