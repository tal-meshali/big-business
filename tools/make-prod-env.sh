#!/bin/sh
# Writes .env for docker-compose.prod.yml from .env.example with fresh random
# secrets. Usage: tools/make-prod-env.sh play.example.com > .env
# Store keys (RevenueCat, Firebase, Vision, Apple, Google) stay empty; fill them later.
set -eu
domain=${1:?usage: tools/make-prod-env.sh <domain>}
cd "$(dirname "$0")/.."
awk -v domain="$domain" '
  function hex(   cmd, out) { cmd = "openssl rand -hex 32"; cmd | getline out; close(cmd); return out }
  /^DOMAIN=/ { print "DOMAIN=" domain; next }
  /^NAKAMA_CONSOLE_USER=/ { print "NAKAMA_CONSOLE_USER=ops"; next }
  /^(POSTGRES_PASSWORD|NAKAMA_SERVER_KEY|NAKAMA_SESSION_KEY|NAKAMA_REFRESH_KEY|NAKAMA_CONSOLE_PASSWORD|NAKAMA_CONSOLE_SIGNING_KEY|NAKAMA_HTTP_KEY|REVENUECAT_WEBHOOK_AUTH)=/ {
    split($0, kv, "="); print kv[1] "=" hex(); next }
  { print }
' .env.example
