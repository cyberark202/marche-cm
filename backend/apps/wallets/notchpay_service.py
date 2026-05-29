import json
import urllib.error
import urllib.request
from decimal import Decimal, InvalidOperation
from urllib.parse import quote

from django.conf import settings


class NotchPayDisbursementService:
    CREATE_TRANSFER_PATH = "/transfers"
    RETRIEVE_TRANSFER_PATH = "/transfers/{identifier}"

    @classmethod
    def is_enabled(cls) -> bool:
        return (
            settings.NOTCHPAY_ENABLED
            and bool(settings.NOTCHPAY_PUBLIC_KEY)
            and bool(settings.NOTCHPAY_PRIVATE_KEY)
        )

    @classmethod
    def withdraw_channel_for(cls, provider: str) -> str:
        if provider == "MOBILE_MONEY":
            return settings.NOTCHPAY_WITHDRAW_CHANNEL_MTN
        if provider == "ORANGE_MONEY":
            return settings.NOTCHPAY_WITHDRAW_CHANNEL_ORANGE
        if provider == "VISA":
            return settings.NOTCHPAY_WITHDRAW_CHANNEL_VISA
        if provider == "MASTERCARD":
            return settings.NOTCHPAY_WITHDRAW_CHANNEL_MASTERCARD
        if provider == "PAYPAL":
            return settings.NOTCHPAY_WITHDRAW_CHANNEL_PAYPAL
        return ""

    @classmethod
    def _base_url(cls) -> str:
        return (settings.NOTCHPAY_API_BASE or "https://api.notchpay.co").rstrip("/")

    @classmethod
    def _headers(cls) -> dict[str, str]:
        return {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": settings.NOTCHPAY_PUBLIC_KEY,
            "X-Grant": settings.NOTCHPAY_PRIVATE_KEY,
        }

    @classmethod
    def _post_json(cls, url: str, payload: dict) -> dict:
        encoded = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=encoded, headers=cls._headers(), method="POST")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:  # nosec B310 - URL is NOTCHPAY_API_BASE (server-configured HTTPS)
                body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
        except urllib.error.HTTPError as exc:
            try:
                body = exc.read().decode("utf-8")
                payload = json.loads(body) if body else {}
            except Exception:
                payload = {}
            return {
                "error": f"NotchPay HTTP {exc.code}: {exc.reason}",
                "status_code": exc.code,
                "raw": payload,
            }
        except urllib.error.URLError as exc:
            return {"error": f"NotchPay unreachable: {exc.reason}", "raw": {}}

    @classmethod
    def _get_json(cls, url: str) -> dict:
        req = urllib.request.Request(url, headers=cls._headers(), method="GET")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:  # nosec B310 - URL is NOTCHPAY_API_BASE (server-configured HTTPS)
                body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
        except urllib.error.HTTPError as exc:
            try:
                body = exc.read().decode("utf-8")
                payload = json.loads(body) if body else {}
            except Exception:
                payload = {}
            return {
                "error": f"NotchPay HTTP {exc.code}: {exc.reason}",
                "status_code": exc.code,
                "raw": payload,
            }
        except urllib.error.URLError as exc:
            return {"error": f"NotchPay unreachable: {exc.reason}", "raw": {}}

    @classmethod
    def _normalize_amount(cls, amount) -> str | None:
        try:
            amount_decimal = Decimal(str(amount))
        except (InvalidOperation, TypeError):
            return None
        if amount_decimal <= 0:
            return None
        amount_int = int(amount_decimal)
        if amount_decimal != Decimal(amount_int):
            return None
        return str(amount_int)

    @classmethod
    def _normalize_account_alias(cls, *, provider: str, alias: str) -> str:
        value = str(alias or "").strip()
        if not value:
            return ""
        if provider in {"MOBILE_MONEY", "ORANGE_MONEY"}:
            digits = "".join(ch for ch in value if ch.isdigit())
            if not digits:
                return ""
            default_country_code = str(settings.NOTCHPAY_DEFAULT_COUNTRY_CODE or "").strip()
            if default_country_code and not digits.startswith(default_country_code):
                digits = f"{default_country_code}{digits}"
            return f"+{digits}"
        if provider in {"VISA", "MASTERCARD"}:
            return "".join(ch for ch in value if ch.isdigit())
        return value

    @classmethod
    def _is_success_code(cls, code) -> bool:
        code_str = str(code or "").strip()
        if not code_str:
            return True
        return code_str in {"200", "201", "202"}

    @classmethod
    def send_money(
        cls,
        *,
        amount,
        provider,
        account_alias=None,
        phone=None,
        transaction_id=None,
        account_name=None,
    ) -> dict:
        if transaction_id is None:
            transaction_id = "WALLET"
        provider = str(provider or "").upper()
        account_alias = account_alias if account_alias is not None else phone
        normalized_alias = cls._normalize_account_alias(provider=provider, alias=str(account_alias or ""))
        if not settings.NOTCHPAY_ENABLED:
            return {
                "mode": "SIMULATED",
                "transaction_id": str(transaction_id),
                "phone": normalized_alias,
                "provider": provider,
                "amount": str(amount),
                "detail": "NOTCHPAY_ENABLED=False",
            }
        if not cls.is_enabled():
            return {
                "mode": "LIVE",
                "transaction_id": str(transaction_id),
                "error": "Configuration NotchPay incomplete.",
            }

        withdraw_channel = cls.withdraw_channel_for(provider)
        if not withdraw_channel:
            return {
                "mode": "LIVE",
                "transaction_id": str(transaction_id),
                "error": f"withdraw_channel introuvable pour provider={provider}.",
            }

        normalized_amount = cls._normalize_amount(amount)
        if not normalized_amount:
            return {
                "mode": "LIVE",
                "transaction_id": str(transaction_id),
                "error": "Montant invalide (NotchPay requiert un entier).",
            }

        if not normalized_alias:
            return {
                "mode": "LIVE",
                "transaction_id": str(transaction_id),
                "error": "account_alias manquant.",
            }

        beneficiary_data: dict[str, str] = {
            "name": str(account_name or "Beneficiary").strip() or "Beneficiary",
            "phone": normalized_alias,
        }
        if provider in {"VISA", "MASTERCARD"}:
            beneficiary_data["account_number"] = normalized_alias
        if provider == "PAYPAL":
            beneficiary_data["email"] = normalized_alias

        payload = {
            "amount": int(normalized_amount),
            "currency": settings.NOTCHPAY_CURRENCY or "XAF",
            "channel": withdraw_channel,
            "reference": str(transaction_id),
            "description": f"Payout {transaction_id}",
            "beneficiary_data": beneficiary_data,
            "metadata": {
                "callback_url": settings.NOTCHPAY_DISBURSE_CALLBACK_URL or settings.BACKEND_PUBLIC_URL,
            },
        }

        result = cls._post_json(f"{cls._base_url()}{cls.CREATE_TRANSFER_PATH}", payload)
        if result.get("error"):
            return {
                "mode": "LIVE",
                "transaction_id": str(transaction_id),
                "error": result.get("error", "Erreur NotchPay transfer."),
                "raw": result.get("raw", {}),
                "status_code": result.get("status_code"),
            }

        if not cls._is_success_code(result.get("code")):
            return {
                "mode": "LIVE",
                "transaction_id": str(transaction_id),
                "error": str(result.get("message") or "Echec transfer."),
                "raw": result,
                "status_code": result.get("code"),
            }

        transfer = result.get("transfer") if isinstance(result.get("transfer"), dict) else {}
        transfer_id = str(transfer.get("id") or "").strip()
        transfer_reference = str(transfer.get("reference") or transaction_id).strip()
        transfer_status = str(transfer.get("status") or "").strip().lower()

        response_payload = {
            "mode": "LIVE",
            "transaction_id": transfer_reference or str(transaction_id),
            "provider_transaction_id": transfer_id,
            "response_code": str(result.get("code") or ""),
            "response_text": str(result.get("message") or ""),
            "status": transfer_status,
            "raw": result,
        }
        if transfer_status in {"failed", "canceled"}:
            response_payload["error"] = str(result.get("message") or "Transfer failed.")
        return response_payload

    @classmethod
    def check_status(cls, *, invoice_token: str) -> dict:
        if not cls.is_enabled():
            return {"mode": "SIMULATED", "invoice_token": invoice_token, "status": "SUCCESS"}
        safe_identifier = quote(str(invoice_token or "").strip())
        result = cls._get_json(f"{cls._base_url()}{cls.RETRIEVE_TRANSFER_PATH.format(identifier=safe_identifier)}")
        if result.get("error"):
            return {
                "mode": "LIVE",
                "invoice_token": invoice_token,
                "status": "UNKNOWN",
                "error": result.get("error"),
                "raw": result.get("raw", {}),
                "status_code": result.get("status_code"),
            }
        transfer = result.get("transfer") if isinstance(result.get("transfer"), dict) else {}
        provider_status = str(transfer.get("status") or "").strip().lower()
        if provider_status == "complete":
            status = "SUCCESS"
        elif provider_status in {"failed", "canceled"}:
            status = "FAILED"
        else:
            status = "PENDING"
        return {
            "mode": "LIVE",
            "invoice_token": invoice_token,
            "status": status,
            "provider_status": provider_status,
            "raw": transfer or result,
        }
