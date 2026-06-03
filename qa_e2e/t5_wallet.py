"""E2E batch 5 — Wallet validation gates (NO live NotchPay call).
All paths tested here return BEFORE NotchPayCheckoutService.create_invoice /
NotchPayDisbursementService.send_money, so no money/link is created.
The real 1000 FCFA recharge link is handled separately with explicit consent."""
from qa import Client, record, S, B, set_sensitive_otp, django_setup

PWD = "ChangeMe123!"
BUYER = "buyer@marche-cm.local"
PIN = "1234"
PHONE = "+237670766331"


def main():
    c = Client("buyer"); c.login(BUYER, PWD)

    # --- T5.1 Wallet retrieve (balance) ---
    r = c.req("GET", "/api/wallets/", note="wallet list")
    record("T5.1", "Consultation du wallet (solde)", "major", S(r) == 200,
           "200", f"status={S(r)} body={B(r,160)}", endpoint="GET /api/wallets/")

    # --- T5.2 Topup invalid amount -> 400 (before NotchPay) ---
    r = c.req("POST", "/api/wallets/topup/", json_body={
        "amount": "abc", "provider": "MOBILE_MONEY", "source_phone": PHONE, "pin": PIN}, note="topup bad amount")
    record("T5.2", "Recharge montant invalide rejetée", "major", S(r) == 400,
           "400", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/wallets/topup/")

    # --- T5.3 Topup KYC per-transaction limit (30000 > 25000 @ level 0) -> 400 (before NotchPay) ---
    r = c.req("POST", "/api/wallets/topup/", json_body={
        "amount": "30000", "provider": "MOBILE_MONEY", "source_phone": PHONE, "pin": PIN}, note="topup kyc limit")
    record("T5.3", "Recharge au-delà de la limite KYC niveau 0 (25000) rejetée", "critical",
           S(r) == 400 and "KYC" in B(r, 200), "400 (limite KYC)", f"status={S(r)} body={B(r,160)}",
           endpoint="POST /api/wallets/topup/", be_file="apps/wallets/views.py:_enforce_kyc_limits")

    # --- T5.4 Topup missing PIN -> 400 (before NotchPay) ---
    r = c.req("POST", "/api/wallets/topup/", json_body={
        "amount": "1000", "provider": "MOBILE_MONEY", "source_phone": PHONE}, note="topup no pin")
    record("T5.4", "Recharge sans PIN wallet rejetée", "critical", S(r) == 400,
           "400 (PIN requis)", f"status={S(r)} body={B(r,120)}",
           endpoint="POST /api/wallets/topup/", be_file="apps/wallets/views.py:_validate_wallet_security")

    # --- T5.5 Topup invalid provider -> 400 ---
    r = c.req("POST", "/api/wallets/topup/", json_body={
        "amount": "1000", "provider": "BITCOIN", "source_phone": PHONE, "pin": PIN}, note="topup bad provider")
    record("T5.5", "Recharge moyen de paiement invalide rejetée", "minor", S(r) == 400,
           "400", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/wallets/topup/")

    # --- T5.6 Topup invalid phone format -> 400 ---
    r = c.req("POST", "/api/wallets/topup/", json_body={
        "amount": "1000", "provider": "MOBILE_MONEY", "source_phone": "12345", "pin": PIN}, note="topup bad phone")
    record("T5.6", "Recharge numéro Mobile Money invalide rejetée", "minor", S(r) == 400,
           "400", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/wallets/topup/")

    # --- T5.7 Withdraw without 2FA challenge -> 403 ---
    r = c.req("POST", "/api/wallets/withdraw/", json_body={
        "amount": "1000", "provider": "MOBILE_MONEY", "destination_phone": PHONE, "pin": PIN}, note="withdraw no 2fa")
    record("T5.7", "Retrait sans challenge 2FA refusé", "critical", S(r) == 403,
           "403 (2FA requise)", f"status={S(r)} body={B(r,120)}",
           endpoint="POST /api/wallets/withdraw/", be_file="apps/wallets/views.py:_validate_wallet_security WITHDRAW")

    # --- T5.8 Withdraw with 2FA + PIN but insufficient funds -> 400 (before disburse) ---
    c.req("POST", "/api/auth/sensitive-action/request/", json_body={"action_key": "wallet.withdraw"}, note="req withdraw otp")
    tok, code = set_sensitive_otp(BUYER, "wallet.withdraw")
    r = c.req("POST", "/api/wallets/withdraw/", json_body={
        "amount": "1000", "provider": "MOBILE_MONEY", "destination_phone": PHONE, "pin": PIN,
        "challenge_token": tok, "verification_code": code}, note="withdraw insufficient")
    record("T5.8", "Retrait à solde insuffisant rejeté (avant tout disbursement)", "critical",
           S(r) == 400 and "insuffisant" in B(r, 200).lower(), "400 (solde insuffisant)",
           f"status={S(r)} body={B(r,140)}", endpoint="POST /api/wallets/withdraw/",
           be_file="apps/wallets/views.py:773 (check avant send_money:817)")

    # --- T5.9 Wallet PIN policy: trivial/short PIN rejected (no change applied) ---
    r = c.req("POST", "/api/auth/wallet-pin/", json_body={"pin": "111111"}, note="pin trivial")
    record("T5.9", "Définition PIN trivial (111111) rejetée", "major", S(r) == 400,
           "400", f"status={S(r)} body={B(r,120)}", endpoint="POST /api/auth/wallet-pin/",
           be_file="apps/accounts/views.py:WalletPinView")

    # --- T5.10 Transactions history endpoint ---
    r = c.req("GET", "/api/wallets/transactions/", note="tx history")
    record("T5.10", "Historique des transactions wallet accessible", "minor", S(r) in (200,),
           "200", f"status={S(r)} body={B(r,120)}", endpoint="GET /api/wallets/transactions/")

    # --- T5.11 IDOR: cannot read another user's wallet by id ---
    r = c.req("GET", "/api/wallets/999999/", note="wallet idor")
    record("T5.11", "IDOR wallet: accès à un wallet arbitraire bloqué", "critical", S(r) == 404,
           "404 (queryset filtré sur owner)", f"status={S(r)}", endpoint="GET /api/wallets/{id}/")

    # reset any PIN failure counter just in case
    django_setup()
    from apps.accounts.models import User
    u = User.objects.filter(email__iexact=BUYER).first()
    if u:
        u.wallet_pin_failed_attempts = 0
        u.wallet_pin_locked_until = None
        u.save(update_fields=["wallet_pin_failed_attempts", "wallet_pin_locked_until"])


if __name__ == "__main__":
    main()
