# -*- coding: utf-8 -*-  (ligne 1 BOM-safe ; lancer via shell -c exec utf-8-sig)
# Prepare les pre-requis du scenario INTERNATIONAL via l'UI :
#  - vendeur (supplier_demo) pays = CN  => commande CM->CN derivee INTERNATIONAL
#  - un produit du vendeur avec weight_kg > 0
#  - livreur onboarde (id 33) : trust_score >= 1, kyc_level 1, TransportProfile actif prix > 0
#  - rend le livreur 33 exclusif dans /api/transport-profiles/ (desactive les autres)
from decimal import Decimal
from django.contrib.auth import get_user_model
from apps.logistics.models import TransportProfile
from apps.catalog.models import Product

U = get_user_model()
DRIVER_ID = 33

seller = U.objects.filter(email__iexact="supplier@marche-cm.local").first()
buyer = U.objects.filter(email__iexact="buyer@marche-cm.local").first()
driver = U.objects.filter(id=DRIVER_ID).first()

# 1) Vendeur a l'etranger -> force INTERNATIONAL
if seller:
    seller.country_code = "CN"
    seller.save(update_fields=["country_code"])
    print(f"seller {seller.id} country_code -> {seller.country_code} (verified={seller.is_verified} kyc={seller.kyc_level})")
print(f"buyer {getattr(buyer,'id',None)} country_code={getattr(buyer,'country_code',None)}")

# 2) Produit vendeur avec poids
prods = Product.objects.filter(seller=seller).order_by("id")
print(f"products of seller: {prods.count()}")
target = prods.first()
if target:
    if target.weight_kg is None or Decimal(target.weight_kg) <= 0:
        target.weight_kg = Decimal("2.0")
        target.save(update_fields=["weight_kg"])
    print(f"TARGET PRODUCT id={target.id} title={target.title!r} weight={target.weight_kg} "
          f"min={target.min_order_qty} max={target.max_order_qty} "
          f"pmin={target.price_for_min_qty} pmax={target.price_for_max_qty} active={target.is_active}")

# 3) Livreur onboarde : trust + profil + tarifs
if driver:
    driver.trust_score = Decimal("5.00")
    driver.kyc_level = max(int(driver.kyc_level or 0), 1)
    driver.save(update_fields=["trust_score", "kyc_level"])
    tp, _ = TransportProfile.objects.get_or_create(user=driver)
    tp.is_active = True
    tp.air_price_per_kg = 3500
    tp.sea_price_per_kg = 1800
    if hasattr(tp, "average_eta_days"):
        tp.average_eta_days = 7
    tp.save()
    print(f"driver {driver.id} trust={driver.trust_score} kyc={driver.kyc_level} verified={driver.is_verified} "
          f"profile(active={tp.is_active} air={tp.air_price_per_kg} sea={tp.sea_price_per_kg})")

# 4) Exclusivite du livreur 33 dans la liste transitaires (cart prend les 3 premiers)
others = TransportProfile.objects.exclude(user_id=DRIVER_ID)
n = others.update(is_active=False)
print(f"deactivated {n} other transport profiles (driver {DRIVER_ID} reste seul actif)")
