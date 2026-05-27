"""
Celery settings — copier/importer dans settings.py
"""
import os

CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", os.getenv("REDIS_URL", "redis://localhost:6379/0"))
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", CELERY_BROKER_URL)
CELERY_RESULT_EXTENDED = True
CELERY_BEAT_SCHEDULER = "django_celery_beat.schedulers:DatabaseScheduler"

# Observability
PROMETHEUS_METRICS_EXPORT_PORT = int(os.getenv("PROMETHEUS_METRICS_EXPORT_PORT", "8001"))
PROMETHEUS_METRICS_EXPORT_ADDRESS = os.getenv("PROMETHEUS_METRICS_EXPORT_ADDRESS", "")
