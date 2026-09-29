# Big Business server

Nakama runtime for the authoritative game. Two layers:

- `src/engine/`: the pure rules engine. No Nakama imports, no clock, no global randomness. Fully covered by `game.test.ts`. This is the reference implementation of `docs/design/rules-spec.md`. `bot.ts` is the heuristic bot policy (one-ply lookahead over the engine, covered by `bot.test.ts` including a tournament against the simple auto-move); `autoAction` in `game.ts` stays the deterministic auto-move for timeouts and tutorial bots.
- `src/match/`: the Nakama match handler (lobby, seats, bots, timers, per-seat views, reconnection) and the wire protocol.
- `src/main.ts`: registers the match handler and the RPCs listed below.

## Commands

```
npm install
npm run check        # typecheck + tests + bundle
npm test             # engine tests only
npm run build        # bundles src/main.ts to build/index.js for Nakama
docker compose up    # Postgres + Nakama 3.28 with build/ mounted as the module dir
```

Nakama console: http://127.0.0.1:7351 (admin / password). API on port 7350 with server key `defaultkey`. All keys in `local.yml` are development values.

## End-to-end tests

With Nakama running (Docker Compose, or a local binary against Postgres):

```
node e2e/play.mjs                       # Node client: private room + quick play, ~2 minutes
godot --headless --path ../client --script res://tests/e2e_client.gd   # real Godot client vs bots
```

`e2e/play.mjs` verifies room codes, ready gating, hidden information, illegal-action rejection, timeout auto-move, leave and rejoin, coin conservation on every state, dividend day, friend requests with room invites delivered as notifications (and refused for strangers), and quick play filling with bots after the lobby wait. Both scripts exit non-zero on failure.

## Production

`Dockerfile` bakes `build/index.js` into the official Nakama image. `docker-compose.prod.yml` plus `Caddyfile` run Postgres, Nakama and automatic TLS on one VPS; see `docs/deploy.md`.

## Wire protocol

Payloads are JSON strings.

| Direction | Opcode | Payload |
|---|---|---|
| client -> server | 1 `OP_ACTION` | `{"type":"take_supply"}` / `{"type":"take_market","cardId":n}` / `{"type":"play_portfolio","cardId":n}` / `{"type":"play_market","cardId":n}` |
| client -> server | 2 `OP_READY` | empty; marks the sender ready in a private lobby |
| client -> server | 3 `OP_EMOTE` | `{"emote":"<id>"}` from `EMOTE_IDS`; 2 s cooldown per player, unknown ids dropped |
| server -> client | 10 `OP_VIEW` | `PlayerView` for that seat (see `src/engine/types.ts`), sent after every accepted action, join and leave |
| server -> client | 11 `OP_EVENTS` | `{seq, events: GameEvent[]}` for animations |
| server -> client | 12 `OP_LOBBY` | `LobbyMessage` while waiting to start |
| server -> client | 13 `OP_ERROR` | `{message, action?}` |
| server -> client | 14 `OP_EMOTE_SHOWN` | `{seat, emote}` relayed to everyone at the table |

## RPCs

| RPC | Payload | Returns |
|---|---|---|
| `quick_play` | `{}` or `{"tutorial": true}` | `{matchId}` (open public lobby or a new one; tutorial match when asked) |
| `create_room` | `{stepSeconds?, maxSeats?}` | `{code, matchId}` |
| `join_room` | `{code}` | `{code, matchId}` |
| `get_profile` | `{}` | `{progress: {xp, level, gamesPlayed, wins, streak, lastDailyClaim, bestRank, trackPoints, quests, equipped}, dailyAvailable, quests: {daily: [...], weekly: [...]}, trackPoints, unlocked, equipped: {cardBack, table}, track: [{points, cosmeticId}]}`; each quest row is `{id, text, target, points, progress, claimable, claimed}` |
| `claim_daily` | `{}` | `{claimed, xpAwarded, progress}`; once per UTC day, streak grows on consecutive days |
| `claim_quest` | `{id}` | `{ok, trackPoints, unlocked}`; adds a completed quest's points to the free cosmetic track, once |
| `equip_cosmetic` | `{slot, id}` | `{ok, equipped}`; `slot` is `cardBack` or `table`, `id` must be unlocked |
| `report_player` | `{userId, reason, matchId?, note?}` | `{ok}`; written to the `reports` storage collection (system user, console-only) |
| `find_player` | `{name}` | `{userId, username}`; exact username match, never the caller; error `not found` otherwise |
| `invite_friend` | `{userId, code}` | `{ok}`; caller and target must be mutual friends (Nakama friend state 0), the target must not have blocked the caller, and the code must be a live room. Sends a persistent in-app notification, code 100 (`INVITE_CODE`), subject `Room invite`, content `{code, fromName, fromUserId}` |
| `account_links` | `{}` | `{apple, google, device, username}`; which sign-in methods the caller's account has (from `accountGetId`), so the lobby can show link state without parsing the raw account. Linking and unlinking Apple / Google use Nakama's own link API from the client; see `docs/deploy.md` "Social sign-in" |

Progression (`src/match/progression.ts`, pure and unit-tested) is applied by the match handler once when a game ends: XP for participation, placement and wins (halved for games against bots only), and season points on the `season` leaderboard (monthly reset, only for games with at least two humans). Adding, accepting, removing and blocking friends use Nakama's friends API from the client; the social RPCs (`src/match/social.ts`, invite rules unit-tested) only look players up and deliver room invites as Nakama in-app notifications (no push).

Quests (`src/match/quests.ts`): three daily quests picked deterministically from the UTC date and two weekly ones from the ISO week (seeded, so every player sees the same list and nothing is stored per selection). The handler advances them from each finished game's stats (Market takes and their coins from the action log, gold, majorities and tokens at the end, human count, rank). Claimed points feed the free cosmetic track (`src/match/cosmetics.ts`): card backs and table felts unlock at point thresholds; nothing on the track is sold (decision D5).

## Match lifecycle

0. `quick_play` with `{"tutorial": true}` creates a solo tutorial match: one human seat, two bots with a longer think delay and deterministic tie-breaks, no step timer, a fixed seed, and the learner always seated first. Its label mode is `tutorial`, so public quick play never joins it.
1. `quick_play` RPC returns an open public match id (or creates one). Public lobbies start when full (5 seats) or 20 seconds after the first player joins, filling empty seats with bots to reach 3.
2. `create_room` RPC returns a 6-character code and a private match id; `join_room` resolves a code. Private rooms start when everyone has sent `OP_READY` and there are at least 2 humans (a bot fills the third seat).
3. During play the server applies bot moves after a short delay and auto-moves a human seat when its deadline passes. Three consecutive timeouts convert a seat to a bot; rejoining reclaims it.
4. Reconnection: a user whose seat exists may rejoin the match and receives a fresh view. The action log is kept in match state for a future replay feature.
5. The match ends 45 seconds after the game ends or when everyone leaves.

## Runtime constraints

Nakama runs JavaScript in goja, so the bundle targets ES2016 and the engine avoids `structuredClone`, `Array.prototype.flat`, `Object.fromEntries` and `at()`. Type definitions are vendored in `types/nakama-runtime/` from heroiclabs/nakama-common (see `VERSION`).
