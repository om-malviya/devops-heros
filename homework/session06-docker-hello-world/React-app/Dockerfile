# React (Vite) Hello World - multi-stage build
# Stage 1: install dependencies and build the static bundle
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

# Stage 2: serve the static files with Nginx (no Node.js in the final image)
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80
