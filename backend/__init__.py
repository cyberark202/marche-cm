# Expose the Celery app so Django's auto-discovery (`from backend import app`) works.
# Import is deferred to celery_app.py to avoid the `celery` package name conflict.
from celery_app import app as celery_app  # noqa: F401

__all__ = ("celery_app",)
