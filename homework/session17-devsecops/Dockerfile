# Session 17 - DevSecOps demo image (hardened)
FROM python:3.12-slim

ARG GIT_SHA=local
ARG APP_VERSION=1.0.0
ENV GIT_SHA=${GIT_SHA} \
    APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Patch OS packages so the image scan does not flag already-fixed CVEs
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# Install the pinned dependencies, then remove the package manager from the runtime image.
# Trivy in CI (run #37717126323) flagged the pip bundled with python:3.12-slim (25.0.1) for five
# fixable MEDIUM CVEs; upgrading pip to 26.x (run #37717503027) replaced them with four HIGH CVEs in
# pip's vendored msgpack/urllib3/setuptools. A runtime image never needs pip, so the smallest attack
# surface is to uninstall it after the dependencies are in place.
RUN pip install --no-cache-dir -r requirements.txt \
 && python -m pip uninstall -y pip setuptools wheel

COPY app ./app

# Dedicated non-root user; the filesystem is read-only at runtime (see k8s securityContext)
RUN groupadd --system app && useradd --system --gid app --uid 10001 --no-create-home app \
    && chown -R app:app /app
USER app

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app.main:app"]
