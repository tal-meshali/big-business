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
| `client/` | Godot 4.6 project: Nakama connection, lobby, table, headless smoke test |

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

Phase 0 complete: decisions, theme, rules spec, engine with tests, match handler, client spike. Next is Phase 1 (playable core) per `docs/research/README.md` section 7.
