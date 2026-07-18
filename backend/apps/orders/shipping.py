"""Calcul du cout de livraison base sur la distance vendeur -> acheteur.

L'acheteur ne choisit plus de transitaire : le cout est derive de la distance
geographique entre le vendeur (origine du colis) et l'acheteur (destination),
au tarif `SHIPPING_RATE_PER_KM` (FCFA/km). Quand l'une des parties n'a pas de
coordonnees GPS, on retombe sur `SHIPPING_DEFAULT_DISTANCE_KM`.
"""

from decimal import Decimal
import math

from django.conf import settings


def _to_decimal(value, default: str) -> Decimal:
    try:
        return Decimal(str(value))
    except Exception:  # noqa: BLE001
        return Decimal(default)


def haversine_km(lat1, lon1, lat2, lon2) -> float:
    """Distance grand-cercle en kilometres entre deux points GPS."""
    radius_km = 6371.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * radius_km * math.asin(min(1.0, math.sqrt(a)))


def distance_between(seller, buyer) -> Decimal:
    """Distance facturable (km) entre vendeur et acheteur.

    Repli sur `SHIPPING_DEFAULT_DISTANCE_KM` si une coordonnee manque ;
    plancher a `SHIPPING_MIN_DISTANCE_KM`.
    """
    default_km = _to_decimal(getattr(settings, "SHIPPING_DEFAULT_DISTANCE_KM", "5"), "5")
    min_km = _to_decimal(getattr(settings, "SHIPPING_MIN_DISTANCE_KM", "1"), "1")

    coords = (
        getattr(seller, "location_latitude", None),
        getattr(seller, "location_longitude", None),
        getattr(buyer, "location_latitude", None),
        getattr(buyer, "location_longitude", None),
    )
    if any(c is None for c in coords):
        km = default_km
    else:
        km = Decimal(str(haversine_km(*coords)))

    return km if km >= min_km else min_km


def compute_shipping_fee(seller, buyer) -> Decimal:
    """Cout de livraison = tarif/km * distance(vendeur, acheteur), arrondi au centime."""
    rate = _to_decimal(getattr(settings, "SHIPPING_RATE_PER_KM", "150"), "150")
    distance_km = distance_between(seller, buyer)
    return (rate * distance_km).quantize(Decimal("0.01"))
