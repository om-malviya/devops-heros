# Node.js Hello World - single stage, no third-party dependencies
FROM node:22-alpine

WORKDIR /app

# Only the two files the app needs (no npm install required - no dependencies)
COPY package.json server.js ./

# Run as the unprivileged "node" user that ships with the official image
USER node

EXPOSE 3000

CMD ["node", "server.js"]
