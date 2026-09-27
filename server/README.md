# Big Business server

Nakama runtime for the authoritative game. Two layers:

- `src/engine/`: the pure rules engine. No Nakama imports, no clock, no global randomness. Fully covered by `game.test.ts`. This is the reference implementation of `docs/design/rules-spec.md`.
- `src/match/`: the Nakama match handler (lobby, seats, bots, timers, per-seat views, reconnection) and the wire protocol.
- `src/main.ts`: registers the match handler and three RPCs: `quick_play`, `create_room`, `join_room`.

## Commands

```
npm install
npm run check        # typecheck + tests + bundle
npm test             # engine tests only
npm run build        # bundles src/main.ts to build/index.js for Nakama
docker compose up    # Postgres + Nakama 3.28 with build/ mounted as the module dir
```

Nakama console: http://127.0.0.1:7351 (admin / password). API on port 7350 with server key `defaultkey`. All keys in `local.yml` are development values.

## Wire protocol

Payloads are JSON strings.

| Direction | Opcode | Payload |
|---|---|---|
| client -> server | 1 `OP_ACTION` | `{"type":"take_supply"}` / `{"type":"take_market","cardId":n}` / `{"type":"play_portfolio","cardId":n}` / `{"type":"play_market","cardId":n}` |
| client -> server | 2 `OP_READY` | empty; marks the sender ready in a private lobby |
| server -> client | 10 `OP_VIEW` | `PlayerView` for that seat (see `src/engine/types.ts`), sent after every accepted action, join and leave |
| server -> client | 11 `OP_EVENTS` | `{seq, events: GameEvent[]}` for animations |
| server -> client | 12 `OP_LOBBY` | `LobbyMessage` while waiting to start |
| server -> client | 13 `OP_ERROR` | `{message, action?}` |

## Match lifecycle

1. `quick_play` RPC returns an open public match id (or creates one). Public lobbies start when full (5 seats) or 20 seconds after the first player joins, filling empty seats with bots to reach 3.
2. `create_room` RPC returns a 6-character code and a private match id; `join_room` resolves a code. Private rooms start when everyone has sent `OP_READY` and there are at least 2 humans (a bot fills the third seat).
3. During play the server applies bot moves after a short delay and auto-moves a human seat when its deadline passes. Three consecutive timeouts convert a seat to a bot; rejoining reclaims it.
4. Reconnection: a user whose seat exists may rejoin the match and receives a fresh view. The action log is kept in match state for a future replay feature.
5. The match ends 45 seconds after the game ends or when everyone leaves.

## Runtime constraints

Nakama runs JavaScript in goja, so the bundle targets ES2016 and the engine avoids `structuredClone`, `Array.prototype.flat`, `Object.fromEntries` and `at()`. Type definitions are vendored in `types/nakama-runtime/` from heroiclabs/nakama-common (see `VERSION`).
