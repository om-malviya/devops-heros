# -------------------------
# Stage 1: Build
# Installs ALL dependencies (including any devDependencies) and
# holds the full source tree. Nothing from here ends up in the
# final image unless it is explicitly COPY --from'd.
# -------------------------
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
# (A real project would run tests / linters / a bundler here.)

# -------------------------
# Stage 2: Production
# Fresh, small base image. Only the runtime files are copied in and
# only production dependencies are installed.
# -------------------------
FROM node:22-alpine AS production
ENV NODE_ENV=production
WORKDIR /app
COPY --from=builder /app/package*.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY --from=builder /app/server.js ./
USER node
EXPOSE 8080
CMD ["node", "server.js"]
