"""Attribution automatique des missions livreur (doc 07).

Modèle : à l'acceptation vendeur, le système offre la mission au livreur
éligible le plus proche (haversine vendeur → livreur). Le livreur dispose
d'un délai configurable ("logistics.dispatch_offer_minutes", 15 min par
défaut) pour accepter ; à expiration ou refus, l'offre cascade au suivant.
S'il n'existe plus aucun candidat, on retombe sur la diffusion large
(mode devis historique) pour ne jamais bloquer une commande.
"""
import logging
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from apps.accounts.models import UserRole
from apps.appconfig.models import get_platform_setting
from apps.notifications.realtime import broadcast_event
from apps.notifications.service import create_realtime_notification
from apps.orders.shipping import haversine_km
from .models import DispatchOffer, DispatchOfferStatus, TransportProfile

logger = logging.getLogger(__name__)


def _eligible_profiles(shipment):
    country = (getattr(shipment, "country_code", "") or "CM").upper()
    return TransportProfile.objects.filter(
        is_active=True,
        coverage_countries__icontains=country,
        user__is_active=True,
        user__is_verified=True,
        user__role=UserRole.TRANSIT_AGENT,
    ).select_related("user")


def _ranked_candidates(shipment):
    """Livreurs éligibles triés du plus proche au plus lointain du vendeur.

    Les livreurs sans coordonnées GPS passent en fin de liste (distance
    inconnue) plutôt que d'être exclus — mieux vaut une offre lointaine
    qu'aucune offre.
    """
    seller = shipment.seller
    slat = getattr(seller, "location_latitude", None)
    slon = getattr(seller, "location_longitude", None)
    ranked: list[tuple[float, object]] = []
    for profile in _eligible_profiles(shipment):
        driver = profile.user
        dlat, dlon = driver.location_latitude, driver.location_longitude
        if None in (slat, slon, dlat, dlon):
            distance = float("inf")
        else:
            distance = haversine_km(slat, slon, dlat, dlon)
        ranked.append((distance, driver))
    ranked.sort(key=lambda pair: pair[0])
    return ranked


def start_dispatch(shipment):
    """Démarre la cascade d'attribution pour une expédition sans livreur."""
    if shipment is None or shipment.transit_agent_id is not None:
        return None
    return offer_to_next_driver(shipment)


def offer_to_next_driver(shipment):
    """Crée une offre pour le prochain livreur le plus proche jamais sollicité.

    Retourne l'offre créée, ou None quand la liste est épuisée (repli sur la
    diffusion large / mode devis).
    """
    if shipment.transit_agent_id is not None:
        return None
    already_offered = set(
        DispatchOffer.objects.filter(shipment=shipment).values_list("driver_id", flat=True)
    )
    minutes = int(get_platform_setting("logistics.dispatch_offer_minutes"))
    for distance, driver in _ranked_candidates(shipment):
        if driver.id in already_offered:
            continue
        offer = DispatchOffer.objects.create(
            shipment=shipment,
            driver=driver,
            distance_km=None if distance == float("inf") else Decimal(str(round(distance, 2))),
            expires_at=timezone.now() + timedelta(minutes=minutes),
        )
        try:
            create_realtime_notification(
                user=driver,
                title="Nouvelle mission de livraison",
                body=(
                    f"Mission #{shipment.id} : {shipment.pickup_address} -> {shipment.dropoff_address}. "
                    f"Vous avez {minutes} minutes pour accepter."
                ),
                payload={"shipment_id": shipment.id, "dispatch_offer_id": offer.id, "topic": "logistics"},
            )
        except Exception:
            logger.exception("dispatch_offer_notify_failed offer=%s driver=%s", offer.id, driver.id)
        broadcast_event(
            "logistics",
            "dispatch_offered",
            {"shipment_id": shipment.id, "offer_id": offer.id, "driver_id": driver.id},
        )
        return offer
    # Liste épuisée : diffusion large pour que les livreurs proposent un devis.
    logger.info("dispatch_exhausted shipment=%s -> fallback broadcast", shipment.id)
    notify_available_drivers(shipment)
    return None


def notify_available_drivers(shipment) -> int:
    """Diffusion large (mode devis) : notifie tous les livreurs éligibles.

    Repli quand la cascade d'offres est épuisée. Best-effort : ne bloque
    JAMAIS le flux appelant. Retourne le nombre de livreurs notifiés.
    """
    if shipment is None or shipment.transit_agent_id is not None:
        return 0
    notified = 0
    for profile in _eligible_profiles(shipment):
        try:
            create_realtime_notification(
                user=profile.user,
                title="Nouvelle course disponible",
                body=f"Expedition #{shipment.id} a pourvoir pres de chez vous. Proposez votre devis.",
                payload={"shipment_id": shipment.id, "topic": "logistics"},
            )
            notified += 1
        except Exception:
            logger.exception(
                "dispatch_notify_failed shipment=%s driver=%s", shipment.id, profile.user_id
            )
    broadcast_event(
        "logistics",
        "dispatch_available",
        {"shipment_id": shipment.id, "drivers_notified": notified},
    )
    return notified
