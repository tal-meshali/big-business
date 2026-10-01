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

- [ ] Android: install Android SDK + export templates in Godot, create an Android export preset (portrait, min SDK 24, permission `VIBRATE` on for haptics), enable USB debugging, "Remote Deploy" from the editor to a phone. Point the server field at your computer's LAN IP (not 127.0.0.1).
- [ ] iOS: Xcode + Apple developer account, iOS export preset, run on a device via Xcode. Same LAN host note.
- [x] Check touch targets: hand cards, market cards, Keep / Sell buttons. Anything under ~48 px tall gets enlarged. *(Cloud: the smoke test now fails if any visible button on the lobby, table or help screen is under 48 px; the emote strip, top-bar buttons and seat-menu rows were enlarged. Still worth a thumb test on a phone.)*
- [x] Check the fan of 4 cards during the play step on a narrow phone (older iPhone SE width). *(Cloud: portrait width is always 720 design px, and a 4-card hand overflowed the left edge by 17 px on every phone; fixed, rendered at iPhone SE, iPhone 13 and tablet ratios, and covered by a smoke check.)*
- [ ] Test app backgrounding for 30 seconds mid-game and returning: the socket should reconnect and the seat should be reclaimed. Auto-rejoin exists, and `net.gd` now also checks the socket when the app resumes; this needs a real phone to confirm.

## B2. Tutorial on a device

The tutorial exists (lobby: "How to play"): a solo game against two slow bots with no timer, a fixed seed so every learner sees the same opening, and a coach overlay that explains each rule the first time it comes up (welcome, take, play, coins on the Market, the regulator token, your token blocking a share, the end approaching, dividend day). Text lives in `client/scripts/ui/coach.gd`.

- [ ] Run the tutorial on a phone and time it. Target: under 6 minutes to dividend day. The headless e2e (learner acting instantly) takes 2.5 to 3.2 minutes, almost all of it the bots' 1.8 s think time, which leaves roughly 3 minutes for a learner's ~20 turns and ten coach cards. If bots feel slow, lower `TUTORIAL_BOT_THINK_MS` in `server/src/match/state.ts`.
- [ ] Hand the phone to someone who has never seen the game. Note which coach card they re-read, which rule they still got wrong, and whether any card appears at a confusing moment (for example a bot's payment card popping up while they were choosing).
- [ ] Check card readability on a small screen: body text is 19 px; the card is 620 px wide on the 720 px design width.
- [ ] Decide whether the first "Play now" should route new players into the tutorial automatically (a "tutorial done" flag saved in `user://net.cfg`).
- [ ] With the fixed seed, script two extra coach lines that name the actual opening cards, once the card art exists.

## B3. Social features on a device

Emotes, mute, report and block exist. Tap the smiley in the top bar for the emote strip; tap an opponent's seat panel for Mute / Report / Block.

- [x] Emoji emotes render as placeholder glyphs with Godot's fallback font. *(Cloud: a 28 KB subset of Noto Color Emoji ships in `client/fonts/` as the UI font's fallback; emoji emotes are drawn larger. Verified with system fonts disabled, where they used to show as hex boxes.)*
- [x] Check the seat tap target on a phone: the seat panel is 200x96 at design size; taps near the timer arc must still open the menu. *(Cloud: the smoke test taps the outer edge of the timer arc through the viewport and expects the seat menu.)*
- [x] Confirm blocked players' emotes stay hidden after the app restarts. *(Cloud: they did not; mutes are now saved in `user://net.cfg` and blocks are reloaded from the Nakama friends list on connect.)*
- [ ] Apple guideline 1.2 needs published contact info. The lobby's "Rules and help" screen (also "?" at the table) has Email support and Privacy policy buttons, disabled until you fill `SUPPORT_EMAIL` and `PRIVACY_URL` in `client/scripts/game/app_info.gd`.
- [ ] Review the 14 preset emotes and phrases with someone outside the project for tone; all-ages means no sarcastic or taunting phrases.
- [ ] Decide the moderation routine: reports land in the Nakama console (storage collection `reports`); pick who checks it and how often (the store expectation is action within 24 hours).

## B4. Progression and season

- [ ] Play two games on a phone and confirm the profile card updates (level, XP bar, wins) and the daily bonus button behaves across a UTC midnight.
- [ ] Decide whether season points should also reward last place with 1 point (currently 0) after seeing a few real standings.
- [ ] Verify the season leaderboard reset on the 1st of a month (Nakama cron `0 0 1 * *`). *(Cloud: the Node e2e now checks that every season record expires at 00:00 UTC on the 1st of next month, which is how Nakama applies the reset. Glance at the standings on the 1st to see it happen.)*

## C. Playtest with people (answers the key Phase 1 question)

- [ ] Deploy the server to a VPS following `docs/deploy.md` so friends can join from anywhere. Type `https://your.domain` in the lobby's server field (it accepts a bare host, `host:port`, or an http/https URL).
- [ ] Run 3 sessions of a 5-player game with friends, 30-second timer. Record: game length, whether the first game was understandable without a tutorial, which rule confused people, whether the timer felt rushed or slow, whether anyone lost track of who holds a regulator token.
- [ ] Decide the default step timer (20 / 30 / 45 s) from those sessions.
- [ ] Note which animations were missed (players didn't notice a token moving, a coin payment, a market take). These become Phase 2 juice work.

## C2. First playtest feedback (from your own games)

Fixed in the cloud; each needs a check on a phone.

- [ ] Bots keeping shares. Bots now lock pairs into their Portfolio and keep about half their plays from their first or second turn (rules-spec 8.2; `PAIR_BONUS` in `server/src/engine/bot.ts`), and tutorial bots keep a pair too once the Market has a share. At 3 and 4 seats they also model opponents' remaining pickups more tightly. Play two games against bots and say whether they now feel like players.
- [ ] Press and hold a card (hand or Market) for a close-up above everything; letting go closes it and does not select the card. Check the 0.35 s hold (`CardView.HOLD_SECONDS`) feels right under a thumb and that a hold on the Market row still lets it scroll.
- [ ] Get-ready countdown (4 s, `GET_READY_MS` in `server/src/match/state.ts`) with the turn order before the first turn. Also fixed: the table used to miss the game's first view and sit empty until the first move (or 30 s, when you moved first).
- [ ] Forfeit: the top-bar button reads "Forfeit" during a live game, asks first, and a bot takes the seat. Try it with a friend at the table to see their "Forfeited" bubble.
- [ ] The "newest card fades in when you cancel a selected card" report: the screen recording showed it in the browser table (`web/`), where selecting or cancelling re-rendered the hand and replayed the newest card's arrival animation; fixed there. In the Godot client the selection lift was hardened as well (a new lift replaces a running one, the selected card draws above its neighbours, a share you take flies face up into its own slot). Check both on a phone.

## D. Rules verification against the physical game

- [ ] Get a copy of the source game (or its rulebook) and check every **verify** item in `docs/design/rules-spec.md`: token behaviour on ties, the same-company restriction when selling to the Market, and payment exemptions. Update the spec and `server/src/engine/game.ts` plus tests if anything differs.

## E. Accounts and stores (needed before any public build)

- [ ] Apple Developer Program and Google Play Console accounts.
- [ ] App identifiers: pick a bundle id (for example `com.<you>.bigbusiness`) and set it in both export presets.
- [ ] Privacy policy URL and support email (required by both stores, and by the report/contact rule for all-ages apps). Put them in `client/scripts/game/app_info.gd`; the help screen shows them.
- [ ] Age rating questionnaires: no simulated gambling, no UGC yet, no ads. Aim for 4+ / Everyone.
- [ ] Sign in with Apple and Google so accounts survive reinstalls. *(Cloud: the lobby's Account row links Apple or Google to the guest account, the next launch signs in with the linked provider and falls back to the device id, and the `account_links` RPC reports link state.)* Still needed here: install the native plugins and return their tokens from `client/scripts/net/social_tokens.gd` (the file names the plugins), set `APPLE_BUNDLE_ID` and `GOOGLE_CLIENT_ID` in `.env`, then link and reinstall on a phone to confirm the account comes back. See `docs/deploy.md` "Social sign-in".
- [ ] Before the first public build, work through the operator half of the Security checklist in `docs/deploy.md` (secrets, console over SSH only, firewall, backups, moderation routine).

## F. Art and sound (can be commissioned in parallel)

- [ ] Six company illustrations for the card art window (see `docs/design/theme.md`), a card back with the BB monogram, table background, coin sprites (bronze and gold), regulator token icon.
- [ ] App icon and store screenshots (the cloud session's placeholder renders are in `docs/screenshots/`).
- [ ] Sound set: card deal, card place, coin slide, coin flip to gold, turn chime, timer tick, dividend fanfare. Placeholders are synthesised in `client/scripts/ui/sfx.gd` and already wired to the table; replace them one name at a time. Haptics on card place, on your turn and in the last two seconds are done (sound and vibration toggles are on the help screen).

## G. Deferred engineering (Phase 2, listed so nothing is lost)

- [x] Tutorial v2: forced choices on the first two turns (only the coached action enabled) and a replayable "rules reference" screen. *(Cloud: keep on turn one; take the Market share with coins, then sell, on turn two; new "Selling to the Market" coach card. Rules reference in the help screen.)*
- [x] Turn-timer sound and screen glow under 5 seconds. *(Cloud: red pulsing rim and a tick each second on your own step.)*
- [x] Friends list and invites. *(Cloud: add by exact username, accept, remove; invite a mutual friend to a private room through a Nakama in-app notification, shown once whether it arrives live or while offline. Try it on two phones.)*
- [ ] Push notification "your turn" via FCM (needs a Firebase project and the Android/iOS plugins on a real machine).
- [x] Daily and weekly quests feeding a free cosmetic track. *(Cloud: 3 daily and 2 weekly quests, track points, card backs and table felts with a picker in the lobby; nothing on the track is sold. Tune the point values after real play.)*
- [ ] Curated card skins sold a la carte through RevenueCat (see `docs/research/03-engagement-monetization.md`).
- [ ] Designer unlock and custom card upload (see `docs/research/05-custom-card-upload.md`).
- [x] Better bots: the current auto-move policy is a placeholder. *(Cloud: real-game bots use a heuristic bot in `server/src/engine/bot.ts` that decides from its own seat's view; against the old policy it averages 20.1 vs 13.1 at 3 seats and 15.3 vs 13.2 at 7, with the keep pace from section C2. Timeouts and the tutorial keep the simple policy, now in `auto.ts`. Still to judge: how it feels to play against, and whether bots taking Market shares more than drawing makes games drag; see rules-spec section 8.2.)*
