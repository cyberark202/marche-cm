"""
OpenTelemetry tracing setup for Marché CM.
Call configure_tracing() at application startup (in AppConfig.ready() or manage.py).
"""
from __future__ import annotations

import logging
import os

logger = logging.getLogger(__name__)


def configure_tracing() -> None:
    """
    Configure OpenTelemetry SDK if dependencies are available.
    Set OTEL_EXPORTER_OTLP_ENDPOINT env var to enable OTLP export.
    """
    try:
        from opentelemetry import trace
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.sdk.resources import Resource, SERVICE_NAME

        service_name = os.getenv("OTEL_SERVICE_NAME", "marche-cm-backend")
        resource = Resource.create({SERVICE_NAME: service_name})
        provider = TracerProvider(resource=resource)

        otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
        if otlp_endpoint:
            from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
            exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
            provider.add_span_processor(BatchSpanProcessor(exporter))

        trace.set_tracer_provider(provider)
        logger.info("otel_tracing_configured", extra={"service": service_name, "endpoint": otlp_endpoint})

    except ImportError:
        logger.info("otel_not_available", extra={"detail": "opentelemetry packages not installed — tracing disabled"})


def get_tracer(name: str = "marche-cm"):
    try:
        from opentelemetry import trace
        return trace.get_tracer(name)
    except ImportError:
        class _NoopTracer:
            def start_as_current_span(self, *_, **__):
                from contextlib import contextmanager
                @contextmanager
                def noop(*_a, **_kw):
                    yield None
                return noop()
        return _NoopTracer()
