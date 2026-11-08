FROM node:20-slim

WORKDIR /app

# Production images skip devDependencies; docker-compose builds with NODE_ENV=development for nodemon
ARG NODE_ENV=production
ENV NODE_ENV=$NODE_ENV

COPY package*.json ./
RUN if [ "$NODE_ENV" = "production" ]; then npm ci --omit=dev; else npm ci; fi

COPY . .

EXPOSE 5000
CMD ["node", "server.js"]
