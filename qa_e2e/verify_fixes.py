"""Live re-verification (before/after) of the previously-failing E2E scenarios,
against the running server with the fixes applied."""
import os, time
from decimal import Decimal
from qa import Client, S, B, django_setup

PWD = "ChangeMe123!"
RUN = str(int(time.time()))


def f(n):
    return os.path.join("media", n)


def main():
    results = []

    def check(tag, cond, detail):
        results.append((tag, cond, detail))
        print(f"  [{'PASS' if cond else 'FAIL'}] {tag} :: {detail}")

    anon = Client("anon")

    # Register fresh actors
    sup_email = f"vsup{RUN}@qa.test"
    anon.req("POST", "/api/auth/register/seller/", json_body={
        "name": "V Supplier", "email": sup_email, "phone_number": "+237691100001",
        "password": PWD, "role": "SUPPLIER"}, auth=False, note="reg supplier")
    sup = Client("sup"); sup.login(sup_email, PWD)

    wh_email = f"vwh{RUN}@qa.test"
    anon.req("POST", "/api/auth/register/seller/", json_body={
        "name": "V Wholesaler", "email": wh_email, "phone_number": "+237691100002",
        "password": PWD, "role": "WHOLESALER"}, auth=False, note="reg wholesaler")
    wh = Client("wh"); wh.login(wh_email, PWD)

    buy_email = f"vbuy{RUN}@qa.test"
    anon.req("POST", "/api/auth/register/", json_body={
        "name": "V Buyer", "email": buy_email, "phone_number": "+237691100003",
        "password": PWD}, auth=False, note="reg buyer")
    buy = Client("buy"); buy.login(buy_email, PWD)

    # --- C-1: exact legacy Flutter supplier payload (category/min_qty/max_qty) ---
    r = sup.req("POST", "/api/products/", json_body={
        "title": f"Riz {RUN}", "brand": "QA", "category": "QA Catégorie",
        "description": "desc flutter", "min_qty": 10, "max_qty": 100,
        "price_for_max_qty": 4500, "price_for_min_qty": 5000, "available_qty": 0,
    }, note="C-1 legacy payload")
    check("C-1 legacy supplier payload -> 201", S(r) == 201, f"status={S(r)} (was 400) body={B(r,100)}")

    # --- C-2: multipart create without is_active -> active + visible ---
    with open(f("product1.jpg"), "rb") as fp:
        r = sup.req("POST", "/api/products/", files={"image": ("p.jpg", fp, "image/jpeg")},
                    data={"title": f"Photo {RUN}", "description": "d", "brand": "QA",
                          "category_name": "QA Catégorie", "weight_kg": "2",
                          "min_order_qty": "10", "max_order_qty": "100",
                          "price_for_min_qty": "5000", "price_for_max_qty": "4500"},
                    note="C-2 multipart no is_active")
    pid = r.json().get("id") if S(r) == 201 else None
    active = r.json().get("is_active") if S(r) == 201 else None
    in_public = False
    if pid:
        rl = Client("a2").req("GET", f"/api/products/{pid}/", auth=False, note="C-2 public retrieve")
        in_public = S(rl) == 200
    check("C-2 multipart product is_active=True + visible", active is True and in_public,
          f"is_active={active} (was False) public_visible={in_public}")

    # --- M-4: wholesaler create with only available_qty + unit_price ---
    r = wh.req("POST", "/api/products/", json_body={
        "title": f"Carton {RUN}", "description": "lot", "brand": "QA",
        "category_name": "QA Catégorie", "weight_kg": "5",
        "available_qty": 50, "unit_price": 3000}, note="M-4 wholesaler create")
    check("M-4 wholesaler create -> 201", S(r) == 201, f"status={S(r)} (was 400) body={B(r,120)}")

    # --- M-2/M-3: KYC PROOF_ADDRESS + SELFIE accepted ---
    ok_types = True
    for dt in ("PROOF_ADDRESS", "SELFIE"):
        with open(f("product1.jpg"), "rb") as fp:
            r = buy.req("POST", "/api/auth/kyc/submit/", files={"file": (f"{dt}.jpg", fp, "image/jpeg")},
                        data={"doc_type": dt, "consent_accepted": "true"}, note=f"M-2/3 {dt}")
        ok_types = ok_types and S(r) in (200, 201)
    check("M-2/M-3 KYC PROOF_ADDRESS+SELFIE -> 201", ok_types, f"(were 400) last status={S(r)}")

    # --- C-3: buyer cancellation refunds escrow (was: CANCELLED + funds stuck) ---
    django_setup()
    from apps.accounts.models import User
    from apps.wallets.models import Wallet
    from apps.wallets.services import WalletAccountingService
    from apps.logistics.models import Shipment
    from apps.orders.models import Order
    # active priced product from C-1? Use a fresh active one with proper qty/price.
    with open(f("product1.jpg"), "rb") as fp:
        rp = sup.req("POST", "/api/products/", files={"image": ("o.jpg", fp, "image/jpeg")},
                     data={"title": f"OrderProd {RUN}", "description": "d", "brand": "QA",
                           "category_name": "QA Catégorie", "weight_kg": "2",
                           "min_order_qty": "1", "max_order_qty": "10",
                           "price_for_min_qty": "5000", "price_for_max_qty": "4500"}, note="C-3 setup product")
    order_pid = rp.json().get("id") if S(rp) == 201 else None
    u = User.objects.get(email__iexact=buy_email); w, _ = Wallet.objects.get_or_create(owner=u)
    WalletAccountingService.credit_available(wallet=w, amount=Decimal("50000"),
        reference="verify-seed", idempotency_key=f"verify-seed-{RUN}", created_by=u)
    # transit agent id 10 (seeded) has active profile
    r = buy.req("POST", "/api/orders/", json_body={
        "product": order_pid, "quantity": 1, "preferred_transit_agent": 10, "transport_mode": "SEA"},
        note="C-3 create order")
    oid = r.json().get("id") if S(r) == 201 else None
    sid = Shipment.objects.filter(order_id=oid).values_list("id", flat=True).first() if oid else None
    w.refresh_from_db(); avail_before = w.available_balance
    rc = buy.req("POST", f"/api/shipments/{sid}/update_status/", json_body={
        "status": "CANCELLED", "note": "annulation acheteur"}, note="C-3 buyer cancel") if sid else None
    w.refresh_from_db(); avail_after = w.available_balance
    o = Order.objects.get(id=oid) if oid else None
    refunded = Decimal(avail_after) - Decimal(avail_before)
    cond = rc is not None and S(rc) == 200 and o.status == "CANCELLED" and refunded == Decimal("8600.00")
    check("C-3 buyer cancel -> CANCELLED + escrow refunded", cond,
          f"status={S(rc) if rc else 'NA'} (was 400) order={o.status if o else None} refunded={refunded} (was 0)")

    print("\n=== SUMMARY ===")
    passed = sum(1 for _, c, _ in results if c)
    print(f"{passed}/{len(results)} live re-verifications PASS")
    return all(c for _, c, _ in results)


if __name__ == "__main__":
    ok = main()
    print("ALL GREEN" if ok else "SOME FAILED")
