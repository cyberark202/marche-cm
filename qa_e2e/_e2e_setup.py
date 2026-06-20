# -*- coding: utf-8 -*-
# Pre-vol E2E 2026-06-16 : credite le wallet acheteur + verifie KYC vendeur.
# Lance via : Get-Content qa_e2e\_e2e_setup.py | python backend\manage.py shell
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db import transaction

from apps.wallets.services import WalletAccountingService

User = get_user_model()

BUYER_EMAIL = "buyer@marche-cm.local"
SELLER_EMAIL = "supplier@marche-cm.local"
CREDIT_AMOUNT = Decimal("500000")

buyer = User.objects.filter(email__iexact=BUYER_EMAIL).first()
seller = User.objects.filter(email__iexact=SELLER_EMAIL).first()

print("=== PRE-VOL SETUP ===")
print("buyer:", buyer.id if buyer else None, "| seller:", seller.id if seller else None)

# --- 1. Verifier KYC vendeur (requis par les controles anti-fraude international)
if seller:
    changed = []
    if not seller.is_verified:
        seller.is_verified = True
        changed.append("is_verified")
    if (seller.kyc_level or 0) < 1:
        seller.kyc_level = 1
        changed.append("kyc_level")
    if changed:
        seller.save(update_fields=changed)
    print("seller is_verified=%s kyc_level=%s (changed=%s)" % (seller.is_verified, seller.kyc_level, changed))

# --- 2. Crediter le wallet acheteur (idempotent)
if buyer:
    with transaction.atomic():
        w = WalletAccountingService.get_wallet_for_update(user=buyer)
        before = w.available_balance
        WalletAccountingService.credit_available(
            wallet=w,
            amount=CREDIT_AMOUNT,
            reference="e2e:setup:buyer_topup",
            idempotency_key="e2e-2026-06-16-buyer-topup-500k",
            created_by=buyer,
            metadata={"source": "e2e_setup_script"},
        )
        w.refresh_from_db()
        print("buyer wallet available: %s -> %s (locked=%s pending=%s)" % (
            before, w.available_balance, w.locked_balance, w.pending_balance))

print("=== SETUP DONE ===")
