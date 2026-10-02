# Big Business

A mobile multiplayer card game for all ages. Collect shares in six companies, pay to draw, take from the Market, and cash in on dividend day. Quick play against anyone or private rooms with a code. A premium unlock lets you design your own cards.

The mechanics are a re-themed implementation of a well-known share-collecting card game; see `docs/decisions.md` for the IP position.

## Layout

| Path | What it is |
| --- | --- |
| `docs/research/` | Research that preceded the project: the source game, card-game UX, engagement and monetization, tech stack, custom card upload |
| `docs/decisions.md` | Decision record: name, engine, backend, audience, premium model |
| `docs/design/theme.md` | The six companies, vocabulary, card layout, table look |
| `docs/design/rules-spec.md` | Authoritative rules, including every ruling the engine implements |
| `server/` | Nakama runtime: pure TypeScript rules engine with tests, authoritative match handler, room-code RPCs, Docker Compose for local play |
| `client/` | Godot 4.6 project: Nakama connection, lobby, table, help screen, synthesised sounds, headless smoke, screenshot and end-to-end tests |
| `web/` | Browser table against bots (the page behind the shared web demo): the real engine and bots bundled in by `node web/build.mjs` |
| `docs/deploy.md` | Single-VPS deployment with Docker Compose and automatic TLS |
| `docs/conventions.md` | Dependency-graph rules enforced by `tools/graph_check.py` (pre-push hook and CI) |
| `docs/TODO-local.md` | Work that needs a local machine: phone builds, playtests, store accounts, art |

## Run it locally

Server (needs Node 22 and Docker):

```
cd server
npm install
npm run check          # typecheck, engine tests, bundle
docker compose up      # Nakama on 127.0.0.1:7350, console on :7351
```

Client (needs Godot 4.6): open `client/` in the editor and press Play, or run headless checks:

```
godot --headless --path client --import
godot --headless --path client --script res://tests/smoke.gd
```

In the app, keep the server as `127.0.0.1` (or type `https://your.domain` for a deployed server), press Connect, then Play now. Open two or more instances to fill a table, or let bots fill the empty seats after the lobby wait.

## Status

Phase 0 complete: decisions, theme, rules spec, engine with tests, match handler, client spike.

Tutorial: "How to play" in the lobby starts a solo game against two slow bots with no timer and a coach overlay that explains each rule as it first matters. Covered by the smoke test, a headless end-to-end run, and CI.

Phase 1 (playable core), cloud-doable parts complete: live end-to-end tests against Nakama (Node client and the real Godot client), a designed portrait table with seat oval, hand fan, contextual actions, event animations and a dividend-day sequence, production deployment files, and CI that runs the whole stack. Placeholder renders are in `docs/screenshots/`.

Phase 2 (soft-launch features), cloud-doable parts complete: preset emotes and phrases with mute, report and block (no free-text chat: all-ages decision), XP and levels awarded at game end, a daily bonus with a streak, a monthly season leaderboard for games with other people, and automatic reconnect with seat rejoin. The look is a title-deed theme on a board-green table.

Phase 2 polish, cloud-doable parts: a heuristic bot for real games that clearly beats the old placeholder policy (rules-spec section 8.2), a rules and help screen (lobby and "?" at the table) with support and privacy links, tutorial v2 (the first two turns only allow the coached move), a bundled emoji font so emotes render on every phone, mutes and blocks that survive restarts, 48 px touch targets enforced by the smoke test, a 4-card hand that stays on screen, placeholder sounds and haptics, a red timer glow under five seconds, reconnect on app resume, and a server field that accepts `https://` addresses.

First playtest fixes: bots keep shares at a steady pace instead of cycling the Market, a get-ready countdown with the turn order before the first turn (the table also no longer misses the game's first view), a Forfeit button that hands your seat to a bot, and press-and-hold on any card for a close-up.

Second playtest fixes: bots lock pairs into their Portfolio, so they keep about half their plays from their first or second turn (tutorial bots too, once the Market has a share). The browser table (`web/`) gets the same engine plus the countdown, Forfeit, the card close-up, a selected card drawn above its neighbours, and no replayed arrival animation when you select or cancel a card. It now opens in a lobby: resume or forfeit the saved game, set up and deal a table, start the tutorial, open the rules, and see your record in that browser (games, wins, best capital). Every game ends back there.

Bot tuning from simulation: at 3 and 4 seats, where bots actually play, they model opponents' remaining pickups more tightly. With one person at a 3-seat table the simple stand-in for that person wins 19% of games instead of 28%, and the bots keep more of their plays than before (rules-spec section 8.2).

Phase 2 social and accounts, ported onto this line: a friends list with room invites (add by exact username, accept, remove; invite a mutual friend to a private room through a Nakama in-app notification), three daily and two weekly quests feeding a free cosmetic track (card backs and table felts, nothing sold), and Sign in with Apple and Google linking for guest accounts (the server side and lobby row are done; the native token plugins need a real machine, `docs/deploy.md` "Social sign-in"). A server security review validates every RPC payload and match message, keeps profile, room, report and rate-limit storage server-owned, and rate-limits lookups, invites, reports, room creation and friend requests (`docs/deploy.md` "Security checklist").

Phase 2 shop, analytics and push, server and client code: three curated skins (two card backs and a table felt) sold a la carte through RevenueCat with entitlements checked on the server, a Shop overlay in the lobby with Buy, Use and Restore purchases, D1 / D7 retention and a first-session funnel counted per install day in Nakama storage, Remote Config switches (shop, push, tutorial auto-routing, quick-play wait) the operator changes without a release, and a "your turn" push sender over FCM with device-token registration. The store and Firebase plugins, accounts and keys are local steps (`docs/TODO-local.md` G, `docs/deploy.md` "Shop, push and analytics").

Phase 3 Designer unlock, server and client code: a one-time unlock for custom card art in private rooms (decision D10). Three deck slots, each with a card back and an art window per company; pictures are framed on the phone, checked by the server, scanned or queued for review, and only approved art reaches other players. An operator moderation queue with strikes, report and block that cover custom cards, and an age gate. The store product, the optional scan key and the DMCA agent are local steps (`docs/TODO-local.md` G, `docs/deploy.md` "Designer").

Phase 3 Plus, built and switched off (decision D11): a monthly subscription with ten Designer decks, the deck in quick play for players who opt in, a Plus skin each month, full lifetime stats, and the host's card back and felt on every seat of their private rooms. The operator turns it on with Remote Config `plusEnabled`.

Code conventions (acyclic, layered dependency graph checked with graphify on every push and in CI) are in `docs/conventions.md`.

What still needs a real machine (phone builds, playtesting, store accounts, art) is listed in `docs/TODO-local.md`.
