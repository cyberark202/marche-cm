# -*- coding: utf-8 -*-
from decimal import Decimal
from django.contrib.auth import get_user_model
from apps.catalog.models import Product

U = get_user_model()
seller = U.objects.filter(email__iexact="supplier@marche-cm.local").first()
actives = Product.objects.filter(seller=seller, is_active=True).order_by("id")
print(f"active products of seller {seller.id}: {actives.count()}")
for pr in actives[:12]:
    print(f"  id={pr.id} title={pr.title!r} weight={pr.weight_kg} min={pr.min_order_qty} max={pr.max_order_qty} pmin={pr.price_for_min_qty}")

target = actives.first()
if target:
    if target.weight_kg is None or Decimal(target.weight_kg) <= 0:
        target.weight_kg = Decimal("2.0")
        target.save(update_fields=["weight_kg"])
    print(f"TARGET -> id={target.id} title={target.title!r} weight={target.weight_kg} active={target.is_active}")
else:
    print("NO ACTIVE PRODUCT for seller — need to activate one")
