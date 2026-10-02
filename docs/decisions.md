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

## D10. Designer: art windows and backs, rendered on the device, reviewed before others see it (2026-10-02)

- **Decision:** a custom deck is a card back plus one picture per company that fills the art window on the card face; the frame, company name and share count are always drawn by the client. The device crops and encodes each picture as a WebP at a fixed size (back 250 x 350, window 352 x 184, 64 KB at most); the server checks the header, size and length, stores it once per content hash, and serves it by hash. A picture shows to other players only once it is approved, by the Cloud Vision scan when a key is set or by the operator. Only the host's selected deck shows, only in private rooms. The age question (D4) is asked inside Designer for now.
- **Why:** Nakama's JavaScript runtime cannot decode or resize images, so rendering has to happen on the device, and a fixed template means the server can verify what it stores without decoding it. Keeping the frame in code means a custom deck can never hide which company a card is. Approval before display, private rooms only, and the host's deck only keep the moderation surface small enough for one operator (research 05 section 4).
- **Implies:** the art travels as RPC payloads (about 90 KB), within Nakama's HTTP request limit; the socket message limit is untouched. Refused pictures are deleted, not kept; three strikes end uploads for an account. Plus (more slots, public-match opt-in) builds on the same deck row.
