"""E2E batch 6 — Orders + escrow. Real HTTP.
Buyer wallet is seeded with an INTERNAL ledger credit (local test DB only — no
real money, no payment provider) so the escrow happy-path can be exercised."""
from decimal import Decimal
import time
from qa import Client, record, S, B, django_setup

PWD = "ChangeMe123!"
SUP = "supplier@marche-cm.local"
BUY = "buyer@marche-cm.local"
import os as _os
TRANSIT_ID = int(_os.environ.get("QA_TRANSIT_ID", "7"))  # transit@marche-cm.local user id (active TransportProfile air=3500, sea=1800)


def f(n):
    import os
    return os.path.join("media", n)


def main():
    sup = Client("supplier"); sup.login(SUP, PWD)
    buy = Client("buyer"); buy.login(BUY, PWD)

    # --- Setup: active priced product (multipart + is_active=true to dodge the is_active bug) ---
    with open(f("product1.jpg"), "rb") as fp:
        r = sup.req("POST", "/api/products/", files={"image": ("ord.jpg", fp, "image/jpeg")},
                    data={"title": f"Riz commande QA {int(time.time())}", "description": "Produit commande QA",
                          "brand": "QA", "category_name": "QA Catégorie", "weight_kg": "2",
                          "min_order_qty": "1", "max_order_qty": "10",
                          "price_for_min_qty": "5000", "price_for_max_qty": "4500", "is_active": "true"},
                    note="setup product")
    pid = r.json().get("id") if S(r) == 201 else None
    print("PRODUCT ID:", pid)

    def order_body(**over):
        b = {"product": pid, "quantity": 1, "preferred_transit_agent": TRANSIT_ID, "transport_mode": "SEA"}
        b.update(over); return b

    # --- T6.1 Non-buyer (supplier) cannot order ---
    r = sup.req("POST", "/api/orders/", json_body=order_body(), note="supplier orders")
    record("T6.1", "Seul un acheteur peut passer commande (vendeur refusé)", "critical",
           S(r) in (400, 403), "400/403", f"status={S(r)} body={B(r,140)}",
           endpoint="POST /api/orders/", be_file="apps/orders/serializers.py:OrderSerializer.create")

    # --- T6.2 Missing transit agent ---
    r = buy.req("POST", "/api/orders/", json_body={"product": pid, "quantity": 1, "transport_mode": "SEA"}, note="no transit")
    record("T6.2", "Commande sans transitaire rejetée", "major", S(r) == 400,
           "400", f"status={S(r)} body={B(r,140)}", endpoint="POST /api/orders/")

    # --- T6.3 Quantity out of range ---
    r = buy.req("POST", "/api/orders/", json_body=order_body(quantity=999), note="qty out of range")
    record("T6.3", "Commande quantité hors plage min/max rejetée", "major", S(r) == 400,
           "400", f"status={S(r)} body={B(r,140)}", endpoint="POST /api/orders/")

    # --- T6.4 Insufficient funds (buyer balance 0) ---
    django_setup()
    from apps.accounts.models import User
    from apps.wallets.models import Wallet
    from apps.wallets.services import WalletAccountingService
    u = User.objects.get(email__iexact=BUY); w, _ = Wallet.objects.get_or_create(owner=u)
    print("BUYER BALANCE (pre-fund):", w.available_balance)
    r = buy.req("POST", "/api/orders/", json_body=order_body(), note="insufficient funds")
    record("T6.4", "Commande à solde insuffisant rejetée (escrow non finançable)", "critical",
           S(r) == 400, "400 (fonds insuffisants)", f"status={S(r)} body={B(r,140)}",
           endpoint="POST /api/orders/", be_file="apps/orders/serializers.py:OrderFinanceService.lock_funds_for_order")

    # --- Seed buyer wallet (internal ledger credit, local test only) ---
    WalletAccountingService.credit_available(
        wallet=w, amount=Decimal("50000"), reference="qa-e2e-seed",
        idempotency_key=f"qa-seed-{int(time.time())}", created_by=u)
    w.refresh_from_db()
    bal_before = w.available_balance
    print("BUYER BALANCE (post-fund):", bal_before)

    # --- T6.5 Price integrity: client cannot override unit_price/total_price ---
    r = buy.req("POST", "/api/orders/", json_body=order_body(quantity=1, unit_price=1, total_price=1), note="order success + price override")
    ok = S(r) == 201
    j = r.json() if ok else {}
    oid = j.get("id")
    server_total = j.get("total_price")
    escrow_status = j.get("escrow_status")
    # expected: qty1 @ price_for_min_qty 5000 => total 5000 ; shipping = 2kg*1*1800 = 3600 ; LOCAL lock = 8600
    w.refresh_from_db(); bal_after = w.available_balance
    debited = (Decimal(bal_before) - Decimal(bal_after))
    record("T6.5", "Commande créée: prix calculés serveur (override client ignoré) + escrow HELD + wallet débité", "critical",
           ok and str(server_total) in ("5000.00", "5000") and escrow_status == "HELD" and debited == Decimal("8600.00"),
           "total=5000 (pas 1), escrow=HELD, débit=8600 (5000+3600 transport SEA local)",
           f"status={S(r)} total={server_total} escrow={escrow_status} debit={debited} body={B(r,140)}",
           endpoint="POST /api/orders/", be_file="apps/orders/serializers.py (unit_price/total_price read_only)")

    # --- T6.6 IDOR: another buyer cannot read this order ---
    other = Client("buyer2")
    # register a throwaway buyer
    em = f"obuyer{int(time.time())}@qa.test"
    Client("anon").req("POST", "/api/auth/register/", json_body={"name": "Other Buyer", "email": em,
        "phone_number": "+237690111222", "password": PWD}, auth=False, note="reg other buyer")
    other.login(em, PWD)
    if oid:
        r = other.req("GET", f"/api/orders/{oid}/", note="IDOR order read")
        record("T6.6", "IDOR commande: un autre acheteur ne voit pas la commande", "critical",
               S(r) == 404, "404 (queryset filtré buyer)", f"status={S(r)}",
               endpoint="GET /api/orders/{id}/", be_file="apps/orders/views.py:get_queryset")

    # --- T6.7 confirm_delivery by buyer -> COMPLETED + seller credited ---
    if oid:
        seller = User.objects.get(email__iexact=SUP); sw, _ = Wallet.objects.get_or_create(owner=seller)
        sw.refresh_from_db(); seller_before = sw.available_balance
        r = buy.req("POST", f"/api/orders/{oid}/confirm_delivery/", json_body={}, note="confirm delivery")
        # re-read order
        from apps.orders.models import Order
        o = Order.objects.get(id=oid)
        sw.refresh_from_db(); seller_after = sw.available_balance
        record("T6.7", "Confirmation livraison -> commande COMPLETED + escrow libéré au vendeur", "critical",
               S(r) in (200,) and o.status in ("COMPLETED",) and Decimal(seller_after) > Decimal(seller_before),
               "200 + status COMPLETED + solde vendeur crédité",
               f"status={S(r)} order_status={o.status} seller_before={seller_before} seller_after={seller_after} body={B(r,120)}",
               endpoint="POST /api/orders/{id}/confirm_delivery/", be_file="apps/orders/views.py:confirm_delivery")

    # --- T6.8 No buyer cancellation endpoint (DELETE disabled) ---
    if oid:
        r = buy.req("DELETE", f"/api/orders/{oid}/", note="cancel via delete")
        record("T6.8", "Annulation: pas d'endpoint d'annulation acheteur (DELETE désactivé)", "minor",
               S(r) == 405, "405 (http_method_names sans delete; remboursement via litige uniquement)",
               f"status={S(r)}", endpoint="DELETE /api/orders/{id}/",
               be_file="apps/orders/views.py:62 http_method_names=['get','post','head','options']")

    return {"product": pid, "order": oid}


if __name__ == "__main__":
    print("RESULT:", main())
