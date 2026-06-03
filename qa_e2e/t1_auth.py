"""E2E batch 1 — Authentication & role isolation. Real HTTP against live server."""
import time
from qa import Client, record

RUN = str(int(time.time()))
PWD = "ChangeMe123!"


def uniq(prefix):
    return f"{prefix}{RUN}@qa.test"


def main():
    anon = Client("anon")

    # --- T1.1 Register buyer (Clients app) ---
    buyer_email = uniq("buyer")
    r = anon.req("POST", "/api/auth/register/", json_body={
        "name": "QA Buyer", "email": buyer_email, "phone_number": "+237690000001",
        "password": PWD,
    }, auth=False, note="register buyer")
    ok = r is not None and r.status_code in (200, 201)
    role = (r.json().get("user", {}) or {}).get("role") if ok and isinstance(r.json(), dict) else None
    # some APIs return user nested, some flat — capture both
    body = r.json() if ok else {}
    role = role or body.get("role")
    record("T1.1", "Inscription acheteur via /register/", "critical", ok,
           "201 + compte role=BUYER", f"status={r.status_code if r else 'NA'} role={role} body={str(body)[:200]}",
           endpoint="/api/auth/register/", be_file="apps/accounts/views.py:RegisterView")

    # --- T1.2 Register seller (Pro app) role=SUPPLIER ---
    sup_email = uniq("sup")
    r = anon.req("POST", "/api/auth/register/seller/", json_body={
        "name": "QA Supplier", "email": sup_email, "phone_number": "+237690000002",
        "password": PWD, "role": "SUPPLIER",
    }, auth=False, note="register supplier")
    ok = r is not None and r.status_code in (200, 201)
    record("T1.2", "Inscription fournisseur via /register/seller/ (role=SUPPLIER)", "critical", ok,
           "201", f"status={r.status_code if r else 'NA'} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/register/seller/", be_file="apps/accounts/views.py:SellerRegisterView")

    # --- T1.3 Register wholesaler ---
    wh_email = uniq("wh")
    r = anon.req("POST", "/api/auth/register/seller/", json_body={
        "name": "QA Wholesaler", "email": wh_email, "phone_number": "+237690000003",
        "password": PWD, "role": "WHOLESALER",
    }, auth=False, note="register wholesaler")
    record("T1.3", "Inscription grossiste via /register/seller/ (role=WHOLESALER)", "major",
           r is not None and r.status_code in (200, 201),
           "201", f"status={r.status_code if r else 'NA'} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/register/seller/")

    # --- T1.4 Register driver ---
    drv_email = uniq("drv")
    r = anon.req("POST", "/api/auth/register/driver/", json_body={
        "name": "QA Driver", "email": drv_email, "phone_number": "+237690000004",
        "password": PWD,
    }, auth=False, note="register driver")
    record("T1.4", "Inscription livreur via /register/driver/", "critical",
           r is not None and r.status_code in (200, 201),
           "201", f"status={r.status_code if r else 'NA'} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/register/driver/")

    # --- T1.5 SECURITY: privilege escalation via seller endpoint role=GENERAL_ADMIN ---
    r = anon.req("POST", "/api/auth/register/seller/", json_body={
        "name": "QA Evil", "email": uniq("evil"), "phone_number": "+237690000005",
        "password": PWD, "role": "GENERAL_ADMIN",
    }, auth=False, note="privesc admin")
    # Acceptable: rejected (400) OR coerced to a non-admin role. FAIL if a GENERAL_ADMIN is created.
    created_admin = False
    if r is not None and r.status_code in (200, 201):
        b = r.json() if isinstance(r.json(), dict) else {}
        rr = (b.get("user", {}) or {}).get("role") or b.get("role")
        created_admin = (rr == "GENERAL_ADMIN")
    record("T1.5", "Escalade de privilège: register/seller role=GENERAL_ADMIN", "critical",
           not created_admin,
           "rejet ou rôle non-admin", f"status={r.status_code if r else 'NA'} created_admin={created_admin} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/register/seller/", be_file="apps/accounts/serializers.py")

    # --- T1.6 SECURITY: buyer endpoint cannot set role (role injection) ---
    r = anon.req("POST", "/api/auth/register/", json_body={
        "name": "QA RoleInj", "email": uniq("rinj"), "phone_number": "+237690000006",
        "password": PWD, "role": "SUPPLIER",
    }, auth=False, note="role injection on buyer endpoint")
    injected = False
    if r is not None and r.status_code in (200, 201):
        b = r.json() if isinstance(r.json(), dict) else {}
        rr = (b.get("user", {}) or {}).get("role") or b.get("role")
        injected = (rr not in (None, "BUYER"))
    record("T1.6", "Injection de rôle sur /register/ (doit forcer BUYER)", "critical",
           not injected,
           "rôle = BUYER imposé", f"status={r.status_code if r else 'NA'} injected={injected} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/register/")

    # --- T1.7 Duplicate email ---
    r = anon.req("POST", "/api/auth/register/", json_body={
        "name": "Dup", "email": buyer_email, "phone_number": "+237690000007",
        "password": PWD,
    }, auth=False, note="duplicate email")
    record("T1.7", "Email en doublon rejeté", "major",
           r is not None and r.status_code == 400,
           "400 (email déjà utilisé)", f"status={r.status_code if r else 'NA'} body={r.text[:150] if r else ''}",
           endpoint="/api/auth/register/")

    # --- T1.8 Invalid email format ---
    r = anon.req("POST", "/api/auth/register/", json_body={
        "name": "Bad", "email": "notanemail", "phone_number": "+237690000008",
        "password": PWD,
    }, auth=False, note="invalid email")
    record("T1.8", "Email invalide rejeté", "minor",
           r is not None and r.status_code == 400,
           "400", f"status={r.status_code if r else 'NA'} body={r.text[:150] if r else ''}",
           endpoint="/api/auth/register/")

    # --- T1.9 Weak password ---
    r = anon.req("POST", "/api/auth/register/", json_body={
        "name": "Weak", "email": uniq("weak"), "phone_number": "+237690000009",
        "password": "123",
    }, auth=False, note="weak password")
    record("T1.9", "Mot de passe faible rejeté", "major",
           r is not None and r.status_code == 400,
           "400 (password validators)", f"status={r.status_code if r else 'NA'} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/register/")

    # --- T1.10 Login OK + JWT shape ---
    c = Client("buyer")
    r = c.login(buyer_email, PWD)
    has_tokens = bool(c.access and c.refresh)
    record("T1.10", "Login acheteur renvoie access+refresh+user", "critical",
           r is not None and r.status_code == 200 and has_tokens,
           "200 + tokens", f"status={r.status_code if r else 'NA'} tokens={has_tokens}",
           endpoint="/api/auth/login/")

    # --- T1.11 Login wrong password ---
    r = anon.req("POST", "/api/auth/login/", json_body={"email": buyer_email, "password": "WrongPass999!"},
                 auth=False, note="wrong password")
    record("T1.11", "Login mauvais mot de passe rejeté", "critical",
           r is not None and r.status_code in (400, 401),
           "401/400", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/login/")

    # --- T1.12 Login nonexistent user (enumeration timing aside) ---
    r = anon.req("POST", "/api/auth/login/", json_body={"email": "ghost-no-such@qa.test", "password": PWD},
                 auth=False, note="nonexistent user")
    record("T1.12", "Login utilisateur inexistant rejeté", "major",
           r is not None and r.status_code in (400, 401),
           "401/400", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/login/")

    # --- T1.13 /me with token ---
    r = c.req("GET", "/api/auth/me/", note="me authed")
    me_ok = r is not None and r.status_code == 200 and isinstance(r.json(), dict) and r.json().get("email") == buyer_email
    record("T1.13", "/api/auth/me/ renvoie l'utilisateur courant", "major",
           me_ok, "200 + email courant", f"status={r.status_code if r else 'NA'} body={r.text[:150] if r else ''}",
           endpoint="/api/auth/me/")

    # --- T1.14 /me without token ---
    r = anon.req("GET", "/api/auth/me/", auth=False, note="me anon")
    record("T1.14", "/api/auth/me/ refuse sans token", "critical",
           r is not None and r.status_code in (401, 403),
           "401/403", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/me/")

    # --- T1.15 Refresh token ---
    r = anon.req("POST", "/api/auth/refresh/", json_body={"refresh": c.refresh}, auth=False, note="refresh")
    new_access = r.json().get("access") if (r is not None and r.status_code == 200 and isinstance(r.json(), dict)) else None
    record("T1.15", "Refresh JWT renvoie un nouvel access", "major",
           bool(new_access), "200 + nouveau access", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/refresh/")

    # --- T1.16 Tampered JWT rejected ---
    bad = (c.access[:-3] + "AAA") if c.access else "x.y.z"
    r = anon.req("GET", "/api/auth/me/", auth=False, extra_headers={"Authorization": f"Bearer {bad}"}, note="tampered jwt")
    record("T1.16", "JWT falsifié rejeté", "critical",
           r is not None and r.status_code in (401, 403),
           "401/403", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/me/")

    # --- T1.17 Logout then refresh should fail (blacklist) ---
    r = c.req("POST", "/api/auth/logout/", json_body={"refresh": c.refresh}, note="logout")
    logout_status = r.status_code if r else None
    r2 = anon.req("POST", "/api/auth/refresh/", json_body={"refresh": c.refresh}, auth=False, note="refresh after logout")
    refresh_blocked = r2 is not None and r2.status_code in (400, 401)
    record("T1.17", "Logout invalide le refresh (blacklist)", "major",
           refresh_blocked,
           "refresh post-logout rejeté (401/400)",
           f"logout={logout_status} refresh_after={r2.status_code if r2 else 'NA'}",
           endpoint="/api/auth/logout/", be_file="apps/accounts/views.py:LogoutView")

    return {"buyer": buyer_email, "supplier": sup_email, "wholesaler": wh_email, "driver": drv_email}


if __name__ == "__main__":
    out = main()
    print("EMAILS:", out)
