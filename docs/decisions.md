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

