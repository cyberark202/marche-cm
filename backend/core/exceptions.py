"""
Domain exceptions hierarchy for Marché CM.
All service-level errors should raise these or subclasses.
"""


class MarcheCMError(Exception):
    """Root exception for all domain errors."""
    code: str = "error"
    http_status: int = 400


class InsufficientFundsError(MarcheCMError):
    code = "insufficient_funds"
    http_status = 422


class WalletLockedError(MarcheCMError):
    code = "wallet_locked"
    http_status = 423


class DuplicateTransactionError(MarcheCMError):
    code = "duplicate_transaction"
    http_status = 409


class EscrowError(MarcheCMError):
    code = "escrow_error"
    http_status = 422


class EscrowFrozenError(EscrowError):
    code = "escrow_frozen"
    http_status = 423


class InvalidTransitionError(MarcheCMError):
    code = "invalid_state_transition"
    http_status = 422


class KYCRequiredError(MarcheCMError):
    code = "kyc_required"
    http_status = 403


class DisputeError(MarcheCMError):
    code = "dispute_error"
    http_status = 422


class FraudFlaggedError(MarcheCMError):
    code = "fraud_flagged"
    http_status = 403


class LedgerBalanceError(MarcheCMError):
    code = "ledger_balance_error"
    http_status = 422


class PermissionDeniedError(MarcheCMError):
    code = "permission_denied"
    http_status = 403


class NotFoundError(MarcheCMError):
    code = "not_found"
    http_status = 404


class RateLimitError(MarcheCMError):
    code = "rate_limit_exceeded"
    http_status = 429
