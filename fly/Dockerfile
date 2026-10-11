# Fly.io image: Nakama with the Big Business runtime and the Fly start script.
# Build context is the repo root (fly deploy runs from there, see fly.toml).
FROM heroiclabs/nakama:3.28.0
COPY server/build/index.js /nakama/data/modules/index.js
COPY fly/start.sh /nakama/start.sh
ENTRYPOINT ["/bin/sh", "/nakama/start.sh"]
