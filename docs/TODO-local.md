# Local-session todo

Work that needs a real machine: a phone or simulator, a Mac for iOS, store accounts, or a human at the table. Everything else in Phase 1 was done in the cloud session; see `docs/research/README.md` section 7 for the phase plan and the root `README.md` for how to run things.

Tick items off as they are done.

## A. First run on your machine

- [ ] Install Godot 4.6 and Docker Desktop. Node 22 for the server.
- [ ] `cd server && npm install && npm run check && docker compose up`. Open http://127.0.0.1:7351 (admin / password) and confirm the "Big Business runtime loaded" log line.
- [ ] Open `client/` in Godot, press Play. The lobby auto-connects to 127.0.0.1. Press "Play now", wait 20 seconds, and play a full game against bots.
- [ ] Run two Godot instances (Debug > Run Multiple Instances) and try a private room: create in one, join by code in the other, both press "I'm ready".
- [ ] Run `node e2e/play.mjs` in `server/` and `godot --headless --path client --script res://tests/e2e_client.gd` to confirm the automated checks pass on your machine too.

## B. Play it on a phone (the Phase 1 goal)

- [ ] Android: install Android SDK + export templates in Godot, create an Android export preset (portrait, min SDK 24), enable USB debugging, "Remote Deploy" from the editor to a phone. Point the host field at your computer's LAN IP (not 127.0.0.1).
- [ ] iOS: Xcode + Apple developer account, iOS export preset, run on a device via Xcode. Same LAN host note.
- [ ] Check touch targets: hand cards, market cards, Keep / Sell buttons. Anything under ~48 px tall gets enlarged.
- [ ] Check the fan of 4 cards during the play step on a narrow phone (older iPhone SE width). Adjust `HAND_SCALE` in `client/scripts/ui/table.gd` if cards overflow.
- [ ] Test app backgrounding for 30 seconds mid-game and returning: the socket should reconnect and the seat should be reclaimed. If not, add auto-rejoin in `client/scripts/net/net.gd` (`_on_socket_closed` currently only reports the disconnect).

## B2. Tutorial on a device

The tutorial exists (lobby: "How to play"): a solo game against two slow bots with no timer, a fixed seed so every learner sees the same opening, and a coach overlay that explains each rule the first time it comes up (welcome, take, play, coins on the Market, the regulator token, your token blocking a share, the end approaching, dividend day). Text lives in `client/scripts/ui/coach.gd`.

- [ ] Run the tutorial on a phone and time it. Target: under 6 minutes to dividend day. If bots feel slow, lower `TUTORIAL_BOT_THINK_MS` in `server/src/match/handler.ts`.
- [ ] Hand the phone to someone who has never seen the game. Note which coach card they re-read, which rule they still got wrong, and whether any card appears at a confusing moment (for example a bot's payment card popping up while they were choosing).
- [ ] Check card readability on a small screen: body text is 19 px; the card is 620 px wide on the 720 px design width.
- [ ] Decide whether the first "Play now" should route new players into the tutorial automatically (a "tutorial done" flag saved in `user://net.cfg`).
- [ ] With the fixed seed, script two extra coach lines that name the actual opening cards, once the card art exists.

## C. Playtest with people (answers the key Phase 1 question)

- [ ] Deploy the server to a VPS following `docs/deploy.md` so friends can join from anywhere. Put the domain in the lobby host field with scheme https (add a scheme toggle to the lobby if needed).
- [ ] Run 3 sessions of a 5-player game with friends, 30-second timer. Record: game length, whether the first game was understandable without a tutorial, which rule confused people, whether the timer felt rushed or slow, whether anyone lost track of who holds a regulator token.
- [ ] Decide the default step timer (20 / 30 / 45 s) from those sessions.
- [ ] Note which animations were missed (players didn't notice a token moving, a coin payment, a market take). These become Phase 2 juice work.

## D. Rules verification against the physical game

- [ ] Get a copy of the source game (or its rulebook) and check every **verify** item in `docs/design/rules-spec.md`: token behaviour on ties, the same-company restriction when selling to the Market, and payment exemptions. Update the spec and `server/src/engine/game.ts` plus tests if anything differs.

## E. Accounts and stores (needed before any public build)

- [ ] Apple Developer Program and Google Play Console accounts.
- [ ] App identifiers: pick a bundle id (for example `com.<you>.bigbusiness`) and set it in both export presets.
- [ ] Privacy policy URL and support email (required by both stores, and by the report/contact rule for all-ages apps).
- [ ] Age rating questionnaires: no simulated gambling, no UGC yet, no ads. Aim for 4+ / Everyone.
- [ ] Sign in with Apple and Google Sign-In configuration in Nakama (`local.yml` social keys) so accounts survive reinstalls. Device-id guest auth stays for first launch.

## F. Art and sound (can be commissioned in parallel)

- [ ] Six company illustrations for the card art window (see `docs/design/theme.md`), a card back with the BB monogram, table background, coin sprites (bronze and gold), regulator token icon.
- [ ] App icon and store screenshots (the cloud session's placeholder renders are in `docs/screenshots/`).
- [ ] Sound set: card deal, card place, coin slide, coin flip to gold, turn chime, dividend fanfare. Haptics on card place and on your turn.

## G. Deferred engineering (Phase 2, listed so nothing is lost)

- [ ] Tutorial v2: forced choices on the first two turns (only the coached action enabled) and a replayable "rules reference" screen.
- [ ] Reconnect flow polish: automatic socket reconnect with backoff, "reconnecting..." overlay, rejoin by stored match id.
- [ ] Turn-timer sound and screen glow under 5 seconds.
- [ ] Emotes and preset phrases (no free text: all-ages decision D4).
- [ ] Profiles, friends, invites; push notification "your turn" via FCM.
- [ ] Daily reward, quests, ranked season (see `docs/research/03-engagement-monetization.md`).
- [ ] Designer unlock and custom card upload (see `docs/research/05-custom-card-upload.md`).
- [ ] Better bots: the current auto-move policy is a placeholder (`autoAction` in `server/src/engine/game.ts`).
