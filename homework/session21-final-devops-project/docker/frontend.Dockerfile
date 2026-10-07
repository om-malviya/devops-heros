# Build context: application/frontend
#   docker build -f docker/frontend.Dockerfile -t taskboard-frontend:local application/frontend
#
# Stage 1 - build the React/Vite bundle with Node
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install --no-audit --no-fund
COPY . .
RUN npm run build

# Stage 2 - serve the static files with an unprivileged nginx (runs as uid 101, listens on 8080).
# 1.27-alpine (Alpine 3.21, built 2025-06) failed the Trivy gate with 42 fixable HIGH/CRITICAL OS CVEs;
# 1.30-alpine (Alpine 3.24) is the current stable build and scans clean.
FROM nginxinc/nginx-unprivileged:1.30-alpine
# Defaults for the envsubst template; overridden in compose / Kubernetes.
ENV BACKEND_HOST=backend \
    BACKEND_PORT=8000
COPY --from=build /app/dist /usr/share/nginx/html
# The image entrypoint renders /etc/nginx/templates/*.template -> /etc/nginx/conf.d/
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
# The base image already switches to uid 101; repeating it keeps the Dockerfile self-describing for scanners (Trivy DS-0002).
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
