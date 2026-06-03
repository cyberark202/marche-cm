"""Accounts Celery tasks.

Audit ref: [M-1] User geocoding runs OUT of the registration request path. The
previous synchronous Nominatim call inside RegisterSerializer.create() blocked
every signup for 2.5–8.6 s (and up to the 10 s HTTP timeout when OSM was slow),
tying up a worker and exposing a DoS amplification surface.
"""
import logging

from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(
    name="apps.accounts.tasks.user_geocode_task",
    bind=True,
    max_retries=2,
    default_retry_delay=60,
    queue="default",
)
def user_geocode_task(self, user_id: int) -> dict:
    """Best-effort reverse/forward geocoding of a user's city/country.

    Bounded retries, silent fallback: a failure here must never surface to the
    user — their account already exists, only the optional lat/long enrichment
    is deferred.
    """
    from apps.accounts.location_service import update_user_location
    from apps.accounts.models import User

    user = User.objects.filter(id=user_id).first()
    if user is None:
        return {"user_id": user_id, "localized": False, "reason": "user_not_found"}
    try:
        localized = update_user_location(user, force=True)
        return {"user_id": user_id, "localized": bool(localized)}
    except Exception as exc:  # network/provider error — retry a bounded number of times
        try:
            raise self.retry(exc=exc)
        except self.MaxRetriesExceededError:
            logger.warning("user_geocode_failed user_id=%s err=%s", user_id, exc)
            return {"user_id": user_id, "localized": False, "reason": "error"}
