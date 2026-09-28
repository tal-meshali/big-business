# Local-session todo

Work that needs a real machine: a phone or simulator, a Mac for iOS, store accounts, or a human at the table. Everything else in Phases 1 and 2, plus the deferred engineering below that did not need a device, was done in cloud sessions; see `docs/research/README.md` section 7 for the phase plan and the root `README.md` for how to run things.

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
- [ ] Check touch targets: hand cards, Market cards, Keep / Sell buttons. Market shares on the tilted table are about 47×55 CSS px on a 390-wide phone; if they feel small, raise `MARKET_SCALE` in `client/scripts/ui/table.gd`.
- [ ] Check the fan of 4 cards during the play step on a narrow phone (older iPhone SE width), and that the hand clears the bottom bar on a 16:9 phone (the stage shrinks to `STAGE_MIN_SCALE` on short screens). Adjust `HAND_SCALE` / `HAND_V` in `client/scripts/ui/table.gd` if cards overflow.
- [ ] Look at the perspective table on a real screen: the tilt and camera distance are `TILT_DEG` / `DIST` in `client/scripts/ui/table_surface.gd`; the design used 32° at 900 px.
- [ ] Test app backgrounding for 30 seconds mid-game and returning: the socket should reconnect and the seat should be reclaimed (auto-rejoin with backoff is implemented in `client/scripts/net/net.gd`; this checks it on a real phone).

## B2. Tutorial on a device

The tutorial exists (lobby: "How to play"): a solo game against two slow bots with no timer, a fixed seed so every learner sees the same opening, and a coach overlay that explains each rule the first time it comes up (welcome, take, play, coins on the Market, the regulator token, your token blocking a share, the end approaching, dividend day). Text lives in `client/scripts/ui/coach.gd`.

- [ ] Run the tutorial on a phone and time it. Target: under 6 minutes to dividend day. If bots feel slow, lower `TUTORIAL_BOT_THINK_MS` in `server/src/match/handler.ts`.
- [ ] Hand the phone to someone who has never seen the game. Note which coach card they re-read, which rule they still got wrong, and whether any card appears at a confusing moment (for example a bot's payment card popping up while they were choosing).
- [ ] Check card readability on a small screen: body text is 19 px; the card is 620 px wide on the 720 px design width.
- [x] Decide whether the first "Play now" should route new players into the tutorial automatically. Done in the cloud: the first "Play now" starts the tutorial (skippable); `tutorial_done` is saved in `user://net.cfg` when it ends or is left. Revisit after playtests if people find it annoying.
- [ ] With the fixed seed, script two extra coach lines that name the actual opening cards, once the card art exists.

## B3. Social features on a device

Emotes, mute, report and block exist. Tap the smiley in the top bar for the emote strip; tap an opponent's seat panel for Mute / Report / Block.

- [x] Emoji emotes rendered as placeholder glyphs. Done in the cloud: the six emoji are drawn icons (`client/scripts/ui/emote_icon.gd`); no emoji font needed.
- [ ] Check the seat tap target on a phone: the seat panel is 200x96 at design size; taps near the timer arc must still open the menu.
- [ ] Confirm blocked players' emotes stay hidden after the app restarts on a phone. The mute list is now persisted in `user://net.cfg` (`[social] muted`); block is server-side via Nakama friends.
- [ ] Apple guideline 1.2 needs published contact info. The lobby has a Help screen with "Contact support" and "Privacy policy" buttons; replace the placeholder values in `client/scripts/game/app_info.gd` with the real email and URL before submission.
- [ ] Review the 14 preset emotes and phrases with someone outside the project for tone; all-ages means no sarcastic or taunting phrases.
- [ ] Decide the moderation routine: reports land in the Nakama console (storage collection `reports`); pick who checks it and how often (the store expectation is action within 24 hours).

## B4. Progression and season

- [ ] Play two games on a phone and confirm the profile card updates (level, XP bar, wins) and the daily bonus button behaves across a UTC midnight.
- [ ] Decide whether season points should also reward last place with 1 point (currently 0) after seeing a few real standings.
- [ ] Verify the season leaderboard reset on the 1st of a month (Nakama cron `0 0 1 * *`).

## C. Playtest with people (answers the key Phase 1 question)

- [ ] Deploy the server to a VPS following `docs/deploy.md` so friends can join from anywhere. Put the domain in the lobby host field (it accepts `https://play.example.com`, and there is a "Secure (https)" toggle).
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

- [ ] Six company illustrations for the card art window (see `docs/design/theme.md`); the drawn silhouettes in `client/scripts/ui/glyphs.gd` are the placeholders. A card back with the BB monogram, coin sprites (bronze and gold) and a regulator token icon can replace the drawn ones the same way. Fonts are done (Archivo and Nunito Sans, OFL, in `client/assets/fonts/`).
- [ ] App icon and store screenshots (the cloud session's placeholder renders are in `docs/screenshots/`).
- [ ] Sound set: card deal, card place, coin slide, coin flip to gold, turn chime, dividend fanfare. Haptics on card place and on your turn.

## G. Deferred engineering (Phase 2, listed so nothing is lost)

- [x] Tutorial v2: forced choices on the first two turns (only the coached action enabled, the card to tap pulses) and a replayable rules reference (Help screen). Done in the cloud; still worth watching a first-timer use it.
- [x] Turn-timer sound and screen glow under 5 seconds. Done in the cloud, with a placeholder sound set synthesized in code (`client/scripts/game/sfx.gd`) and haptics on your turn. Real recorded sounds remain an art task (section F).
- [x] Friends list and invites: done in the cloud (add by name, accept, remove, invite a friend to a private room through a Nakama in-app notification).
- [ ] Push notification "your turn" via FCM (needs a Firebase project and the Android/iOS plugins on a real machine).
- [x] Daily and weekly quests feeding a free cosmetic track: done in the cloud (3 daily and 2 weekly quests, track points, four card backs and three table felts, picker in the lobby). Tune the point values after real play.
- [ ] Curated card skins sold a la carte through RevenueCat (see `docs/research/03-engagement-monetization.md`).
- [ ] Designer unlock and custom card upload (see `docs/research/05-custom-card-upload.md`).
- [x] Better bots: done in the cloud (`server/src/engine/bot.ts`, one-ply lookahead with a heuristic evaluation; timeouts and the tutorial keep the simple auto-move). Watch whether they feel too strong or too passive with people.
