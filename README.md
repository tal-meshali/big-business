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
| `client/` | Godot 4.6 project: Nakama connection, lobby (profile, quests, friends, help), table, tutorial coach, headless smoke, screenshot and end-to-end tests |
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

In the app, keep the host as `127.0.0.1`, press Connect, then Play now. Open two or more instances to fill a table, or let bots fill the empty seats after the lobby wait.

## Status

Phase 0 complete: decisions, theme, rules spec, engine with tests, match handler, client spike.

Tutorial: "How to play" in the lobby starts a solo game against two slow bots with no timer and a coach overlay that explains each rule as it first matters. Covered by the smoke test, a headless end-to-end run, and CI.

Phase 1 (playable core), cloud-doable parts complete: live end-to-end tests against Nakama (Node client and the real Godot client), a designed portrait table with seat oval, hand fan, contextual actions, event animations and a dividend-day sequence, production deployment files, and CI that runs the whole stack. Placeholder renders are in `docs/screenshots/`.

Phase 2 (soft-launch features), cloud-doable parts complete: preset emotes and phrases with mute, report and block (no free-text chat: all-ages decision), XP and levels awarded at game end, a daily bonus with a streak, a monthly season leaderboard for games with other people, and automatic reconnect with seat rejoin. The look is a title-deed theme on a board-green table.

Visual redesign (2026-09-28) from the "3D table" design canvas: the table is drawn in perspective (tilted felt with the supply, Market, Portfolio and opponents' hands on it, your hand held upright in front), deed-style buttons and plates with hard shadows, the Archivo / Nunito Sans type pair, a start page with a floating card fan, and a tutorial coach that spotlights what it explains. Renders of every screen are in `docs/screenshots/`.

Phase 2 follow-ups, cloud-doable parts complete: the tutorial guides the first two turns (only the coached action is enabled) and a Help screen holds a replayable rules reference plus support and privacy links; the first "Play now" routes new players into the tutorial; friends list and private-room invites (Nakama notifications); daily and weekly quests feeding a free cosmetic track (card backs and table felts); a placeholder sound set synthesized in code, a timer glow under 5 seconds and haptics; drawn emote icons instead of emoji; the lobby host field accepts https URLs; and a heuristic bot with one-ply lookahead for public games (the tutorial and timeouts keep the simple auto-move).

Code conventions (acyclic, layered dependency graph checked with graphify on every push and in CI) are in `docs/conventions.md`.

What still needs a real machine (phone builds, playtesting, store accounts, art) is listed in `docs/TODO-local.md`.
