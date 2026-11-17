FROM node:22-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

# Source files inherit restrictive host permissions, so make them readable to the runtime user.
COPY --chown=node:node run-workload.mjs ./
RUN chmod 0644 run-workload.mjs

USER node

CMD ["node", "run-workload.mjs"]
