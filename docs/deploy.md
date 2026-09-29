# Deploying the server

One small VPS runs everything until well past 10k monthly players. Steps:

1. **Provision** a 2 vCPU / 4 GB Linux VPS with Docker installed, and point a DNS A record for your domain (for example `play.example.com`) and `console.play.example.com` at it.
2. **Build the runtime** on your machine: `cd server && npm run check`. Commit nothing from `build/`; the Dockerfile copies it at image build time.
3. **Copy** the `server/` folder to the VPS (or clone the repo there and run `npm ci && npm run build`).
4. **Configure**: `cp .env.example .env` and fill every value with long random strings. `NAKAMA_SERVER_KEY` is the key the Godot client uses (set it in `client/scripts/net/net.gd` or the in-app host field later).
5. **Start**: `docker compose -f docker-compose.prod.yml up -d --build`. Caddy obtains TLS certificates automatically. The client connects with scheme `https` on port 443, and the socket uses `wss`.
6. **Verify**: `curl https://play.example.com/` returns Nakama's status, and the console is at `https://console.play.example.com` (protect it with a firewall or Caddy basic auth before sharing the address).
7. **Update**: rebuild the bundle, then `docker compose -f docker-compose.prod.yml up -d --build nakama`. Matches in progress are terminated on restart; deploy during quiet hours until rolling restarts are set up.

## Social sign-in

Players start as guests: the first launch authenticates with a device id and nothing else. The lobby's Account row then offers "Link Apple" (iOS) and "Link Google" (Android) so the same account comes back after a reinstall or on a new phone; the next launch signs in with that provider first and falls back to the device id. Server-side:

- **Apple**: set `APPLE_BUNDLE_ID` in `.env` to the app's bundle id (the same value as in the iOS export preset). It is passed as `--social.apple.bundle_id`; Nakama refuses Apple sign-in while it is empty. For local Docker Compose use `social.apple.bundle_id` in `server/local.yml`.
- **Google**: Nakama 3.28 verifies Google id tokens against Google's public certificates and needs no server setting. Record the OAuth *web* client id from the Google Cloud console in `.env` (`GOOGLE_CLIENT_ID`) and put it in the Android sign-in plugin config on the client (`client/scripts/net/social_tokens.gd` says which plugin).

The token acquisition itself (the native Sign in with Apple sheet and the Google account picker) needs the platform plugins and store accounts; `docs/TODO-local.md` section E lists that step.

Backups: `docker exec <postgres container> pg_dump -U postgres nakama > backup.sql` on a cron job. Nakama's data is small at this stage.

Cost reference: see `docs/research/04-tech-stack-multiplayer.md` section 6.
