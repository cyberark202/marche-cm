"""
Prometheus metrics for Marché CM.
Import and use these counters/histograms from services and views.
"""
from __future__ import annotations

try:
    from prometheus_client import Counter, Histogram, Gauge, Summary

    # HTTP
    http_requests_total = Counter(
        "marche_cm_http_requests_total",
        "Total HTTP requests",
        ["method", "endpoint", "status_code"],
    )
    http_request_duration_seconds = Histogram(
        "marche_cm_http_request_duration_seconds",
        "HTTP request duration",
        ["method", "endpoint"],
        buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
    )

    # Financial
    transactions_total = Counter(
        "marche_cm_transactions_total",
        "Total financial transactions",
        ["type", "status", "currency"],
    )
    transaction_amount = Histogram(
        "marche_cm_transaction_amount_xaf",
        "Financial transaction amount in XAF",
        ["type"],
        buckets=[1000, 5000, 10000, 50000, 100000, 500000, 1000000, 5000000],
    )

    # Escrow
    escrow_active_total = Gauge(
        "marche_cm_escrow_active_total",
        "Number of active escrow holds",
    )
    escrow_amount_locked = Gauge(
        "marche_cm_escrow_amount_locked_xaf",
        "Total amount locked in escrow (XAF)",
    )

    # Orders
    orders_total = Counter(
        "marche_cm_orders_total",
        "Total orders",
        ["status"],
    )

    # Fraud
    fraud_flags_total = Counter(
        "marche_cm_fraud_flags_total",
        "Total fraud flags raised",
        ["decision", "event_type"],
    )

    # Outbox
    outbox_events_total = Counter(
        "marche_cm_outbox_events_total",
        "Total outbox events",
        ["event_type", "status"],
    )
    outbox_processing_lag_seconds = Histogram(
        "marche_cm_outbox_processing_lag_seconds",
        "Lag between outbox event creation and processing",
        buckets=[1, 5, 15, 30, 60, 300, 600, 1800],
    )

    # WebSocket
    ws_connections_active = Gauge(
        "marche_cm_ws_connections_active",
        "Active WebSocket connections",
        ["consumer_type"],
    )

    METRICS_ENABLED = True

except ImportError:
    METRICS_ENABLED = False
    # Provide no-op stubs so code imports don't fail without prometheus_client
    class _Noop:
        def labels(self, **_): return self
        def inc(self, *_, **__): pass
        def observe(self, *_, **__): pass
        def set(self, *_, **__): pass
        def __call__(self, *_, **__): return self

    http_requests_total = _Noop()
    http_request_duration_seconds = _Noop()
    transactions_total = _Noop()
    transaction_amount = _Noop()
    escrow_active_total = _Noop()
    escrow_amount_locked = _Noop()
    orders_total = _Noop()
    fraud_flags_total = _Noop()
    outbox_events_total = _Noop()
    outbox_processing_lag_seconds = _Noop()
    ws_connections_active = _Noop()
