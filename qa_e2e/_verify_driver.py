# -*- coding: utf-8 -*-  (ligne 1 absorbe le BOM eventuel du shell interactif)
from django.contrib.auth import get_user_model
from apps.logistics.models import TransportProfile

U = get_user_model()
u = U.objects.filter(email__iexact="driver.e2e@marche-cm.local").first()
if not u:
    print("DRIVER NOT FOUND")
else:
    print(f"driver.e2e -> id={u.id} username={u.username} role={u.role} "
          f"is_verified={u.is_verified} kyc_level={u.kyc_level} trust={u.trust_score} active={u.is_active}")
    tp = TransportProfile.objects.filter(user=u).first()
    if tp:
        print(f"  TransportProfile: active={tp.is_active} air={tp.air_price_per_kg} sea={tp.sea_price_per_kg} veh={getattr(tp,'vehicle_types',None)}")
    else:
        print("  no TransportProfile")
    try:
        from apps.compliance.models import KYCDocument
        docs = KYCDocument.objects.filter(user=u)
        print(f"  KYC docs: {docs.count()} -> {list(docs.values_list('doc_type','status'))[:10]}")
    except Exception as e:
        print("  kyc docs query err:", e)
