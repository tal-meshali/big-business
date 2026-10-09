# Production image: Nakama with the Big Business runtime baked in.
# Build:  (cd server && npm run build) && docker build -t big-business-server .
# Run:    see docs/deploy.md
FROM registry.heroiclabs.com/heroiclabs/nakama:3.28.0
COPY server/build/index.js /nakama/data/modules/index.js
