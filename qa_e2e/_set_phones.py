# -*- coding: utf-8 -*-
from django.contrib.auth import get_user_model

U = get_user_model()
targets = {
    "supplier@marche-cm.local": "+237670000008",
    "driver.e2e@marche-cm.local": "+237670000033",
    "buyer@marche-cm.local": "+237670000011",
}
for email, phone in targets.items():
    u = U.objects.filter(email__iexact=email).first()
    if not u:
        print("skip (not found):", email); continue
    u.phone_number = phone
    u.save(update_fields=["phone_number"])
    print(f"{email} -> phone={u.phone_number}")
