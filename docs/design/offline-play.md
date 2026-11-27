# Offline play: plan

Status: plan only, nothing built yet. Decision: D30 in `docs/decisions.md`.

Goal: a player with no connection (plane, subway, the home server down) can still play a full game against bots on their phone. A later step adds pass-and-play: several people sharing one phone.

## 1. What exists today

- **Every game runs on the server.** Vs bots, quick play, private rooms and the tutorial are all Nakama matches (`server/src/match/handler.ts`). The phone sends moves and draws what comes back. With no connection, the lobby disables every play button (`main.gd` `_on_failed` -> `_set_online_buttons(false)`).
- **The rules are already separate from the server.** `server/src/engine` is pure TypeScript with no Nakama, no clock and no global randomness: `game.ts` (rules, 442 lines), `bot.ts` (heuristic bot, 505), `auto.ts` (timeout move and tutorial bot, 102), `view.ts` (what each seat may see, 52), `rng.ts` (mulberry32, 37), `companies.ts`, `types.ts`. About 1,100 lines with 885 lines of tests.
- **The browser table** (`web/big-business.html`) bundles that engine and plays offline in a browser. A phone can't run it: Godot has no JavaScript runtime on iOS or Android.
- **The table screen is already decoupled.** `table.gd` hears the game only through `Net.view_updated` (a `PlayerView` dictionary) and `Net.events_received` (seq + `GameEvent` list), and acts only through `Net.send_action`, `send_emote`, `forfeit` and `leave_match`. A local game that speaks those same signals needs no table changes.
- **The match loop around the engine is small.** It is what a local host has to copy: 4-second get-ready (`GET_READY_MS`), bot think time (`BOT_THINK_MS` 900 ms, tutorial 1800 ms), timeout moves at `deadline` via `autoAction`, a human who times out 3 times becomes a bot (`AUTO_MOVES_TO_BOT`), views send an empty `legal` list during get-ready, and the game ends on `phase == "ended"`.

## 2. Options for running rules on the phone

| Option | What it means | Verdict |
|---|---|---|
| A. Port the engine to GDScript | Second copy of the rules and bots, kept in step by shared recorded games (section 4) | **Recommended.** Pure GDScript, works on every export, no native build risk. Cost: two engines to maintain. |
| B. Embed a JavaScript runtime | QuickJS or similar as a GDExtension, run the bundled engine | Rejected. Native library per platform (iOS static linking, Android ABIs), a third-party addon to keep alive through Godot upgrades, and App Store review of an embedded interpreter. More risk than the 1,100 lines it saves. |
| C. Make GDScript the only engine and run it on the server too | Godot headless server | Rejected. Throws away Nakama's authoritative TypeScript match, tests and anti-cheat. |

## 3. Design

### 3.1 Client engine (`client/scripts/game/engine/`)

A straight port, file for file, so a diff of a rule change reads side by side:

| TypeScript | GDScript | Notes |
|---|---|---|
| `rng.ts` | `rng.gd` | mulberry32 with explicit 32-bit masking (`& 0xFFFFFFFF`) and an `imul` helper, since GDScript ints are 64-bit. Must return the same floats as JS for the same seed. |
| `companies.ts`, `types.ts` | `companies.gd`, `rules_types.gd` | Constants and the shapes as Dictionaries/Arrays, using the same JSON field names as the server. |
| `game.ts` | `rules.gd` | `create_game`, `apply_action`, `legal_actions`, `draw_cost`, dividends. Throws become a returned error string (`RulesError` -> `{error}`), since GDScript has no exceptions. |
| `auto.ts` | `auto_move.gd` | Timeout move and the tutorial bot. |
| `bot.ts` | `bot.gd` | Heuristic bot; takes an rng callable like the TS one. |
| `view.ts` | `player_view.gd` | The per-seat view the table already understands. |

Layering: these files live in `scripts/game` (bottom layer), so `tools/graph_check.py` keeps them free of UI references.

### 3.2 Local match host (`client/scripts/net/local_match.gd`)

A node that plays the server's part on the phone, with the same timing rules as `handler.ts` and `actions.ts` (get-ready, bot think time, timeouts, timeout-to-bot, end). It never runs while a server match is open.

`Net` gets a small switch: `Net.play_offline(bot_count)` starts a `LocalMatch`, and `send_action`, `forfeit`, `leave_match` route to it while it is active. The host emits the existing `view_updated` and `events_received` signals.

WHY round-trip through JSON: the host passes every view and event through `JSON.stringify` then `JSON.parse_string` before emitting, so the table gets exactly the types it gets from the server (numbers as floats). The regulator-chip bug in PR #11 came from that difference, and this keeps one code path.

Emotes offline: shown locally, bots never answer (same as today). Report, block and mute are hidden. Watching a friend is not offered.

### 3.3 Lobby and app shell

- No connection: "Vs bots" stays enabled and starts an offline game with the same 2 / 3 / 4 bot sheet (D28). Online-only buttons stay disabled. A calm line under the status says "Offline: bot games are practice and don't earn XP."
- Connection comes back mid-game: the offline game carries on; nothing migrates to the server.
- The tutorial can also run offline (fixed seed `TUTORIAL_SEED`, `autoAction` tie-break 0, seats rotated so the learner goes first), which means the coach works on a first launch without network. Worth doing in the same slice because a first launch with no network is exactly when it matters.
- End of game: the result sheet shows places and dividends from the local result; the XP / quest lines (and the earnings report from PR #27) are replaced by the practice note.
- Card looks: offline games use the standard deck and whatever skins and custom decks are already cached on the phone.

### 3.4 Pass-and-play (later slice)

Same local host with 2 to 7 human seats (bots optional to fill). Before each human's turn a full-screen cover "Pass to Dana" hides the previous hand until the next player taps. Timer off by default (pass-and-play is social and slow). The one real design question is the cover between turns; the rest is reuse.

## 4. Keeping the two engines in step (golden games)

The risk of option A is drift: a rule change made in TypeScript and forgotten in GDScript. The guard is a set of recorded games both engines must replay identically, checked in CI on every push.

1. **Recorder** (`server/src/engine/golden.ts`, run by `npm run golden`): plays N full games (all seat counts 3 to 7, both bot policies, a few timeouts) from fixed seeds, with the bot rng also seeded, and writes `shared/golden/*.json`: seed, seat list, and for every step the action, the resulting events, every seat's `playerView`, the `legalActions` list and the bot's chosen action.
2. **TypeScript check** (in `npm test`): replays each file and fails if anything differs. A rule change that alters games forces a re-record, and the diff shows up in review.
3. **GDScript check** (`client/tests/golden.gd`, a new CI step next to the smoke test): replays the same files through the ported engine and compares every view, event, legal list and bot choice. Any difference fails CI with the game, step and field.
4. **CI ties them**: like the existing "browser table bundles the current engine" step, CI re-records and fails if the committed golden files are stale. So a TypeScript rule change cannot merge without new golden files, and new golden files cannot pass without the GDScript port matching.

What it catches: rule changes, scoring, dividend ties, bot decisions (since the bot rng is fixed), shuffle order, view fields. What it does not catch: timing in the local host (covered by its own smoke test) and rules no recorded game reaches (mitigation: the recorder also plays crafted edge cases from `game.test.ts`).

## 5. PR slices

Each slice goes through the project workflow (build, separate tester, separate reviewer, fix) before Tal sees it.

1. **Golden games recorder + TS check.** Server only, no behaviour change. Small.
2. **GDScript engine port + golden check in CI.** The bulk of the work (about 1,100 lines of rules and bots, plus `golden.gd`). No UI yet; nothing a player sees changes.
3. **Local match host + offline Vs bots + offline tutorial.** `local_match.gd`, the `Net` switch, lobby offline state, end sheet practice note. Smoke test drives a full offline game headless; screenshots of the offline lobby and end sheet for review.
4. **Pass-and-play** (after Tal tries slice 3). Seat setup sheet, pass cover, timer off.

Rough size: slices 1 to 3 are one large feature, about the size of the profile or engagement work. Slice 2 is half of it.

## 6. Risks

- **Two engines drift** — golden games in CI (section 4).
- **Number types** — JSON round-trip in the host (3.2).
- **The engine changes during the port** — land slice 1 first so any rule PR merged meanwhile updates the golden files the port is checked against.
- **Bot strength on old phones** — the bot is simple heuristics; a profile on a low-end Android in slice 3 confirms think time is not CPU-bound.
- **Cheating** — the phone owns the whole game offline, so nothing from it is trusted. That is why offline games award nothing (D30).

## 7. Open decisions (recommended defaults in D30)

1. Offline games earn no XP, quests, stats or season points: practice only. *(Alternative: queue results and send them later. Rejected: the server cannot check a game it did not run, so it would be a free XP button for a modified client.)*
2. Online "Vs bots" stays on the server, so it keeps counting. The local engine only runs when there is no connection. *(Alternative: always play bots locally for instant start and less server load, at the cost of those games no longer counting.)*
3. The tutorial also works offline.
4. Pass-and-play comes after offline Vs bots, as its own slice.
