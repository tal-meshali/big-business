# Deploying the server

One small VPS runs everything until well past 10k monthly players. Steps:

1. **Provision** a 2 vCPU / 4 GB Linux VPS with Docker installed, and point a DNS A record for your domain (for example `play.example.com`) and `console.play.example.com` at it.
2. **Build the runtime** on your machine: `cd server && npm run check`. Commit nothing from `build/`; the Dockerfile copies it at image build time.
3. **Copy** the `server/` folder to the VPS (or clone the repo there and run `npm ci && npm run build`).
4. **Configure**: `cp .env.example .env` and fill every value with long random strings. `NAKAMA_SERVER_KEY` is the key the Godot client uses (set it in `client/scripts/net/net.gd` or the in-app host field later).
5. **Start**: `docker compose -f docker-compose.prod.yml up -d --build`. Caddy obtains TLS certificates automatically. The client connects with scheme `https` on port 443, and the socket uses `wss`.
6. **Verify**: `curl https://play.example.com/` returns Nakama's status. The console is not published; open it through an SSH tunnel (`ssh -N -L 7351:127.0.0.1:7351 user@play.example.com`, then `http://127.0.0.1:7351`).
7. **Update**: rebuild the bundle, then `docker compose -f docker-compose.prod.yml up -d --build nakama`. Matches in progress are terminated on restart; deploy during quiet hours until rolling restarts are set up.

Backups: `docker exec <postgres container> pg_dump -U postgres nakama > backup.sql` on a cron job. Nakama's data is small at this stage.

## Security checklist

What the code and compose files already do, and what only the operator can do. Tick every item before the first public build.

Done by the repository (verify, do not repeat):

- Every RPC validates its payload (`server/src/match/input.ts`) and returns short errors; internal failures are logged and reported as `internal error`.
- Storage: `profile` rows are server-owned (clients read their own, write nothing; a row a client created itself is ignored), `rooms` and `reports` and `ratelimit` are unreadable by clients, the season leaderboard is authoritative.
- Per-user rate limits (`server/src/match/ratelimit.ts`): find_player 20/min, invite_friend 10/min, report_player 5/min, create_room 6/min, and friend requests 20/min through a before-hook. Reports are one row per (day, reporter, reported) with a count, so the collection cannot be grown by a single account.
- Invite notifications carry the sender's server-side username (32 characters at most), never a client-supplied string.
- The match handler drops oversized or malformed messages before parsing them and never lets a client message throw.
- Production sessions last 2 hours with a 7 day refresh token (the defaults are 60 seconds and 1 hour, which the client does not refresh yet).
- `runtime.js_read_only_globals` stays on; `socket.max_message_size_bytes` stays at Nakama's default (4 KB) in production.

Operator actions:

- [ ] `.env`: every value replaced (`openssl rand -hex 32` for the keys). `NAKAMA_SERVER_KEY` is embedded in the client and is not a secret, but must not be `defaultkey`; `NAKAMA_SESSION_KEY` and `NAKAMA_REFRESH_KEY` are secrets; rotating them logs every player out.
- [ ] Console: only reachable over the SSH tunnel (the compose file binds it to `127.0.0.1:7351`). Confirm from outside: `curl -m 5 https://console.play.example.com` must fail and port 7351 must be closed on the VPS firewall. Use a long console password; the console has no lockout. The `console.` DNS record from step 1 is only needed if you enable the commented allow-list block in `Caddyfile`.
- [ ] Firewall: only 22, 80 and 443 open. Postgres is not published (verify with `ss -ltn` on the VPS).
- [ ] SSH: key-only login, no root password.
- [ ] Backups: the `pg_dump` cron job runs and a restore was tested once. Reports contain user ids and free-text notes (200 characters, from the reporter): treat backups as personal data.
- [ ] Moderation: someone reads the `reports` collection (console, Storage, collection `reports`, user `00000000-0000-0000-0000-000000000000`) at least weekly, and the support address in the Help screen is monitored (store policies for an all-ages app).
- [ ] Friend requests: Nakama refuses requests to users who blocked the sender and the client offers block and report on every player; there is no server-side word filter on usernames, so name reports (`reason: name`) must be handled by hand.
- [ ] Console users: create a personal read-only console account per moderator instead of sharing the admin login (Console, Settings, Users).
- [ ] Optional hardening: `--session.single_match true` prevents one account sitting in two matches, and `--socket.max_request_size_bytes` can stay at its 4 KB default; both are safe with this client.
- [ ] After each Nakama upgrade, re-check this list: config keys move between versions.

Cost reference: see `docs/research/04-tech-stack-multiplayer.md` section 6.
