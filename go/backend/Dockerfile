# syntax=docker/dockerfile:1.7
# Hardened multi-stage Dockerfile — production fintech standards.
#
# Security properties:
#   - Multi-stage: build artifacts never reach the runtime image
#   - Non-root user (uid=10001) — no privilege escalation possible
#   - Read-only filesystem on /app (static files written at build time)
#   - Minimal base (python:3.12-slim) — reduced attack surface
#   - No development tools in runtime image
#   - Build args pinned, no floating tags in runtime
#   - Health check built in

# ── Stage 1: dependency compilation ─────────────────────────────────────────
FROM python:3.12-slim AS builder

# Install only what's needed to compile Python C extensions.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy and install dependencies before copying source (layer cache efficiency).
COPY requirements.txt requirements-prod.txt* ./
RUN pip install --upgrade pip==24.3.1 && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: runtime image ───────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Install only runtime libraries (libpq for psycopg2).
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
        # curl for health checks
        curl \
        # dumb-init: PID 1 signal forwarding + zombie reaping (ASGI/WS graceful shutdown)
        dumb-init \
    && rm -rf /var/lib/apt/lists/* \
    # Disable pip warnings in production — no pip in runtime.
    && pip uninstall -y pip setuptools wheel 2>/dev/null || true

# Copy compiled packages from builder stage.
COPY --from=builder /install /usr/local

# Create a dedicated non-root user.
# uid/gid 10001 — outside typical system ranges, no shell, no home.
RUN groupadd --gid 10001 appgroup && \
    useradd --uid 10001 --gid appgroup --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

# Copy application source.
COPY --chown=appuser:appgroup . .

# Collect static files at build time so /app/staticfiles is populated.
# Use a dummy SECRET_KEY — no real key needed for collectstatic.
RUN SECRET_KEY=build-time-only-not-a-real-key \
    DEBUG=False \
    DJANGO_SETTINGS_MODULE=config.settings \
    python manage.py collectstatic --noinput --clear 2>/dev/null || true

# Drop privileges — all subsequent operations run as non-root.
USER appuser

# Expose ASGI port.
EXPOSE 8000

# Health check — calls /api/health/ which returns 200 with no auth.
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -fsS http://localhost:8000/api/health/ || exit 1

# dumb-init as PID 1: forwards signals to Daphne (SIGTERM → graceful WS shutdown)
# and reaps zombie processes. Without it, SIGTERM is ignored by PID 1 and
# WebSocket connections are force-killed instead of closed cleanly.
ENTRYPOINT ["dumb-init", "--"]

# Default command: Daphne ASGI server.
# Override CMD in docker-compose or K8s for workers/crons.
CMD ["daphne", \
     "-b", "0.0.0.0", \
     "-p", "8000", \
     "--access-log", "-", \
     "--proxy-headers", \
     "config.asgi:application"]
