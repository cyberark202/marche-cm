"""E2E batch 10 — Security: authz, JWT, IDOR, SQLi, XSS, traversal, headers, throttling."""
import time
from datetime import timedelta
from qa import Client, record, S, B, django_setup

PWD = "ChangeMe123!"; BUY = "buyer@marche-cm.local"; SUP = "supplier@marche-cm.local"


def main():
    anon = Client("anon")
    buy = Client("buyer"); buy.login(BUY, PWD)

    # T10.1 Unauthenticated access to protected endpoints
    protected = ["/api/orders/", "/api/wallets/", "/api/auth/me/", "/api/notifications/", "/api/disputes/"]
    fails = []
    for ep in protected:
        r = anon.req("GET", ep, auth=False, note=f"unauth {ep}")
        if S(r) not in (401, 403):
            fails.append(f"{ep}={S(r)}")
    record("T10.1", "Endpoints protégés refusent l'accès non authentifié", "critical",
           not fails, "401/403 partout", f"exceptions={fails or 'aucune'}", endpoint="(divers protégés)")

    # T10.2 Expired JWT rejected
    import qa
    if qa.is_remote():
        expired = qa.remote_eval("""
from rest_framework_simplejwt.tokens import AccessToken
from apps.accounts.models import User
from django.utils import timezone
from datetime import timedelta
u = User.objects.get(email__iexact='buyer@marche-cm.local')
tok = AccessToken.for_user(u)
tok.set_exp(from_time=timezone.now() - timedelta(hours=2), lifetime=timedelta(seconds=1))
val = str(tok)
""", "val")
    else:
        django_setup()
        from rest_framework_simplejwt.tokens import AccessToken
        from apps.accounts.models import User
        u = User.objects.get(email__iexact=BUY)
        tok = AccessToken.for_user(u)
        from django.utils import timezone
        tok.set_exp(from_time=timezone.now() - timedelta(hours=2), lifetime=timedelta(seconds=1))
        expired = str(tok)
    r = anon.req("GET", "/api/auth/me/", auth=False, extra_headers={"Authorization": f"Bearer {expired}"}, note="expired jwt")
    record("T10.2", "JWT expiré rejeté", "critical", S(r) == 401,
           "401", f"status={S(r)} body={B(r,120)}", endpoint="GET /api/auth/me/")

    # T10.3 IDOR: buyer cannot read another user's record
    r = buy.req("GET", "/api/users/7/", note="idor user 7 (admin)")
    record("T10.3", "IDOR utilisateur: un acheteur ne voit pas un autre compte (ni l'admin)", "critical",
           S(r) == 404, "404", f"status={S(r)}", endpoint="GET /api/users/{id}/", be_file="apps/accounts/views.py:UserViewSet.get_queryset")

    # T10.4 SQL injection in product search q
    inj = "' OR 1=1;-- "
    r = anon.req("GET", f"/api/products/?q={inj}", auth=False, note="sqli products q")
    no_crash = S(r) == 200
    record("T10.4", "Injection SQL dans la recherche produits neutralisée (ORM paramétré)", "critical",
           no_crash, "200 sans erreur ni dump", f"status={S(r)} body={B(r,80)}", endpoint="GET /api/products/?q=")

    # T10.5 SQL injection via numeric id path
    r = anon.req("GET", "/api/products/1%20OR%201=1/", auth=False, note="sqli path")
    record("T10.5", "Injection SQL via id de chemin neutralisée", "major", S(r) in (404, 400),
           "404/400", f"status={S(r)}", endpoint="GET /api/products/{id}/")

    # T10.6 Stored XSS payload in product title (supplier) — stored as data, JSON transport
    sup = Client("supplier"); sup.login(SUP, PWD)
    xss = "<script>alert('xss')</script>"
    import os
    with open(os.path.join("media", "product1.jpg"), "rb") as fp:
        r = sup.req("POST", "/api/products/", files={"image": ("x.jpg", fp, "image/jpeg")},
                    data={"title": xss, "description": "d", "brand": "b", "category_name": "QA Catégorie",
                          "weight_kg": "1", "min_order_qty": "1", "max_order_qty": "2",
                          "price_for_min_qty": "100", "price_for_max_qty": "100", "is_active": "true"}, note="xss product")
    stored_title = r.json().get("title") if S(r) == 201 else None
    ctype = r.headers.get("Content-Type", "") if r is not None else ""
    record("T10.6", "Payload XSS accepté en données mais transporté en JSON (échappement = responsabilité front)", "minor",
           S(r) == 201 and "json" in ctype.lower(),
           "201 + Content-Type application/json (pas de rendu HTML serveur)",
           f"status={S(r)} stored_title={stored_title!r} ctype={ctype}", endpoint="POST /api/products/",
           note="L'API ne fait pas de sanitisation HTML; le rendu sécurisé incombe au frontend Flutter (Text widget = sûr).")

    # T10.7 Path traversal pattern blocked by SuspiciousRequestMiddleware
    r = anon.req("GET", "/api/../../etc/passwd", auth=False, note="path traversal")
    record("T10.7", "Tentative de path traversal non servie", "major", S(r) in (400, 403, 404),
           "400/403/404", f"status={S(r)}", endpoint="GET /api/../../etc/passwd", be_file="config/middleware.py:SuspiciousRequestMiddleware")

    # T10.8 Security headers present
    r = anon.req("GET", "/api/health/", auth=False, note="headers")
    h = {k.lower(): v for k, v in (r.headers.items() if r is not None else [])}
    want = ["x-content-type-options", "x-frame-options"]
    present = [k for k in want if k in h]
    record("T10.8", "En-têtes de sécurité présents (X-Content-Type-Options, X-Frame-Options)", "major",
           len(present) == len(want), "tous présents", f"présents={present} manquants={[k for k in want if k not in h]}",
           endpoint="GET /api/health/", be_file="config/middleware.py:SecurityHeadersMiddleware")

    # T10.9 Scanner User-Agent flagged/handled (no 500)
    r = anon.req("GET", "/api/products/", auth=False, extra_headers={"User-Agent": "sqlmap/1.5"}, note="scanner UA")
    record("T10.9", "Requête avec User-Agent de scanner gérée sans erreur serveur", "minor", S(r) in (200, 400, 403, 429),
           "200/400/403/429 (pas de 500)", f"status={S(r)}", endpoint="GET /api/products/ (UA=sqlmap)")

    # T10.10 Mass assignment: try to set is_superuser/is_staff/role via profile update
    from qa import set_sensitive_otp
    buy.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "profile.update"}, note="req otp mass")
    tk, cd = set_sensitive_otp(BUY, "profile.update")
    r = buy.req("POST", "/api/auth/profile/", json_body={
        "is_superuser": True, "is_staff": True, "role": "GENERAL_ADMIN", "kyc_level": 3,
        "challenge_token": tk, "verification_code": cd}, note="mass assignment")
    if qa.is_remote():
        escalated_str = qa.remote_eval(f"from apps.accounts.models import User; u = User.objects.get(email__iexact='{BUY}'); val = u.is_superuser or u.is_staff or u.role == 'GENERAL_ADMIN' or u.kyc_level == 3", "val")
        escalated = escalated_str == "True"
        u_info = qa.remote_eval(f"from apps.accounts.models import User; u = User.objects.get(email__iexact='{BUY}'); val = f'is_superuser={{u.is_superuser}} is_staff={{u.is_staff}} role={{u.role}} kyc={{u.kyc_level}}'", "val")
    else:
        u.refresh_from_db()
        escalated = u.is_superuser or u.is_staff or u.role == "GENERAL_ADMIN" or u.kyc_level == 3
        u_info = f"is_superuser={u.is_superuser} is_staff={u.is_staff} role={u.role} kyc={u.kyc_level}"
    record("T10.10", "Mass-assignment: champs privilégiés (is_superuser/role/kyc_level) non modifiables via profil", "critical",
           not escalated, "aucune élévation",
           f"after: {u_info} (resp={S(r)})",
           endpoint="POST /api/auth/profile/", be_file="apps/accounts/serializers.py:ProfileUpdateSerializer (champs restreints)")


if __name__ == "__main__":
    main()
