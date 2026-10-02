# Deploying the server

One small VPS runs everything until well past 10k monthly players. Steps:

1. **Provision** a 2 vCPU / 4 GB Linux VPS with Docker installed, and point a DNS A record for your domain (for example `play.example.com`) and `console.play.example.com` at it.
2. **Build the runtime** on your machine: `cd server && npm run check`. Commit nothing from `build/`; the Dockerfile copies it at image build time.
3. **Copy** the `server/` folder to the VPS (or clone the repo there and run `npm ci && npm run build`).
4. **Configure**: `cp .env.example .env` and fill every value with long random strings. `NAKAMA_SERVER_KEY` is the key the Godot client uses (set it in `client/scripts/net/net.gd` or the in-app host field later).
5. **Start**: `docker compose -f docker-compose.prod.yml up -d --build`. Caddy obtains TLS certificates automatically. The client connects with scheme `https` on port 443, and the socket uses `wss`.
6. **Verify**: `curl https://play.example.com/` returns Nakama's status. The console is not published; open it through an SSH tunnel (`ssh -N -L 7351:127.0.0.1:7351 user@play.example.com`, then `http://127.0.0.1:7351`).
7. **Update**: rebuild the bundle, then `docker compose -f docker-compose.prod.yml up -d --build nakama`. Matches in progress are terminated on restart; deploy during quiet hours until rolling restarts are set up.

## Social sign-in

Players start as guests: the first launch authenticates with a device id and nothing else. The lobby's Account row then offers "Link Apple" (iOS) and "Link Google" (Android) so the same account comes back after a reinstall or on a new phone; the next launch signs in with that provider first and falls back to the device id. Server-side:

- **Apple**: set `APPLE_BUNDLE_ID` in `.env` to the app's bundle id (the same value as in the iOS export preset). It is passed as `--social.apple.bundle_id`; Nakama refuses Apple sign-in while it is empty. For local Docker Compose use `social.apple.bundle_id` in `server/local.yml`.
- **Google**: Nakama 3.28 verifies Google id tokens against Google's public certificates and needs no server setting. Record the OAuth *web* client id from the Google Cloud console in `.env` (`GOOGLE_CLIENT_ID`) and put it in the Android sign-in plugin config on the client (`client/scripts/net/social_tokens.gd` says which plugin).

The token acquisition itself (the native Sign in with Apple sheet and the Google account picker) needs the platform plugins and store accounts; `docs/TODO-local.md` section E lists that step.

## Shop, push and analytics

All three run without any account: the shop says it "opens soon", no push is sent, and analytics count in Nakama storage from day one. Each piece switches on with `.env` values (passed to the runtime as `--runtime.env`, read through `ctx.env`):

- **Skin shop (RevenueCat)**: in RevenueCat, create the app for both stores, the non-consumable products `bb_skin_back_gilded`, `bb_skin_back_blueprint` and `bb_skin_table_walnut`, and an entitlement `skin_<cosmetic id>` attached to each (`server/src/match/store.ts`). Put the *secret* API key in `REVENUECAT_API_KEY`. The client logs in to RevenueCat with its Nakama user id, buys through the store plugin, then calls `sync_purchases`; the server reads the entitlements back from RevenueCat and keeps them in a server-only `purchases` row. Restore Purchases runs the plugin's restore and the same sync. For refunds and purchases made on another device, add a webhook in RevenueCat: URL `https://<domain>/v2/rpc/revenuecat_webhook?http_key=<NAKAMA_HTTP_KEY>&unwrap`, Authorization header value `REVENUECAT_WEBHOOK_AUTH`. The webhook only triggers a re-read, so a forged event cannot grant anything.
- **"Your turn" push (FCM)**: in the Firebase project, create a service account with the "Firebase Cloud Messaging API Admin" role and download its JSON key. Copy `project_id`, `client_email` and `private_key` (one line, `\n` escapes kept) into `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL` and `FCM_PRIVATE_KEY`. The server sends a push when a turn starts for a player who is away from the match, in untimed games or steps of 30 seconds or more, at most once per `pushCooldownMinutes` per player and match. The client side (plugin, permission prompt, token) is `client/scripts/net/push_tokens.gd`.
- **Remote Config**: switches in Nakama storage (`server/src/match/remote_config.ts`): `shopEnabled`, `pushEnabled`, `pushCooldownMinutes`, `tutorialAutoRoute`, `quickPlayWaitSeconds`, `designerEnabled`, `plusEnabled`. Change them without a release:

  ```
  curl -X POST "https://<domain>/v2/rpc/set_remote_config?http_key=$NAKAMA_HTTP_KEY&unwrap" -d '{"tutorialAutoRoute": true}'
  ```

  Unknown keys are dropped and numbers clamped; the answer is the whole config. Players read it with `get_remote_config` on every sign-in.
- **Analytics (D1 / D7 and the funnel)**: counted per install day, nothing personal and nothing sent to a third party (decision D4). Read the last two weeks with:

  ```
  curl -X POST "https://<domain>/v2/rpc/analytics_report?http_key=$NAKAMA_HTTP_KEY&unwrap" -d '{"days": 14}'
  ```

  Each row has `installs`, `d1` and `d7` (active on exactly day 1 / day 7, UTC days) with their rates, and the funnel steps `tutorial`, `firstGame`, `peopleGame` (a game with another person) and `purchase`. A day's D7 is final a week after it. Crashlytics needs the Firebase SDK on a device and is a local task.

## Designer (custom card art)

The Designer unlock (decision D5, `server/src/match/designer.ts`) runs with no extra account: uploads wait in a moderation queue until the operator approves them.

- **Store**: a non-consumable product `bb_designer` in both stores, attached in RevenueCat to an entitlement `designer`. It is read with the skins (same `sync_purchases`, webhook and Restore Purchases).
- **Automated scan (optional)**: enable the Cloud Vision API in a Google Cloud project, create an API key restricted to it, and put it in `GOOGLE_VISION_API_KEY`. Clean pictures then go live at once, clear adult or violent ones are refused, and uncertain ones wait in the queue. Without the key every new picture waits for a person.
- **Moderation queue**: the operator reads it and decides with two server-to-server RPCs. The queue holds pictures not yet reviewed and reported ones (three reports hide a picture until it is reviewed again). Each item carries the base64 WebP in `data`:

  ```
  curl -X POST "https://<domain>/v2/rpc/moderation_queue?http_key=$NAKAMA_HTTP_KEY&unwrap" -d '{"limit": 20}'
  curl -X POST "https://<domain>/v2/rpc/moderate_card_art?http_key=$NAKAMA_HTTP_KEY&unwrap" -d '{"hash": "<hash>", "verdict": "approve"}'
  curl -X POST "https://<domain>/v2/rpc/moderate_card_art?http_key=$NAKAMA_HTTP_KEY&unwrap" -d '{"hash": "<hash>", "verdict": "reject", "note": "DMCA notice 2026-10-02"}'
  ```

  A refusal deletes the picture, shows the standard card wherever it was used, and gives the uploader a strike (pass `"strike": false` for an honest mistake). Three strikes stop that account's uploads for good (repeat-infringer policy). Apple and Google expect reports handled within a day; check the queue daily once Designer is on sale.
- **Kill switch**: Remote Config `designerEnabled: false` stops uploads and custom decks in rooms without touching anyone's decks.
- **Plus (decision D11)**: an auto-renewing subscription `bb_plus_monthly` attached in RevenueCat to an entitlement `plus`. It reaches the server through the same sync and webhook (an `EXPIRATION` event triggers a re-read; an expiry date passing ends it even without one). The shop lists it only while Remote Config `plusEnabled` is true, which it is not by default.

Backups: `docker exec <postgres container> pg_dump -U postgres nakama > backup.sql` on a cron job. Nakama's data is small at this stage.

## Security checklist

What the code and compose files already do, and what only the operator can do. Tick every item before the first public build.

Done by the repository (verify, do not repeat):

- Every RPC validates its payload (`server/src/match/input.ts`) and returns short errors; internal failures are logged and reported as `internal error`.
- Storage: `profile` and `purchases` rows are server-owned (clients read their own, write nothing); `designer` (decks), `standing` (age bracket and strikes) and `stats` are server-owned the same way; `rooms`, `reports`, `ratelimit`, `analytics`, `analytics_cohort`, `config`, `push`, `card_art` and `art_queue` are unreadable by clients; before-hooks refuse every client write or delete in all of them. The season leaderboard is authoritative.
- Server-to-server RPCs (`set_remote_config`, `analytics_report`, `revenuecat_webhook`, `moderation_queue`, `moderate_card_art`) refuse any player session; they need the runtime http_key, and the webhook also its Authorization secret. Store entitlements are read from RevenueCat by the server, never taken from the client.
- Private rooms: joining needs the room code, and match labels never carry it, so listing matches does not reveal a way in.
- Per-user rate limits (`server/src/match/ratelimit.ts`): find_player 20/min, invite_friend 10/min, report_player 5/min, create_room 6/min, quick_play 12/min, sync_purchases 6/min, register_push_token 6/min, set_age_bracket 6/min, upload_card_art 10/min, get_card_art 30/min, report_card_art 5/min, and friend requests 20 players/min through a before-hook. Reports are one row per (day, reporter, reported) with a count and the first 10 reports' details, so the collection cannot be grown by a single account.
- Invite notifications carry the sender's server-side username (32 characters at most), never a client-supplied string.
- The match handler drops oversized or malformed messages before parsing them and never lets a client message throw.
- Production sessions last 2 hours with a 7 day refresh token (the defaults are 60 seconds and 1 hour, which the client does not refresh yet).
- `runtime.js_read_only_globals` stays on; `socket.max_message_size_bytes` stays at Nakama's default (4 KB) in production.

Operator actions:

- [ ] `.env`: every value replaced (`openssl rand -hex 32` for the keys). `NAKAMA_HTTP_KEY` and `REVENUECAT_WEBHOOK_AUTH` are secrets: anyone with the http key can change Remote Config and read the analytics report. `NAKAMA_SERVER_KEY` is embedded in the client and is not a secret, but must not be `defaultkey`; `NAKAMA_SESSION_KEY` and `NAKAMA_REFRESH_KEY` are secrets; rotating them logs every player out.
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
