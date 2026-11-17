FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --no-fund

COPY . .
# Host files inherit restrictive permissions, so normalise them for the runtime user.
RUN chmod -R a+rX /app && npm run build

ENV HOST=0.0.0.0
ENV PORT=8000
EXPOSE 8000

USER node

CMD ["npm", "run", "start"]
