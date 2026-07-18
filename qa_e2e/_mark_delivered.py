# -*- coding: utf-8 -*-
import os
from apps.orders.models import Order, OrderStatus
from apps.logistics.models import ShipmentStatus

oid = int(os.environ.get("OID", "6"))
o = Order.objects.get(id=oid)
o.status = OrderStatus.DELIVERED
o.save(update_fields=["status", "updated_at"])
sh = getattr(o, "shipment", None)
if sh:
    sh.status = ShipmentStatus.DELIVERED
    sh.save(update_fields=["status", "updated_at"])
print(f"order {o.id} -> {o.status} | shipment -> {getattr(sh,'status',None)}")
