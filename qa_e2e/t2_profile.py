"""E2E batch 2 — Profile, password, phone/email change, Buyer KYC. Real HTTP."""
import os
from qa import Client, record, set_sensitive_otp, django_setup

MEDIA = os.path.join(os.path.dirname(__file__), "media")
PWD = "ChangeMe123!"
BUYER = "buyer@marche-cm.local"


def f(name):
    return os.path.join(MEDIA, name)


def main():
    c = Client("buyer")
    c.login(BUYER, PWD)

    # --- T2.1 Profile update WITHOUT challenge -> 403 (sensitive gate) ---
    r = c.req("POST", "/api/auth/profile/", json_body={"city": "Douala"}, note="profile no challenge")
    record("T2.1", "Update profil sans challenge 2FA refusé", "major",
           r is not None and r.status_code == 403,
           "403 (vérification requise)", f"status={r.status_code if r else 'NA'} body={r.text[:120] if r else ''}",
           endpoint="/api/auth/profile/", be_file="apps/accounts/views.py:ProfileUpdateView")

    # --- T2.2 Profile update WITH challenge -> 200 + DB check (name field) ---
    import time as _t
    new_name = f"QA Buyer {int(_t.time())}"
    c.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "profile.update"}, note="req profile otp")
    tok, code = set_sensitive_otp(BUYER, "profile.update")
    r = c.req("POST", "/api/auth/profile/", json_body={
        "name": new_name, "challenge_token": tok, "verification_code": code,
    }, note="profile with challenge")
    passed = r is not None and r.status_code == 200
    db_name = None
    if passed:
        django_setup()
        from apps.accounts.models import User
        db_name = User.objects.filter(email__iexact=BUYER).values_list("first_name", flat=True).first()
    record("T2.2", "Update profil (nom) avec challenge -> persisté en base", "major",
           passed and db_name == new_name,
           f"200 + first_name='{new_name}' en base", f"status={r.status_code if r else 'NA'} db_name={db_name}",
           endpoint="/api/auth/profile/")

    # --- T2.3 Email change requires a SEPARATE email challenge -> 403 if missing ---
    c.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "profile.update"}, note="req profile otp 2")
    tok2, code2 = set_sensitive_otp(BUYER, "profile.update")
    r = c.req("POST", "/api/auth/profile/", json_body={
        "email": "newmail-qa@qa.test", "challenge_token": tok2, "verification_code": code2,
    }, note="email change without email challenge")
    record("T2.3", "Changement d'email sans challenge dédié refusé", "major",
           r is not None and r.status_code == 403,
           "403 (confirmation email requise)", f"status={r.status_code if r else 'NA'} body={r.text[:120] if r else ''}",
           endpoint="/api/auth/profile/")

    # --- T2.4 Password change wrong current -> 400 ---
    r = c.req("POST", "/api/auth/password-change/", json_body={
        "current_password": "WRONGcurrent1!", "new_password": "BrandNew123!",
    }, note="pwd wrong current")
    record("T2.4", "Changement mdp avec mauvais mot de passe actuel refusé", "major",
           r is not None and r.status_code == 400,
           "400", f"status={r.status_code if r else 'NA'} body={r.text[:120] if r else ''}",
           endpoint="/api/auth/password-change/")

    # --- T2.5 Password change weak new -> 400 ---
    r = c.req("POST", "/api/auth/password-change/", json_body={
        "current_password": PWD, "new_password": "123",
    }, note="pwd weak new")
    record("T2.5", "Changement mdp avec nouveau mdp faible refusé", "minor",
           r is not None and r.status_code == 400,
           "400", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/password-change/")

    # --- T2.6 Password change same as old -> 400 ---
    r = c.req("POST", "/api/auth/password-change/", json_body={
        "current_password": PWD, "new_password": PWD,
    }, note="pwd same")
    record("T2.6", "Changement mdp identique à l'ancien refusé", "minor",
           r is not None and r.status_code == 400,
           "400", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/password-change/")

    # --- T2.7 Password change valid (challenge) then login with new, then revert ---
    NEW = "FreshPass456!"
    c.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "auth.password.change"}, note="req pwd otp")
    tok3, code3 = set_sensitive_otp(BUYER, "auth.password.change")
    r = c.req("POST", "/api/auth/password-change/", json_body={
        "current_password": PWD, "new_password": NEW,
        "challenge_token": tok3, "verification_code": code3,
    }, note="pwd change valid")
    changed = r is not None and r.status_code == 200
    login_new = Client("buyer_new").login(BUYER, NEW) if changed else None
    new_works = login_new is not None and login_new.status_code == 200
    # revert to original
    if new_works:
        cc = Client("buyer_new2"); cc.login(BUYER, NEW)
        cc.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "auth.password.change"}, note="req pwd otp revert")
        tok4, code4 = set_sensitive_otp(BUYER, "auth.password.change")
        cc.req("POST", "/api/auth/password-change/", json_body={
            "current_password": NEW, "new_password": PWD,
            "challenge_token": tok4, "verification_code": code4,
        }, note="pwd revert")
    record("T2.7", "Changement mdp valide (challenge) + login avec nouveau mdp", "critical",
           changed and new_works,
           "200 + login nouveau mdp OK", f"change={r.status_code if r else 'NA'} login_new={login_new.status_code if login_new else 'NA'}",
           endpoint="/api/auth/password-change/")

    # --- T2.8 KYC invalid doc_type -> 400 ---
    c2 = Client("buyer_kyc"); c2.login(BUYER, PWD)
    with open(f("product1.jpg"), "rb") as fp:
        r = c2.req("POST", "/api/auth/kyc/submit/", files={"file": ("cni.jpg", fp, "image/jpeg")},
                   data={"doc_type": "BANANA"}, note="kyc bad type")
    record("T2.8", "KYC: doc_type invalide rejeté", "minor",
           r is not None and r.status_code == 400,
           "400", f"status={r.status_code if r else 'NA'}",
           endpoint="/api/auth/kyc/submit/")

    # --- T2.9 KYC valid CNI (image + signature + consent) -> 201 + DB PENDING ---
    with open(f("product1.jpg"), "rb") as fp, open(f("product2.png"), "rb") as sig:
        r = c2.req("POST", "/api/auth/kyc/submit/",
                   files={"file": ("cni.jpg", fp, "image/jpeg"), "signature": ("sig.png", sig, "image/png")},
                   data={"doc_type": "CNI", "consent_accepted": "true"}, note="kyc CNI valid")
    kyc_ok = r is not None and r.status_code in (200, 201)
    db_status = None
    if kyc_ok:
        django_setup()
        from apps.accounts.models import ComplianceDocument as CD, User as U2
        u = U2.objects.filter(email__iexact=BUYER).first()
        doc = CD.objects.filter(user=u, doc_type="CNI").order_by("-id").first()
        db_status = doc.status if doc else None
    record("T2.9", "KYC CNI valide (image+signature+consent) accepté + PENDING en base", "critical",
           kyc_ok and db_status == "PENDING", "201 + document PENDING en base",
           f"status={r.status_code if r else 'NA'} db_status={db_status} body={r.text[:160] if r else ''}",
           endpoint="/api/auth/kyc/submit/", be_file="apps/accounts/views.py:BuyerKycSubmitView")

    # --- T2.10 KYC PROOF_ADDRESS (view allows, serializer ALLOWED_DOC_TYPES may not) ---
    with open(f("product1.jpg"), "rb") as fp:
        r = c2.req("POST", "/api/auth/kyc/submit/", files={"file": ("addr.jpg", fp, "image/jpeg")},
                   data={"doc_type": "PROOF_ADDRESS", "consent_accepted": "true"}, note="kyc PROOF_ADDRESS")
    record("T2.10", "KYC PROOF_ADDRESS accepté (annoncé par la vue acheteur)", "major",
           r is not None and r.status_code in (200, 201),
           "201 (la vue liste PROOF_ADDRESS comme valide)",
           f"status={r.status_code if r else 'NA'} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/kyc/submit/",
           be_file="views.py:BuyerKycSubmitView.IDENTITY_DOC_TYPES vs serializers.py:ComplianceDocumentSerializer.ALLOWED_DOC_TYPES")

    # --- T2.11 KYC SELFIE (same suspected mismatch) ---
    with open(f("product1.jpg"), "rb") as fp:
        r = c2.req("POST", "/api/auth/kyc/submit/", files={"file": ("selfie.jpg", fp, "image/jpeg")},
                   data={"doc_type": "SELFIE", "consent_accepted": "true"}, note="kyc SELFIE")
    record("T2.11", "KYC SELFIE accepté (annoncé par la vue acheteur)", "major",
           r is not None and r.status_code in (200, 201),
           "201 (la vue liste SELFIE comme valide)",
           f"status={r.status_code if r else 'NA'} body={r.text[:200] if r else ''}",
           endpoint="/api/auth/kyc/submit/")

    # --- T2.12 KYC polyglot/script file as image -> must reject (magic bytes) ---
    with open(f("evil.jpg"), "rb") as fp:
        r = c2.req("POST", "/api/auth/kyc/submit/", files={"file": ("evil.jpg", fp, "image/jpeg")},
                   data={"doc_type": "CNI"}, note="kyc polyglot")
    record("T2.12", "KYC: fichier script renommé .jpg rejeté (magic bytes)", "critical",
           r is not None and r.status_code == 400,
           "400 (contenu != extension)", f"status={r.status_code if r else 'NA'} body={r.text[:160] if r else ''}",
           endpoint="/api/auth/kyc/submit/", be_file="apps/accounts/upload_security.py")

    # --- T2.13 Display-name uniqueness on profile update (inconsistency vs register) ---
    # Register removed the first_name existence check (H-005), but ProfileUpdateSerializer
    # still rejects a display name already used by ANOTHER user. Try to set buyer's name
    # to the seeded supplier's display name.
    django_setup()
    from apps.accounts.models import User as U3
    other = U3.objects.filter(email__iexact="supplier@marche-cm.local").first()
    other_name = other.first_name if other else "Compte"
    c.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "profile.update"}, note="req profile otp 3")
    tokn, coden = set_sensitive_otp(BUYER, "profile.update")
    r = c.req("POST", "/api/auth/profile/", json_body={
        "name": other_name, "challenge_token": tokn, "verification_code": coden,
    }, note="dup display name")
    # This documents behaviour: a 400 here = display names forced globally unique
    # (UX defect + enumeration), inconsistent with registration which allows dups.
    is_rejected_for_dup = r is not None and r.status_code == 400
    record("T2.13", "Nom d'affichage NON imposé unique au profil (cohérence avec inscription)", "minor",
           not is_rejected_for_dup,
           "nom d'affichage dupliqué autorisé (comme à l'inscription)",
           f"status={r.status_code if r else 'NA'} body={r.text[:160] if r else ''} other_name='{other_name}'",
           endpoint="/api/auth/profile/",
           be_file="serializers.py:ProfileUpdateSerializer.validate_name vs RegisterSerializer.validate_name")


if __name__ == "__main__":
    main()
