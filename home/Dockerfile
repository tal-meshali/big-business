# Home server image (home/docker-compose.yml): builds the server runtime from
# source inside Docker, so the PC needs neither Node nor npm, then starts
# Nakama with the same flags as Fly (fly/start.sh).
FROM node:22-alpine AS runtime
WORKDIR /src
COPY server/package.json server/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY server/tsconfig.json ./
COPY server/src ./src
COPY server/types ./types
RUN npm run build

# Docker Hub copy of the official image: registry.heroiclabs.com answers 429 to CI runners.
FROM heroiclabs/nakama:3.28.0
COPY --from=runtime /src/build/index.js /nakama/data/modules/index.js
COPY fly/start.sh /nakama/start.sh
# A Windows checkout made before .gitattributes may have CRLF endings, which sh refuses.
RUN sed -i 's/\r$//' /nakama/start.sh
ENTRYPOINT ["/bin/sh", "/nakama/start.sh"]
