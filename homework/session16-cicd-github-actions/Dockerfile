# Session 16 - calculator API image
FROM python:3.12-slim

# Build-time metadata (set by the CI pipeline)
ARG GIT_SHA=local
ARG APP_VERSION=1.0.0
ENV GIT_SHA=${GIT_SHA} \
    APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install dependencies first so this layer is cached between code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Run as a non-root user. USER must be the numeric uid (not the name "app"): with
# runAsNonRoot: true the kubelet cannot verify a named user and refuses to start the pod
# ("container has runAsNonRoot and image has non-numeric user").
RUN groupadd --system app && useradd --system --gid app --uid 10001 app \
    && chown -R app:app /app
USER 10001

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app.main:app"]
