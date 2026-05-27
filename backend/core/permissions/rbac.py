"""
RBAC + ABAC permission system for Marché CM.

Role hierarchy:
    GENERAL_ADMIN > SUPPLIER/WHOLESALER > TRANSIT_AGENT > BUYER

Usage (in DRF views):
    from core.permissions.rbac import IsGeneralAdmin, IsSupplierOrWholesaler, IsOwner

    class OrderView(APIView):
        permission_classes = [IsAuthenticated, IsOwnerOrAdmin]

Audit ref: [NEW-004] role comparisons use the UserRole enum (TextChoices)
instead of bare string literals so a future rename of the enum value gets
flagged at lint time rather than silently opening admin doors.
"""
from __future__ import annotations

from rest_framework.permissions import BasePermission, IsAuthenticated

from apps.accounts.models import UserRole


class _RolePermission(BasePermission):
    """Base class: grants access if user.role is in allowed_roles."""
    allowed_roles: tuple[str, ...] = ()

    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role in self.allowed_roles
        )


class IsGeneralAdmin(_RolePermission):
    allowed_roles = ("GENERAL_ADMIN",)


class IsSupplier(_RolePermission):
    allowed_roles = ("SUPPLIER",)


class IsWholesaler(_RolePermission):
    allowed_roles = ("WHOLESALER",)


class IsSupplierOrWholesaler(_RolePermission):
    allowed_roles = ("SUPPLIER", "WHOLESALER")


class IsTransitAgent(_RolePermission):
    allowed_roles = ("TRANSIT_AGENT",)


class IsBuyer(_RolePermission):
    allowed_roles = ("BUYER",)


class IsTrader(_RolePermission):
    """SUPPLIER + WHOLESALER + BUYER (anyone who trades)."""
    allowed_roles = ("SUPPLIER", "WHOLESALER", "BUYER")


class IsAdminOrReadOnly(BasePermission):
    def has_permission(self, request, view) -> bool:
        if request.method in ("GET", "HEAD", "OPTIONS"):
            return request.user and request.user.is_authenticated
        return bool(request.user and request.user.role == UserRole.GENERAL_ADMIN)


class IsOwner(BasePermission):
    """Object-level: user must be the owner (obj.owner or obj.user)."""
    owner_field: str = "user"

    def has_object_permission(self, request, view, obj) -> bool:
        owner = getattr(obj, self.owner_field, None)
        if owner is None:
            owner = getattr(obj, "owner", None)
        if owner is None:
            return False
        return owner == request.user


class IsOwnerOrAdmin(BasePermission):
    """Object-level: owner OR admin."""
    def has_object_permission(self, request, view, obj) -> bool:
        if getattr(request.user, "role", None) == UserRole.GENERAL_ADMIN:
            return True
        for field in ("user", "owner", "buyer", "seller"):
            owner = getattr(obj, field, None)
            if owner is not None and owner == request.user:
                return True
        return False


class IsVerifiedUser(BasePermission):
    """Only email-verified users can access."""
    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.is_verified
        )


class HasKYCLevel(BasePermission):
    """ABAC: user must have at least the required KYC level."""
    required_level: int = 1

    def has_permission(self, request, view) -> bool:
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.kyc_level >= self.required_level
        )


def require_kyc_level(level: int):
    """Factory: creates a permission class requiring the given KYC level."""
    class KYCPermission(HasKYCLevel):
        required_level = level
    KYCPermission.__name__ = f"RequiresKYCLevel{level}"
    return KYCPermission


RequiresKYC1 = require_kyc_level(1)
RequiresKYC2 = require_kyc_level(2)
