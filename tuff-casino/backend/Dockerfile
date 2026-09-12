FROM node:20-alpine
WORKDIR /app
COPY backend/package*.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY backend/src ./src
COPY database /database
COPY frontend /frontend
ENV NODE_ENV=production PORT=3000 MIGRATIONS_DIR=/database/migrations
EXPOSE 3000
CMD ["sh", "-c", "node src/migrate.js && node src/server.js"]
