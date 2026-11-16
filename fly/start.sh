#!/bin/sh
# Starts Nakama on Fly.io (fly.toml): the same flags as docker-compose.prod.yml,
# with secrets from `fly secrets set` and the database from `fly postgres attach`.
set -eu
# Nakama wants user:pass@host:port/db; Fly's DATABASE_URL carries a scheme.
db=${DATABASE_URL#postgres://}
db=${db#postgresql://}
/nakama/nakama migrate up --database.address "$db"
exec /nakama/nakama \
  --name bigbiz \
  --database.address "$db" \
  --runtime.js_entrypoint index.js \
  --runtime.js_read_only_globals=true \
  --socket.server_key "$NAKAMA_SERVER_KEY" \
  --session.encryption_key "$NAKAMA_SESSION_KEY" \
  --session.refresh_encryption_key "$NAKAMA_REFRESH_KEY" \
  --session.token_expiry_sec 7200 \
  --session.refresh_token_expiry_sec 604800 \
  --console.username "$NAKAMA_CONSOLE_USER" \
  --console.password "$NAKAMA_CONSOLE_PASSWORD" \
  --console.signing_key "$NAKAMA_CONSOLE_SIGNING_KEY" \
  --social.apple.bundle_id "${APPLE_BUNDLE_ID:-}" \
  --runtime.http_key "$NAKAMA_HTTP_KEY" \
  --runtime.env "REVENUECAT_API_KEY=${REVENUECAT_API_KEY:-}" \
  --runtime.env "REVENUECAT_WEBHOOK_AUTH=${REVENUECAT_WEBHOOK_AUTH:-}" \
  --runtime.env "FCM_PROJECT_ID=${FCM_PROJECT_ID:-}" \
  --runtime.env "FCM_CLIENT_EMAIL=${FCM_CLIENT_EMAIL:-}" \
  --runtime.env "FCM_PRIVATE_KEY=${FCM_PRIVATE_KEY:-}" \
  --runtime.env "GOOGLE_VISION_API_KEY=${GOOGLE_VISION_API_KEY:-}" \
  --logger.level INFO
