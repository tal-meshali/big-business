# Server and phones: what is done, what needs you

Status on 2026-10-09. The detailed guides are `docs/deploy.md` (server) and `docs/TODO-local.md` (phones, stores).

## Done on this Mac

- The production stack (`docker-compose.prod.yml`) was broken in two ways, both fixed and verified locally with TLS:
  - Nakama stopped reading flags after `--runtime.js_read_only_globals true`, so the server key, session keys, console login, http key and every store key were ignored. A deployed server would have accepted `defaultkey` and `defaulthttpkey`, which means anyone could change Remote Config and read analytics.
  - The root `Dockerfile` copied a file that does not exist from a clone.
- `tools/make-prod-env.sh <domain> > .env` writes the server's `.env` with fresh secrets. A new CI job starts the production stack and fails if any default key is in use.
- Phone builds can carry the deployed server: fill `SERVER_ADDRESS` and `SERVER_KEY` in `client/scripts/game/app_info.gd` and the lobby starts there.
- `client/export_presets.cfg` has Android and iOS presets with the bundle id `com.talmeshali.bigbusiness` (a placeholder until you pick one, see below).
- Java 17, the Android SDK and the Godot 4.6.3 export templates are being installed.

## Needs you: the server

1. **Pick a VPS.** Recommended: Hetzner Cloud, its smallest 2 vCPU / 4 GB shared plan (a few euros a month), which matches the size in `docs/deploy.md`. DigitalOcean or any Ubuntu VPS with Docker works too.
2. **A domain.** Either one you own, or a cheap new one. Add an A record `play.<domain>` pointing at the VPS address.
3. **An SSH key.** This Mac has none yet. Run `ssh-keygen -t ed25519` and paste `~/.ssh/id_ed25519.pub` into the VPS provider when creating the server.
4. **Tell me the VPS address and the domain.** I will then, with your go-ahead, clone the repo there, generate `.env`, start the stack, lock the firewall to ports 22, 80 and 443, set up the nightly backup, and put the address and key into `app_info.gd`. Keep a copy of `.env` in your password manager.

## Needs you: phones

1. **Bundle id.** Pick the permanent id, for example `com.talmeshali.bigbusiness` (already in the presets). It cannot change after the first store upload.
2. **Android phone.** Settings, About phone, tap Build number seven times, then Developer options, USB debugging on. Plug it into the Mac and accept the prompt. A debug build needs no Google account.
3. **iPhone.** Install Xcode from the App Store (it needs your Apple ID and is a large download). A free Apple ID can install to your own iPhone for 7 days at a time; TestFlight and the store need the Apple Developer Program (99 USD a year). Put your Team ID in the iOS preset (`application/app_store_team_id`).
4. **Support email and privacy policy URL** in `client/scripts/game/app_info.gd` (both stores require them).

## Later, before a public build

- Google Play Console (25 USD once) and the Apple Developer Program.
- RevenueCat, Firebase (push) and the Godot plugins for Apple and Google sign-in, purchases and push. These stay stubs until the accounts exist (`docs/TODO-local.md` E and G).
- The operator half of the security checklist in `docs/deploy.md`.
