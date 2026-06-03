"""Single source of truth for KYC / compliance document type groupings.

Audit ref: [M-2][M-3]. Previously the accepted document types were declared
twice — in ``BuyerKycSubmitView.IDENTITY_DOC_TYPES`` (view) and in
``ComplianceDocumentSerializer.ALLOWED_DOC_TYPES`` (serializer) — and the two
sets had drifted: the view advertised ``PROOF_ADDRESS`` and ``SELFIE`` while the
serializer rejected them, so the buyer KYC wizard 400'd on those steps. Both now
import from here.
"""

# Business certifications — unique per user (a user holds at most one of each).
CERTIFICATION_DOC_TYPES = frozenset(
    {
        "CERT_BUSINESS_REGISTRATION",
        "CERT_TAX_CLEARANCE",
        "CERT_EXPORT_LICENSE",
        "CERT_IMPORT_LICENSE",
        "CERT_QUALITY_STANDARD",
        "CERT_INSURANCE",
    }
)

# Identity / KYC documents — re-submittable (a new upload replaces the prior one
# of the same type instead of raising "already exists").
IDENTITY_DOC_TYPES = frozenset(
    {
        "CNI",
        "CNI_VERSO",
        "PASSPORT",
        "DRIVER_LICENSE",
        "PROOF_ADDRESS",
        "SELFIE",
    }
)

# Subset a BUYER may submit through the dedicated /api/auth/kyc/submit/ endpoint.
BUYER_IDENTITY_DOC_TYPES = frozenset(
    {"CNI", "CNI_VERSO", "PASSPORT", "PROOF_ADDRESS", "SELFIE"}
)

# Every document type accepted anywhere in the platform.
ALLOWED_DOC_TYPES = CERTIFICATION_DOC_TYPES | IDENTITY_DOC_TYPES
