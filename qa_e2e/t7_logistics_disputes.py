"""E2E batch 7 — Shipment lifecycle, cancellation+refund, disputes+evidence.
No live payout is triggered (escrow release-to-seller would call NotchPay
disburse — deliberately not exercised)."""
import os, time
from decimal import Decimal
from qa import Client, record, S, B, django_setup

PWD = "ChangeMe123!"
SUP = "supplier@marche-cm.local"; BUY = "buyer@marche-cm.local"
TRANSIT = "transit@marche-cm.local"; ADMIN = "admin@marche-cm.local"
TRANSIT_ID = int(os.environ.get("QA_TRANSIT_ID", "7"))
PRODUCT_ID = 9  # overridden in main() with a freshly created active product


def f(n):
    return os.path.join("media", n)


def make_order(buyer):
    r = buyer.req("POST", "/api/orders/", json_body={
        "product": PRODUCT_ID, "quantity": 1, "preferred_transit_agent": TRANSIT_ID,
        "transport_mode": "SEA"}, note="create order for logistics")
    return (r.json().get("id") if S(r) == 201 else None), r


def shipment_id_for(order_id):
    django_setup()
    from apps.logistics.models import Shipment
    s = Shipment.objects.filter(order_id=order_id).first()
    return s.id if s else None


def main():
    buy = Client("buyer"); buy.login(BUY, PWD)
    sup = Client("supplier"); sup.login(SUP, PWD)
    tr = Client("transit"); tr.login(TRANSIT, PWD)
    adm = Client("admin"); adm.login(ADMIN, PWD)
    other = Client("other");
    em = f"olog{int(time.time())}@qa.test"
    Client("anon").req("POST", "/api/auth/register/", json_body={"name": "Other L", "email": em,
        "phone_number": "+237690333444", "password": PWD}, auth=False, note="reg other log")
    other.login(em, PWD)

    django_setup()
    from apps.accounts.models import User
    from apps.wallets.models import Wallet
    from apps.wallets.services import WalletAccountingService
    from apps.orders.models import Order

    # ensure buyer funded for a fresh order
    u = User.objects.get(email__iexact=BUY); w, _ = Wallet.objects.get_or_create(owner=u)
    if w.available_balance < Decimal("20000"):
        WalletAccountingService.credit_available(wallet=w, amount=Decimal("50000"),
            reference="qa-seed-log", idempotency_key=f"qa-seed-log-{int(time.time())}", created_by=u)

    # Harness hardcoded PRODUCT_ID=9 doesn't match a fresh prod DB — create a
    # real active priced product (weight set for SEA shipping math) as supplier.
    global PRODUCT_ID
    with open(f("product1.jpg"), "rb") as fp:
        rp = sup.req("POST", "/api/products/", files={"image": ("log.jpg", fp, "image/jpeg")},
                     data={"title": f"Logistics QA {int(time.time())}", "description": "produit logistique QA",
                           "brand": "QA", "category_name": "QA", "weight_kg": "2",
                           "min_order_qty": "1", "max_order_qty": "10",
                           "price_for_min_qty": "5000", "price_for_max_qty": "4500", "is_active": "true"},
                     note="setup logistics product")
    if S(rp) == 201:
        PRODUCT_ID = rp.json().get("id")
    print("LOGISTICS PRODUCT_ID:", PRODUCT_ID)

    # order #2 for shipment progression + dispute
    oid2, r = make_order(buy)
    sid2 = shipment_id_for(oid2)
    print("ORDER2:", oid2, "SHIPMENT2:", sid2)

    # order #1 (from batch 6) for cancellation; fallback: make another
    o1 = Order.objects.filter(buyer=u, status="PENDING").exclude(id=oid2).order_by("id").first()
    oid1 = o1.id if o1 else None
    sid1 = shipment_id_for(oid1) if oid1 else None
    print("ORDER1(cancel target):", oid1, "SHIPMENT1:", sid1)

    # --- T7.1 Transit agent advances shipment PICKUP_PENDING -> IN_TRANSIT ---
    r = tr.req("POST", f"/api/shipments/{sid2}/update_status/", json_body={"status": "IN_TRANSIT", "note": "départ"}, note="transit in_transit")
    record("T7.1", "Transitaire fait avancer l'expédition (PICKUP_PENDING->IN_TRANSIT)", "critical",
           S(r) == 200, "200", f"status={S(r)} body={B(r,120)}",
           endpoint="POST /api/shipments/{id}/update_status/", be_file="apps/logistics/views.py:update_status")

    # --- T7.2 Buyer cannot set transit-only status ---
    if sid1:
        r = buy.req("POST", f"/api/shipments/{sid1}/update_status/", json_body={"status": "IN_TRANSIT"}, note="buyer transit status")
        record("T7.2", "Acheteur ne peut pas appliquer un statut réservé au transitaire", "major",
               S(r) == 403, "403", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/shipments/{id}/update_status/")

    # --- T7.3 Invalid transition (PICKUP_PENDING -> OUT_FOR_DELIVERY) ---
    if sid1:
        r = tr.req("POST", f"/api/shipments/{sid1}/update_status/", json_body={"status": "OUT_FOR_DELIVERY"}, note="invalid transition")
        record("T7.3", "Transition d'expédition invalide rejetée", "major",
               S(r) == 400, "400", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/shipments/{id}/update_status/")

    # --- T7.4 Non-participant cannot touch shipment ---
    r = other.req("POST", f"/api/shipments/{sid2}/update_status/", json_body={"status": "IN_TRANSIT"}, note="nonparticipant shipment")
    record("T7.4", "Non-participant ne peut pas modifier une expédition (cloisonnement)", "critical",
           S(r) in (403, 404), "403/404", f"status={S(r)}", endpoint="POST /api/shipments/{id}/update_status/")

    # --- T7.5 validate_delivery without proof -> 400 ---
    r = buy.req("POST", f"/api/shipments/{sid2}/validate_delivery/", json_body={}, note="validate no proof")
    record("T7.5", "Validation livraison sans preuve refusée", "major",
           S(r) == 400, "400 (aucune preuve)", f"status={S(r)} body={B(r,120)}",
           endpoint="POST /api/shipments/{id}/validate_delivery/", be_file="apps/logistics/views.py:validate_delivery")

    # --- T7.6 Cancellation + escrow refund (buyer cancels order#1 shipment) ---
    if sid1:
        w.refresh_from_db(); avail_before = w.available_balance; locked_before = w.locked_balance
        r = buy.req("POST", f"/api/shipments/{sid1}/update_status/", json_body={"status": "CANCELLED", "note": "annulation acheteur"}, note="cancel+refund")
        w.refresh_from_db(); avail_after = w.available_balance
        o1b = Order.objects.get(id=oid1)
        refunded = Decimal(avail_after) - Decimal(avail_before)
        record("T7.6", "Annulation expédition -> commande CANCELLED + escrow remboursé à l'acheteur", "critical",
               S(r) == 200 and o1b.status == "CANCELLED" and refunded == Decimal("8600.00"),
               "200 + order CANCELLED + +8600 recrédité (available)",
               f"status={S(r)} order_status={o1b.status} avail_before={avail_before} avail_after={avail_after} refunded={refunded}",
               endpoint="POST /api/shipments/{id}/update_status/ (CANCELLED)", be_file="apps/logistics/views.py:update_status + refund_order_locked_funds")

    # --- T7.7 Open dispute on order#2 shipment (buyer) ---
    r = buy.req("POST", f"/api/shipments/{sid2}/open_dispute/", json_body={"dispute_type": "QUALITY_DEFECT", "description": "Produit défectueux QA"}, note="open dispute")
    disp_ok = S(r) in (200, 201)
    # find dispute id
    django_setup()
    from apps.logistics.models import ShipmentDispute
    disp = ShipmentDispute.objects.filter(shipment_id=sid2).order_by("-id").first()
    did = disp.id if disp else None
    record("T7.7", "Ouverture d'un litige sur l'expédition (acheteur)", "critical",
           disp_ok and did is not None, "200/201 + litige créé",
           f"status={S(r)} dispute_id={did} body={B(r,120)}",
           endpoint="POST /api/shipments/{id}/open_dispute/", be_file="apps/logistics/views.py:open_dispute")

    # --- T7.8 Add image evidence ---
    if did:
        with open(f("product1.jpg"), "rb") as fp:
            r = buy.req("POST", f"/api/shipment-disputes/{did}/add-evidence/",
                        files={"file": ("evi.jpg", fp, "image/jpeg")},
                        data={"evidence_type": "PHOTO", "description": "photo défaut"}, note="evidence image")
        record("T7.8", "Ajout de preuve image au litige", "major", S(r) in (200, 201),
               "201", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/shipment-disputes/{id}/add-evidence/")

        # --- T7.9 Add video evidence ---
        with open(f("clip.mp4"), "rb") as fp:
            r = buy.req("POST", f"/api/shipment-disputes/{did}/add-evidence/",
                        files={"file": ("evi.mp4", fp, "video/mp4")},
                        data={"evidence_type": "VIDEO", "description": "vidéo défaut"}, note="evidence video")
        record("T7.9", "Ajout de preuve vidéo au litige", "major", S(r) in (200, 201),
               "201", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/shipment-disputes/{id}/add-evidence/")

        # --- T7.10 Non-participant cannot add evidence ---
        with open(f("product1.jpg"), "rb") as fp:
            r = other.req("POST", f"/api/shipment-disputes/{did}/add-evidence/",
                          files={"file": ("x.jpg", fp, "image/jpeg")}, data={"evidence_type": "PHOTO"}, note="evidence nonparticipant")
        record("T7.10", "Non-participant ne peut pas ajouter de preuve au litige", "critical",
               S(r) in (403, 404), "403/404", f"status={S(r)}", endpoint="POST /api/shipment-disputes/{id}/add-evidence/")

        # --- T7.11 Admin can view the dispute ---
        r = adm.req("GET", f"/api/shipment-disputes/{did}/", note="admin view dispute")
        record("T7.11", "Admin peut consulter le litige", "minor", S(r) == 200,
               "200", f"status={S(r)}", endpoint="GET /api/shipment-disputes/{id}/")

    return {"order2": oid2, "shipment2": sid2, "dispute": did}


if __name__ == "__main__":
    print("RESULT:", main())
