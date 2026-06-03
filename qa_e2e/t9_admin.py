"""E2E batch 9 — Administration: dashboard, KYC review, dispute resolution, perms."""
from decimal import Decimal
from qa import Client, record, S, B, django_setup

PWD = "ChangeMe123!"
ADMIN = "admin@marche-cm.local"; BUY = "buyer@marche-cm.local"


def main():
    adm = Client("admin"); adm.login(ADMIN, PWD)
    buy = Client("buyer"); buy.login(BUY, PWD)

    # T9.1 admin dashboard
    r = adm.req("GET", "/api/admin/dashboard/", note="admin dashboard")
    record("T9.1", "Dashboard admin accessible (stats)", "critical", S(r) == 200,
           "200 + stats", f"status={S(r)} body={B(r,160)}", endpoint="GET /api/admin/dashboard/")

    # T9.2 non-admin dashboard -> 403
    r = buy.req("GET", "/api/admin/dashboard/", note="buyer dashboard")
    record("T9.2", "Dashboard admin refusé aux non-admins", "critical", S(r) == 403,
           "403", f"status={S(r)}", endpoint="GET /api/admin/dashboard/")

    # T9.3 admin audit CSV export
    r = adm.req("GET", "/api/admin/audit/export/", note="admin audit export")
    is_csv = r is not None and "csv" in (r.headers.get("Content-Type", "") if r is not None else "")
    record("T9.3", "Export CSV des logs d'audit (admin)", "major", S(r) == 200 and is_csv,
           "200 text/csv", f"status={S(r)} ctype={r.headers.get('Content-Type') if r is not None else 'NA'}",
           endpoint="GET /api/admin/audit/export/")

    # T9.4 non-admin audit export -> 403
    r = buy.req("GET", "/api/admin/audit/export/", note="buyer audit export")
    record("T9.4", "Export audit refusé aux non-admins", "critical", S(r) == 403,
           "403", f"status={S(r)}", endpoint="GET /api/admin/audit/export/")

    # T9.5 admin reviews/approves a pending seller/buyer KYC document
    django_setup()
    from apps.accounts.models import ComplianceDocument
    doc = ComplianceDocument.objects.filter(status="PENDING").order_by("id").first()
    did = doc.id if doc else None
    if did:
        r = adm.req("POST", f"/api/compliance-documents/{did}/review/", json_body={"status": "APPROVED"}, note="admin approve kyc")
        doc.refresh_from_db()
        record("T9.5", "Validation KYC (admin approuve un document) -> APPROVED en base", "critical",
               S(r) == 200 and doc.status == "APPROVED", "200 + status APPROVED",
               f"status={S(r)} db_status={doc.status} doc_id={did}", endpoint="POST /api/compliance-documents/{id}/review/",
               be_file="apps/accounts/views.py:ComplianceDocumentViewSet.review")

        # T9.6 non-admin review -> 403
        r = buy.req("POST", f"/api/compliance-documents/{did}/review/", json_body={"status": "REJECTED"}, note="buyer review")
        record("T9.6", "Revue KYC refusée aux non-admins", "critical", S(r) in (403, 404),
               "403/404", f"status={S(r)}", endpoint="POST /api/compliance-documents/{id}/review/")

    # T9.7 admin lists all users
    r = adm.req("GET", "/api/users/", note="admin users")
    record("T9.7", "Admin liste tous les utilisateurs", "major", S(r) == 200,
           "200", f"status={S(r)}", endpoint="GET /api/users/")

    # T9.8 /api/users/online/ exists
    r = adm.req("GET", "/api/users/online/", note="users online")
    record("T9.8", "Endpoint /api/users/online/ (utilisé par l'app admin) fonctionne", "minor",
           S(r) in (200,), "200", f"status={S(r)} body={B(r,80)}", endpoint="GET /api/users/online/",
           fe_file="frontend/admin/project/lib/features/data/admin_repository.dart:19")

    # T9.9 admin escrow holds + audit events
    r1 = adm.req("GET", "/api/escrow/holds/", note="escrow holds")
    r2 = adm.req("GET", "/api/audit/events/", note="audit events")
    record("T9.9", "Admin consulte escrow holds + audit events", "minor",
           S(r1) == 200 and S(r2) == 200, "200/200", f"holds={S(r1)} audit={S(r2)}",
           endpoint="GET /api/escrow/holds/ , /api/audit/events/")

    # T9.10 admin resolves dispute #1 with REFUND_BUYER (internal refund, safe)
    from apps.logistics.models import ShipmentDispute
    from apps.accounts.models import User
    from apps.wallets.models import Wallet
    disp = ShipmentDispute.objects.order_by("id").first()
    dispute_id = disp.id if disp else None
    if dispute_id:
        u = User.objects.get(email__iexact=BUY); w, _ = Wallet.objects.get_or_create(owner=u)
        w.refresh_from_db(); avail_before = w.available_balance
        r = adm.req("POST", f"/api/shipment-disputes/{dispute_id}/decide/", json_body={
            "status": "RESOLVED", "admin_decision": "REFUND_BUYER", "resolution_note": "Remboursement acheteur (QA)"}, note="admin decide refund")
        disp.refresh_from_db(); w.refresh_from_db(); avail_after = w.available_balance
        refunded = Decimal(avail_after) - Decimal(avail_before)
        record("T9.10", "Résolution litige (admin REFUND_BUYER) -> RESOLVED + acheteur remboursé", "critical",
               S(r) == 200 and disp.status == "RESOLVED" and refunded > 0,
               "200 + dispute RESOLVED + solde acheteur recrédité",
               f"status={S(r)} dispute_status={disp.status} refunded={refunded} body={B(r,120)}",
               endpoint="POST /api/shipment-disputes/{id}/decide/", be_file="apps/logistics/views.py:decide")

        # T9.11 non-admin decide -> 403
        r = buy.req("POST", f"/api/shipment-disputes/{dispute_id}/decide/", json_body={
            "status": "RESOLVED", "admin_decision": "REFUND_BUYER", "resolution_note": "x"}, note="buyer decide")
        record("T9.11", "Décision de litige refusée aux non-admins", "critical", S(r) in (403, 404),
               "403/404", f"status={S(r)}", endpoint="POST /api/shipment-disputes/{id}/decide/")

    # T9.12 Feature gap: no user-block endpoint wired anywhere (mission expects 'blocage utilisateur')
    record("T9.12", "Fonction 'blocage utilisateur' disponible côté admin", "major",
           False,
           "endpoint de blocage/suspension utilisateur exposé + câblé dans l'app admin",
           "Aucun endpoint block/suspend dans accounts/views.py (UserViewSet est ReadOnly) et l'app admin (admin_repository.dart) ne référence aucune action de blocage. Fonction attendue par la mission non implémentée.",
           endpoint="(absent)", fe_file="frontend/admin/project/lib/features/data/admin_repository.dart",
           be_file="apps/accounts/views.py:UserViewSet (ReadOnlyModelViewSet)")


if __name__ == "__main__":
    main()
