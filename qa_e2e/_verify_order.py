# -*- coding: utf-8 -*-
import os
from apps.orders.models import Order, OrderEscrow
from apps.wallets.services import WalletAccountingService

oid = int(os.environ.get("OID", "5"))
o = Order.objects.get(id=oid)
print(f"Order {o.id}: type={o.order_type} status={o.status} escrow_status={o.escrow_status} total={o.total_price} logistics={o.logistics_price}")
print(f"  buyer={o.buyer_id} seller={o.seller_id} preferred_transit={o.preferred_transit_agent_id}")
sh = getattr(o, "shipment", None)
print(f"  shipment: transit_agent={getattr(sh,'transit_agent_id',None)} mode={getattr(sh,'transport_mode',None)} fee={getattr(sh,'shipping_fee',None)}")
for e in o.escrows.all():
    print(f"  ESCROW {e.escrow_type}: amount={e.amount} status={e.status} beneficiary={e.beneficiary_id} "
          f"req_transit={e.requires_transit_confirmation} req_proof={e.requires_purchase_proof} req_admin={e.requires_admin_validation} req_buyer={e.requires_buyer_confirmation}")
from django.contrib.auth import get_user_model
U = get_user_model()
for uid, label in [(o.buyer_id, "buyer"), (o.seller_id, "seller"), (o.preferred_transit_agent_id, "driver")]:
    u = U.objects.get(id=uid)
    w = WalletAccountingService.get_wallet_for_update(user=u)
    print(f"  WALLET {label} #{uid}: available={w.available_balance} locked={w.locked_balance} pending={w.pending_balance}")
