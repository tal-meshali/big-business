# Running the server on a home Windows PC

The game server (Postgres + Nakama) can run on a Windows PC instead of Fly.io. Docker Desktop runs the same Nakama version and start script as Fly (`fly/start.sh`), with the server code built from source, and Tailscale Funnel gives the PC a fixed public address, `https://<pc-name>.<tailnet>.ts.net`, with a real certificate. Phones reach it from anywhere. You don't need a domain, router port forwarding or a fixed IP address.

Files: `home/docker-compose.yml`, `home/Dockerfile` (builds the server runtime inside Docker, so the PC needs no Node), and the PowerShell scripts in `home/`. Secrets live in `.env.home` at the repo root (git-ignored).

## Set up (once)

From the repo folder, in PowerShell:

```
powershell -ExecutionPolicy Bypass -File home\setup.ps1
```

The script is safe to run again, and every step skips what is already done. It:

1. Installs Git, Docker Desktop and Tailscale with winget if they are missing. A freshly installed Docker Desktop usually needs one restart (it turns on WSL 2). The script says so and stops; run it again after signing back in.
2. Starts Docker Desktop and waits for the engine.
3. Writes `.env.home` with fresh random secrets (and refuses to if the database already exists without it, since the database keeps its first password). The client key is copied from `client/scripts/game/app_info.gd`, so the app needs only a new address. Keep a copy of `.env.home` in a password manager.
4. Builds and starts the stack, waits for `http://127.0.0.1:7350/healthcheck`, and fails if Nakama logs `insecure default`.
5. Turns off sleep and hibernate while plugged in, and makes Docker Desktop start at sign-in. Both containers restart with Docker.
6. Signs in to Tailscale if needed (open the link it prints, or use the tray icon) and runs `tailscale funnel --bg 7350`. The first time, Tailscale prints a link to allow Funnel for the tailnet; open it and the script carries on. The PC itself reaches the address over the tailnet, so confirm Funnel from a phone on mobile data: `https://<address>/healthcheck` shows `{}`.
7. Registers the scheduled task "Big Business server backup" (daily 04:00, see below).
8. Writes the public address into `client/scripts/game/app_info.gd` (`-NoClientUpdate` skips this). Commit that change and make a new phone build. Builds made before it still point at Fly. A new build moves every player to the new default unless they typed their own server under the current default (`Net._load_settings`).

## Everyday operation

- **Update the server**: `home\update.ps1` (git pull, rebuild, restart, health check). Games in progress end on restart, so run it at a quiet time.
- **Console**: http://127.0.0.1:7351 on the PC, user `ops`, password `NAKAMA_CONSOLE_PASSWORD` in `.env.home`. It is not published to the internet.
- **Logs**: `docker compose -f home/docker-compose.yml logs -f nakama`.
- **Server-to-server RPCs** (Remote Config, analytics, moderation in `docs/deploy.md`): use the public address with `NAKAMA_HTTP_KEY` from `.env.home`, or `http://127.0.0.1:7350` on the PC.
- **Player feedback** (More > Send feedback, decision D29): `home\feedback.ps1` prints the newest 20 messages (`-Limit 50` for more); `home\feedback.ps1 -Done <key>, <key>` clears handled ones. They are also in the console under Storage, collection `feedback`.
- **Backups**: `home\backup.ps1` writes `home\backups\nakama-<date>.dump` and keeps the newest 14. Each run is logged in `home\backups\backup.log`. Copy one off the PC now and then. The dumps hold player data, so keep them private. Restore with `home\restore.ps1 -File <dump>`, which backs up the current database first.

## Moving players over from Fly

`home\import-fly-data.ps1` copies the Fly database (accounts, friends, stats, clubs, purchases) into the home server. It installs flyctl and asks you to sign in if needed, reads the database address from the Fly app, dumps the database through `fly proxy`, and restores the dump with `restore.ps1`. Run it right before switching the app over, because anything played on Fly afterwards is not copied. Session keys are new, so phones sign in again by themselves, as the same accounts.

Switch-over order:

1. `home\setup.ps1`, and check the public address answers.
2. Optional: `home\import-fly-data.ps1`.
3. Commit the new `app_info.gd` address, make new builds, and install them.
4. Only once the PC server works: stop Fly with `fly scale count 0 -a big-business-server` (it can be brought back with `fly scale count 1`). Delete the Fly apps (`fly apps destroy big-business-server`, `fly apps destroy big-business-db`) later, once you are sure. This removes the Fly database for good.

## What to expect from a home server

- **The PC must stay on, signed in and online.** Docker Desktop starts only after a Windows sign-in, so after a Windows Update restart the server is down until someone signs in. To avoid this, turn on automatic sign-in for this account (Windows "netplwiz"), or set Windows Update active hours.
- A restart of the PC or of Docker ends games in progress. Accounts and progress are in Postgres and are kept.
- Players' traffic goes through Tailscale's Funnel relays. That suits a card game, but Funnel has bandwidth limits meant for personal use. Once you have real traffic, a VPS (`docker-compose.prod.yml`, `docs/deploy.md`) is the next step.
- The `.ts.net` name contains the PC's name and the tailnet's name, and the store review team sees it in network traffic. Rename the PC in the Tailscale admin console before the first public build if needed. A rename changes the address, so the client then needs the new one.
