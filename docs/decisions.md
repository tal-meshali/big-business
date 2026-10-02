# Decision record

Decisions made by the project owner on 2026-09-27, after the research in `docs/research/`. Each entry is short on purpose: what was decided, why, and what it implies.

## D1. Name and theme: "Big Business", fully re-themed

- **Decision:** the app is called Big Business. It reimplements the mechanics of Startups (Jun Sasaki, Oink Games) with original company names, icons, art and rule text. No licence is sought.
- **Why:** mechanics are not protected by copyright; names, art and rule prose are. Re-theming removes the IP risk without waiting on a licensor that competes with its own app.
- **Implies:** nothing from Oink may appear in the app or store listing: not the title, the six company names, the animal mascots, the card art, the chip art, the colour scheme, or rulebook sentences. The companies are defined in `docs/design/theme.md`. The rules are written in our own words in `docs/design/rules-spec.md`. The app and store copy do not mention Startups or Oink.

## D2. Engine: Godot 4.6 with GDScript

- **Decision:** the client is built in Godot 4.6 using GDScript.
- **Why:** solo developer, zero licensing, small builds, strong 2D tween and UI nodes, official Nakama client, official StoreKit 2 and Play Billing plugins as of 4.6.
- **Implies:** no C# on mobile (export still experimental). Godot 4.6 is pinned; upgrades are deliberate.

## D3. Backend: Nakama, self-hosted, TypeScript match handlers

- **Decision:** Nakama runs the authoritative game. Match logic is a pure TypeScript rules engine wrapped by a Nakama match handler.
- **Why:** it bundles auth, friends, groups, chat, leaderboards, storage and matchmaking, and has an official Godot 4 client. Self-hosting costs $20 to 40 a month.
- **Implies:** clients send intents only; the server shuffles, deals and scores. The engine is pure and unit-tested independently of Nakama.

## D4. Audience: every age

- **Decision:** the app targets all ages.
- **Why:** the game has no gambling; framed as investing it fits a 4+ / PEGI 3 rating.
- **Implies:**
  - No casino framing anywhere: no "bet", "gamble", poker chips, slot iconography or "casino" in store copy. Currency is "capital" and cards are "shares".
  - No free-text chat for anyone under 13. Ship preset phrases and emotes only at launch; free-text chat, if ever added, is gated behind a 13+ declared age.
  - Custom card upload (the premium feature) is gated at 13+ (16+ where the EU requires it), because photos are personal data under COPPA. Younger players can still see custom decks in private rooms only if the host opts in.
  - Ask for age at first launch (neutral age screen, not a yes/no gate), store only the age bracket, and keep analytics and advertising SDKs configured for mixed audiences (no personalised ads). Without an ad network configured for families, ship with no ads at all.
  - Contact info, report and block are available to every player.

## D5. Premium: one-time "Designer" unlock first

- **Decision:** premium launches as a one-time, non-consumable purchase ("Designer", $4.99 to 9.99, final price to be tested) that unlocks custom card designs. No subscription at launch.
- **Why:** a one-time cosmetic unlock reviews cleanly with Apple and Google and does not require the ongoing-value promise a subscription needs. A subscription can be layered on later if there is enough rotating content.
- **Implies:** entitlements are checked server-side via RevenueCat. Custom decks display in private rooms only at launch. Restore Purchases is required on both stores. No loot boxes, no virtual currency at launch; curated skins, if sold, are priced in real money.

## D6. Portrait-first

- **Decision:** the table is designed for portrait, one-handed play. Landscape is not planned.
- **Why:** real-money poker apps and every premium casual card game moved to portrait; landscape-forcing apps get complaints.

## D7. Working directories

- `docs/` research, design and decisions.
- `server/` Nakama TypeScript runtime: pure rules engine in `server/src/engine`, match handler in `server/src/match`.
- `client/` Godot 4.6 project.

## D8. Shop, analytics, Remote Config and push stay on our server

- **Decision:** store entitlements are read by the Nakama server from RevenueCat and kept in a server-only row; analytics are aggregate counts per install day in Nakama storage; Remote Config lives in Nakama storage; "your turn" pushes are sent by the server through FCM HTTP v1. Firebase is used only for FCM delivery and, later, Crashlytics.
- **Why:** D5 requires server-side entitlements and Restore Purchases. D4 (every age, no personalised ads) is easiest to keep when no analytics SDK collects device data: D1 / D7 and the first-session funnel need only install day, active days and first-time steps. The server itself reads some switches (push off, quick-play wait), so Remote Config has to be where it can read them.
- **Implies:** the client never says what it owns; it buys through the store plugin and asks the server to sync. Server-to-server RPCs (Remote Config, analytics report, RevenueCat webhook) need the runtime http_key, which is a production secret. Without RevenueCat or FCM keys the shop reports "opens soon" and nothing is pushed. Pushes are capped (one per cooldown per player and match) and only sent when a turn starts for a player who is away.

## D9. Left-to-right layout, larger type (2026-10-02)

- **Decision:** the client always lays out left to right (`internationalization/rendering/root_node_layout_direction=1`), and UI text is about 20% larger than the first pass (labels 19 px, buttons and inputs 22 px on the 720 px canvas; seat cards widened to 220 px).
- **Why:** on the owner's first local run (macOS in Hebrew) Godot mirrored the whole table: the supply pile jumped to the right and the hand fan rendered off screen. The app has no translations, so the locale should not flip the layout. Text was also too small on a phone.
- **Implies:** if Hebrew or Arabic translations ever ship, right-to-left support is a deliberate project: the table's absolute positions (`_hand_slot`, seat slots) assume left to right. New UI uses the larger sizes as the floor.

## D10. The "3D table" design (2026-10-02)

- **Decision:** the client follows the "Big Business — 3D Table" design: a felt table tilted 32 degrees in perspective with printed zones, opponents on plates around the far side, the hand standing at the near edge, a cream bottom bar, Archivo Black and Nunito Sans (bundled, OFL), and a start page with a fanned set of shares over a small felt. Layouts are written in design points of the 390 x 844 artboard and scaled by `UiTheme.layout_scale`, so the same layout fills a 16:9 and a 19.5:9 phone. The tutorial coach dims the table except the area its step is about.
- **Why:** the owner asked for the design to be implemented. Scaling from the artboard also fixes the remaining "too small on a phone" complaint from D9: the design's 44-point buttons become 67 to 81 px on the 720 px canvas, and nothing on the table is under the 48 px touch target.
- **Implies:** the tilt is drawn in 2D (`TableBoard.project`), not with a 3D scene, so cards stay ordinary Controls and every smoke and e2e hook still works. D9 still holds: the layout is pinned left to right, and Hebrew-locale screenshots match the default ones. Company art is drawn in code (sun, pine, anchor, gear, cloud, bolt) until the commissioned art in TODO-local F replaces the art window.

## D11. Designer: art windows and backs, rendered on the device, reviewed before others see it (2026-10-02)

- **Decision:** a custom deck is a card back plus one picture per company that fills the art window on the card face; the frame, company name and share count are always drawn by the client. The device crops and encodes each picture as a WebP at a fixed size (back 250 x 350, window 324 x 228, 64 KB at most); the server checks the header, size and length, stores it once per content hash, and serves it by hash. A picture shows to other players only once it is approved, by the Cloud Vision scan when a key is set or by the operator. Only the host's selected deck shows, only in private rooms. The age question (D4) is asked inside Designer for now.
- **Why:** Nakama's JavaScript runtime cannot decode or resize images, so rendering has to happen on the device, and a fixed template means the server can verify what it stores without decoding it. Keeping the frame in code means a custom deck can never hide which company a card is. Approval before display, private rooms only, and the host's deck only keep the moderation surface small enough for one operator (research 05 section 4).
- **Implies:** the art travels as RPC payloads (about 90 KB), within Nakama's HTTP request limit; the socket message limit is untouched. Refused pictures are deleted, not kept; three strikes end uploads for an account. Plus (more slots, public-match opt-in) builds on the same deck row.

## D12. Plus is built but switched off (2026-10-02)

- **Decision:** the Plus subscription (research section 7, Phase 3) is in the code and is offered only while Remote Config `plusEnabled` is on; it ships off. Plus includes Designer, ten deck slots instead of three, the deck in quick play (opt-in on both sides, never to players under 13), a dated Plus skin each month, full lifetime stats, and a Plus host's card back and felt on every seat of their private room. Members keep every benefit while the switch is off.
- **Why:** D5 launches without a subscription; a subscription needs ongoing value the store reviewers can see, which the monthly skin provides only once its art exists. Building it now behind a switch lets the operator turn it on after the Designer launch without a release.
- **Implies:** the purchase row keeps each subscription's expiry and readers drop it once passed, so a lapsed Plus ends without waiting for a webhook; an equipped Plus skin falls back to the default. Stats are recorded for every player, so joining Plus shows a full history. Quick play custom decks reach only players who said they are 13 or older and switched them on.

## D13. Clubs: picked names, no chat, a weekly league (2026-10-02)

- **Decision:** a club is a Nakama group that only the server creates and joins. Its name is an adjective and a noun from fixed lists plus a number ("Golden Partners 412"), its crest one of the six company icons; there is no description and no club chat. One club per player, 30 members. Season points a player earns (games with other people only) also go to their club's weekly league and to their own part of it; both reset on Monday with the weekly quests. Moving clubs starts the player's part from zero; the old club keeps what they earned.
- **Why:** D4 rules out free text for players under 13, and a typed club name or a club chat would be the first text one player shows another, needing a moderation queue. Picked names and no chat keep clubs open to every age with nothing to review. Tying the league to season points rewards playing with people, which the game needs for its liquidity, and adds no new grind.
- **Implies:** the client's own group calls (create, update, join, add users) and every chat channel join are refused by before hooks, so a modified client cannot get around the rules. If a weekly reward is added later it must be a free cosmetic, never anything sold. If clubs ever get chat, it needs the 13+ gate and moderation from D4 first.

