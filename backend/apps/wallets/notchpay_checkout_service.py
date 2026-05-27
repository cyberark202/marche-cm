import json
import urllib.error
import urllib.request
from decimal import Decimal, InvalidOperation
from urllib.parse import quote

from django.conf import settings


class NotchPayCheckoutService:
    CREATE_PATH = "/payments"
    RETRIEVE_PATH = "/payments/{reference}"

    @classmethod
    def is_enabled(cls) -> bool:
        return settings.NOTCHPAY_ENABLED and bool(settings.NOTCHPAY_PUBLIC_KEY)

    @classmethod
    def _base_url(cls) -> str:
        return (settings.NOTCHPAY_API_BASE or "https://api.notchpay.co").rstrip("/")

    @classmethod
    def _headers(cls) -> dict[str, str]:
        return {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": settings.NOTCHPAY_PUBLIC_KEY,
        }

    @classmethod
    def _post_json(cls, url: str, payload: dict) -> dict:
        encoded = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=encoded, headers=cls._headers(), method="POST")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
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
            with urllib.request.urlopen(req, timeout=20) as resp:
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
    def _is_success_code(cls, code) -> bool:
        code_str = str(code or "").strip()
        if not code_str:
            return True
        return code_str in {"200", "201", "202"}

    # Audit ref: NotchPay channel routing — buyers selecting Orange Money were
    # locked on the MTN payment page because locked_channel hard-coded to the
    # first entry of NOTCHPAY_CHECKOUT_CHANNELS. The map below converts the
    # caller-side `provider` ("mtn", "orange", ...) to NotchPay's channel id.
    _PROVIDER_TO_CHANNEL = {
        "mtn": "cm.mtn",
        "cm.mtn": "cm.mtn",
        "orange": "cm.orange",
        "cm.orange": "cm.orange",
    }

    @classmethod
    def create_invoice(
        cls,
        *,
        amount,
        description: str,
        tx_ref: str,
        provider: str | None = None,
        customer_name: str | None = None,
        customer_email: str | None = None,
    ) -> dict:
        if not settings.NOTCHPAY_ENABLED:
            return {"mode": "SIMULATED", "detail": "NOTCHPAY_ENABLED=False"}
        if not cls.is_enabled():
            return {"mode": "LIVE", "error": "Configuration NotchPay incomplete."}

        normalized_amount = cls._normalize_amount(amount)
        if not normalized_amount:
            return {"mode": "LIVE", "error": "Montant invalide (entier requis)."}

        callback_url = (
            settings.NOTCHPAY_CHECKOUT_RETURN_URL
            or settings.NOTCHPAY_CHECKOUT_CALLBACK_URL
            or settings.BACKEND_PUBLIC_URL
        )
        payload = {
            "amount": int(normalized_amount),
            "currency": settings.NOTCHPAY_CURRENCY or "XAF",
            "reference": tx_ref,
            "description": description,
            "callback": callback_url,
            "metadata": {
                "tx_ref": tx_ref,
            },
        }

        customer_payload: dict[str, str] = {}
        if customer_name:
            customer_payload["name"] = customer_name
        if customer_email:
            customer_payload["email"] = customer_email
        if customer_payload:
            payload["customer"] = customer_payload

        # Route to the channel that matches what the buyer picked. If the
        # provider hint is unknown OR the configured list excludes that
        # channel, we leave locked_channel out so NotchPay falls back to its
        # own channel picker — that's safer than locking the wrong rail.
        channels = [channel for channel in settings.NOTCHPAY_CHECKOUT_CHANNELS if channel]
        if channels:
            mapped = cls._PROVIDER_TO_CHANNEL.get((provider or "").lower())
            if mapped and mapped in channels:
                payload["locked_channel"] = mapped
            elif len(channels) == 1:
                payload["locked_channel"] = channels[0]

        result = cls._post_json(f"{cls._base_url()}{cls.CREATE_PATH}", payload)
        if result.get("error"):
            return {
                "mode": "LIVE",
                "error": result.get("error", "Erreur NotchPay."),
                "raw": result.get("raw", {}),
                "status_code": result.get("status_code"),
            }

        if not cls._is_success_code(result.get("code")):
            return {
                "mode": "LIVE",
                "error": str(result.get("message") or "Echec creation payment."),
                "raw": result,
                "status_code": result.get("code"),
            }

        transaction = result.get("transaction") if isinstance(result.get("transaction"), dict) else {}
        payment_id = str(transaction.get("id") or "").strip()
        payment_reference = str(transaction.get("reference") or tx_ref).strip()
        checkout_url = str(
            result.get("authorization_url")
            or result.get("checkout_url")
            or transaction.get("authorization_url")
            or ""
        ).strip()
        if not checkout_url:
            return {
                "mode": "LIVE",
                "error": "URL de paiement NotchPay introuvable.",
                "raw": result,
            }

        return {
            "mode": "LIVE",
            "invoice_token": payment_id or payment_reference,
            "checkout_url": checkout_url,
            "reference": payment_reference,
            "provider_transaction_id": payment_id,
            "response_code": str(result.get("code") or ""),
            "response_text": str(result.get("message") or ""),
            "raw": result,
        }

    @classmethod
    def confirm_invoice(cls, *, token: str) -> dict:
        if not cls.is_enabled():
            return {"mode": "SIMULATED", "token": token, "status": "complete"}
        safe_token = quote(str(token or "").strip())
        result = cls._get_json(f"{cls._base_url()}{cls.RETRIEVE_PATH.format(reference=safe_token)}")
        if result.get("error"):
            return {
                "mode": "LIVE",
                "token": token,
                "status": "error",
                "error": result.get("error", "Erreur NotchPay."),
                "raw": result.get("raw", {}),
                "status_code": result.get("status_code"),
            }
        transaction = result.get("transaction") if isinstance(result.get("transaction"), dict) else {}
        status = str(transaction.get("status") or "").strip().lower()
        return {"mode": "LIVE", "token": token, "status": status, "raw": transaction or result}
