# -*- coding: utf-8 -*-
# Simule la livraison effectuee par le livreur (action UI Driver bloquee : app
# principale derriere flag onboarding local non persistant). Met l'order + le
# shipment en DELIVERED pour que l'acheteur puisse "Valider reception" en UI.
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
