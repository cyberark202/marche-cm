# -*- coding: utf-8 -*-
import os
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.orders.models import Order
from apps.orders.services import OrderFinanceService
from apps.wallets.services import WalletAccountingService

U = get_user_model()
oid = int(os.environ.get("OID", "5"))
admin = U.objects.filter(email__iexact="admin@marche-cm.local").first()
driver = U.objects.filter(email__iexact="driver.e2e@marche-cm.local").first()


def snap(tag):
    o = Order.objects.get(id=oid)
    line = f"[{tag}] order status={o.status} escrow_status={o.escrow_status}"
    for e in o.escrows.all():
        line += f" | {e.escrow_type}={e.status}({e.released_amount}/{e.amount})"
    print(line)
    for uid, lbl in [(o.buyer_id, "buyer"), (o.seller_id, "seller"), (driver.id, "driver")]:
        w = WalletAccountingService.get_wallet_for_update(user=U.objects.get(id=uid))
        print(f"     wallet {lbl}#{uid}: avail={w.available_balance} locked={w.locked_balance} pending={w.pending_balance}")


o = Order.objects.get(id=oid)
snap("START")

OrderFinanceService.register_supplier_confirmation(order=o, actor=driver)
snap("APRES confirm fournisseur (livreur)")

img = Path(r"E:/project/Marche CM/qa_e2e/media/product2.png").read_bytes()
proof = SimpleUploadedFile("preuve_achat.png", img, content_type="image/png")
OrderFinanceService.register_supplier_purchase_proof(order=o, actor=driver, proof_file=proof)
snap("APRES upload preuve (livreur)")

OrderFinanceService.admin_validate_supplier(order=o, actor=admin, approve=True, note="QA E2E validation")
snap("APRES validation admin (-> libere escrow fournisseur, payout simule)")

print("DONE STEPS 3-4")
