FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production --no-audit --no-fund --fetch-retries=5 --fetch-retry-factor=2 --fetch-retry-maxtimeout=120000
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
