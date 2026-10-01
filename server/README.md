# Big Business server

Nakama runtime for the authoritative game. Two layers:

- `src/engine/`: the pure rules engine. No Nakama imports, no clock, no global randomness. `game.ts` holds the rules, `view.ts` the per-seat views, `auto.ts` the simple auto-move and `bot.ts` the heuristic bot; covered by `game.test.ts` and `bot.test.ts`. This is the reference implementation of `docs/design/rules-spec.md`.
- `src/match/`: the Nakama match handler (lobby, seats, bots, timers, per-seat views, reconnection) and the wire protocol.
- `src/main.ts`: registers the match handler and the RPCs listed below. Every RPC is wrapped by `guardRpc` and reads its payload through `src/match/input.ts` (pure validators, unit-tested): malformed JSON, arrays, wrong types and out-of-range numbers are rejected with a short message, and any other failure is logged and returned as `internal error`. `src/match/ratelimit.ts` holds the per-user rate limits (fixed one-minute windows in the `ratelimit` storage collection, atomic through versioned writes).

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

`e2e/play.mjs` verifies room codes, ready gating, hidden information, illegal and malformed action rejection (the match survives), timeout auto-move, leave and rejoin, coin conservation on every state, dividend day, friend requests with room invites delivered as notifications (and refused for strangers), bad RPC payloads and the report rate limit, and quick play filling with bots after the lobby wait. Both scripts exit non-zero on failure.

## Production

`Dockerfile` bakes `build/index.js` into the official Nakama image. `docker-compose.prod.yml` plus `Caddyfile` run Postgres, Nakama and automatic TLS on one VPS; see `docs/deploy.md`.

## Wire protocol

Payloads are JSON strings.

| Direction | Opcode | Payload |
|---|---|---|
| client -> server | 1 `OP_ACTION` | `{"type":"take_supply"}` / `{"type":"take_market","cardId":n}` / `{"type":"play_portfolio","cardId":n}` / `{"type":"play_market","cardId":n}`; anything else (or over 256 bytes) gets `OP_ERROR` `bad action payload` |
| client -> server | 2 `OP_READY` | empty; marks the sender ready in a private lobby |
| client -> server | 3 `OP_EMOTE` | `{"emote":"<id>"}` from `EMOTE_IDS`; 2 s cooldown per player, checked before parsing; unknown ids and payloads over 128 bytes dropped |
| server -> client | 10 `OP_VIEW` | `PlayerView` for that seat (see `src/engine/types.ts`), sent after every accepted action, join and leave |
| server -> client | 11 `OP_EVENTS` | `{seq, events: GameEvent[]}` for animations |
| server -> client | 12 `OP_LOBBY` | `LobbyMessage` while waiting to start |
| server -> client | 13 `OP_ERROR` | `{message, action?}` |
| server -> client | 14 `OP_EMOTE_SHOWN` | `{seat, emote}` relayed to everyone at the table |

## RPCs

| RPC | Payload | Returns |
|---|---|---|
| `quick_play` | `{}` or `{"tutorial": true}` | `{matchId}` (open public lobby or a new one; tutorial match when asked); 12 per minute per user |
| `create_room` | `{stepSeconds?, maxSeats?}` | `{code, matchId}`; `stepSeconds` 0 (no timer) or clamped to 5..120 (default 30), `maxSeats` to 2..7 (default 7); 6 per minute per user |
| `join_room` | `{code}` | `{code, matchId}`; error `invalid code` or `room not found` (a code whose match has ended is removed). Join the match with `{code}` as join metadata: a private room refuses a join without its code |
| `get_profile` | `{}` | `{progress: {xp, level, gamesPlayed, wins, streak, lastDailyClaim, bestRank, trackPoints, quests, equipped}, dailyAvailable, quests: {daily: [...], weekly: [...]}, trackPoints, unlocked, equipped: {cardBack, table}, track: [{points, cosmeticId}]}`; each quest row is `{id, text, target, points, progress, claimable, claimed}` |
| `claim_daily` | `{}` | `{claimed, xpAwarded, progress}`; once per UTC day, streak grows on consecutive days |
| `claim_quest` | `{id}` | `{ok, trackPoints, unlocked}`; adds a completed quest's points to the free cosmetic track, once (a concurrent claim or daily claim of the same row fails with `try again`) |
| `equip_cosmetic` | `{slot, id}` | `{ok, equipped}`; `slot` is `cardBack` or `table`, `id` must be unlocked |
| `report_player` | `{userId, reason, matchId?, note?}` | `{ok}`; `userId` must be an existing user other than the caller, `note` is cut to 200 characters; written to the `reports` storage collection (system user, console-only) as one row per UTC day, reporter and reported player with a `count` and the first 10 reports' `{reason, matchId, note, at}` in `entries`; 5 per minute per user |
| `find_player` | `{name}` | `{userId, username}`; exact username match, never the caller; error `not found` otherwise; 20 per minute per user |
| `invite_friend` | `{userId, code}` | `{ok}`; caller and target must be mutual friends (Nakama friend state 0), the target must not have blocked the caller, and the code must be a live room. Sends a persistent in-app notification, code 100 (`INVITE_CODE`), subject `Room invite`, content `{code, fromName, fromUserId}` where `fromName` is the caller's server-side username cut to 32 characters; 10 per minute per user |
| `account_links` | `{}` | `{apple, google, device, username}`; which sign-in methods the caller's account has (from `accountGetId`), so the lobby can show link state without parsing the raw account. Linking and unlinking Apple / Google use Nakama's own link API from the client; see `docs/deploy.md` "Social sign-in" |

Rate-limited calls beyond their budget fail with `too many requests`. Friend requests (Nakama's own `AddFriends` API) are limited the same way by a before-hook, 20 players per minute (a request naming several players costs one per player).

Storage permissions: `profile/progress` is readable by its owner only and never client-writable; `rooms`, `reports` and `ratelimit` are server-only; the `season` leaderboard is authoritative. Before-hooks on Nakama's WriteStorageObjects and DeleteStorageObjects refuse any client request touching `profile`, `ratelimit`, `rooms` or `reports`, so a client cannot pre-seed a row the server would trust (and a profile row the client created anyway is ignored).

Match labels carry the mode, open flag and seat counts, never the room code: any client can list matches.

Progression (`src/match/progression.ts`, pure and unit-tested) is applied by the match handler once when a game ends: XP for participation, placement and wins (halved for games against bots only), and season points on the `season` leaderboard (monthly reset, only for games with at least two humans). Adding, accepting, removing and blocking friends use Nakama's friends API from the client; the social RPCs (`src/match/social.ts`, invite rules unit-tested) only look players up and deliver room invites as Nakama in-app notifications (no push).

Quests (`src/match/quests.ts`): three daily quests picked deterministically from the UTC date and two weekly ones from the ISO week (seeded, so every player sees the same list and nothing is stored per selection). The handler advances them from each finished game's stats (Market takes and their coins from the action log, gold, majorities and tokens at the end, human count, rank). Claimed points feed the free cosmetic track (`src/match/cosmetics.ts`): card backs and table felts unlock at point thresholds; nothing on the track is sold (decision D5).

## Match lifecycle

0. `quick_play` with `{"tutorial": true}` creates a solo tutorial match: one human seat, two bots with a longer think delay and deterministic tie-breaks, no step timer, a fixed seed, and the learner always seated first. Its label mode is `tutorial`, so public quick play never joins it.
1. `quick_play` RPC returns an open public match id (or creates one). Public lobbies start when full (5 seats) or 20 seconds after the first player joins, filling empty seats with bots to reach 3.
2. `create_room` RPC returns a 6-character code and a private match id; `join_room` resolves a code. Joining a private lobby needs the code as join metadata (`{code}`); players already in the lobby and seated players rejoining a started game do not. Private rooms start when everyone has sent `OP_READY` and there are at least 2 humans (a bot fills the third seat).
3. During play the server applies bot moves after a short delay and auto-moves a human seat when its deadline passes. Real-game bots use the heuristic bot (`src/engine/bot.ts`); timeouts and tutorial bots use the simple `autoAction` (rules-spec section 8). Three consecutive timeouts convert a seat to a bot, which then plays with the heuristic bot; rejoining reclaims it.
4. Reconnection: a user whose seat exists may rejoin the match and receives a fresh view. A second socket of the same user takes the seat over (views go to the newest session; the older session's leave is ignored), so a phone that changed networks reconnects before the server has noticed the drop. The action log is kept in match state for a future replay feature.
5. The match ends 45 seconds after the game ends or when everyone leaves.

## Runtime constraints

Nakama runs JavaScript in goja, so the bundle targets ES2016 and the engine avoids `structuredClone`, `Array.prototype.flat`, `Object.fromEntries` and `at()`. Type definitions are vendored in `types/nakama-runtime/` from heroiclabs/nakama-common (see `VERSION`).
