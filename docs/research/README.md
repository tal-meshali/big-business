# Big Business: research report and recommended plan

*A mobile multiplayer card game built on the mechanics of Startups (Oink Games), with random matchmaking, private rooms, and a premium tier for custom card designs.*

Date: 2026-09-27. Five detailed source reports sit next to this file (01 to 05). This document is the synthesis: what was found, what it means for the product, and a recommended plan. Numbers and claims are cited in the source reports; this file only repeats the ones that drive a decision.

---

## 1. Executive summary

- **The game is a strong base.** Startups is a 3-7 player, 20-minute, hidden-hand majority game rated 7.2 on BoardGameGeek. Reviewers describe "a small, mean decision every turn" and a reveal at the end that flips leaders. That is exactly the "one more hand" tension poker and blackjack apps monetize, without any gambling.
- **The market gap is real.** The only official digital version (Let's Play! Oink Games) caps online play at 4 players, has no random matchmaking, no rooms with friends beyond its own lobby, and no cosmetics. Nobody serves the 5-7 player game or the social-card-game loop.
- **IP is the first decision, not the last.** Mechanics are not copyrightable, but the name "Startups", the six company names, the animal mascots and the art are. Either license from Oink or re-theme completely before any art is produced. This report assumes re-theming under the working title "Big Business".
- **Do not build a casino-looking app.** Poker and blackjack apps get their polish, social loops and monetization right, but their casino framing forces an 18+ rating on Apple, PEGI 18, and Google Play's social-casino disclaimers. Startups is about shares and capital. Frame it as investing, keep the poker-app polish, and the app can ship at 13+ to a much wider audience.
- **Recommended stack:** Godot 4.6 (GDScript) client, Nakama authoritative server (TypeScript match handlers, self-hosted), Firebase for auth/push/analytics, Cloudflare R2 + Images for card art, Sightengine for moderation, RevenueCat for cross-platform purchases. Under $50/month until traction.
- **Recommended business model:** free to play with cosmetic-only monetization. A one-time "Designer" unlock ($4.99-9.99) for custom decks in private rooms, plus a $4.99/month "Plus" subscription that adds monthly skins, no ads, more deck slots and the right to show your deck in public matches. No loot boxes, no virtual currency with hidden pricing.

---

## 2. The game (see `01-startups-game.md`)

**Core loop.** Each player holds 3 cards. On a turn you take one card (from the deck, paying 1 chip onto every card in the market, or from the market, collecting its chips), then play one card (to your tableau face-up, or into the market). Whoever has the most face-up cards of a company holds its Anti-Monopoly chip, which blocks them from taking that company from the market. When the deck runs out, hands are revealed, the majority holder of each company is paid by every minority holder, and chips received flip from value 1 to value 3. Most value wins.

**Why it will hold players.**
- Every deck draw taxes you and subsidises rivals, so trivial turns don't exist.
- Hidden hands mean the final reveal can swing the game. This is the "river card" moment poker apps build their tension around.
- Chip flipping (1 to 3) makes majority swings feel big.
- 20 minutes physical translates to roughly 5-8 minutes online with turn timers, which sits in the mobile sweet spot for stacking several sessions a day.

**Design implications.**
- Reviewers say the first play is confusing and the second play "clicks". A directed interactive tutorial is mandatory, not optional.
- The known exploit (cycling a card between hand and market) needs a rules decision in the engine, and turn timers make stalling tactics moot.
- There is no official 2-player rule. Fill seats with bots when matchmaking is thin and use a dummy-player variant for 2-player private rooms.
- The official app supports only 4 online players. Supporting the full 3-7 range is a differentiator.

**IP.** Re-theme: game name, six company names and mascots, card art, chip art, colour scheme and rule text. Keep: 6 companies with 5/6/7/8/9/10 shares, 10 starting chips, coin seeding, chip flip, majority payout, Anti-Monopoly rule. The alternative, licensing from Oink, is worth one email before art starts, but plan for a no since Oink competes with its own app.

---

## 3. What poker and blackjack apps teach (see `02-card-game-ux.md`)

**Orientation.** Real-money poker (partypoker, 888poker, PokerStars) moved portrait-first from 2019 for one-handed play; legacy social-casino apps (Zynga) still force landscape and get complaints. Every premium casual card game (Marvel Snap, UNO!, Exploding Kittens) is portrait. **Build portrait-first** with opponents in a vertical oval, your seat at 6 o'clock, action bar in the thumb zone. Do not rotate a landscape layout.

**Table layout for 3-7 players.** Hand-authored seat rings per player count, as the open-source poker client in the UX report does. Opponent seats show avatar, chip count, tableau counts per company as small colored pips, and a turn ring. The market row sits in the center with chips rendered on cards. Your 3-card hand fans at the bottom; tap to zoom, drag to play, drop back to cancel (Hearthstone's phone pattern).

**Visual style.** Dark navy/charcoal "modern casino" is the dominant premium look (Marvel Snap's "piano glass" with light-projected buttons is the reference). Green felt survives only as a selectable skin. Cards must be readable at thumbnail size: bold company glyph and share count top-left, one strong color per company, and identity encoded by icon shape too since ~4.5% of players are colorblind.

**Juice.** Chip slide with escalating pitch, card flip with haptic tick, big celebration on the end-of-game payout (Balatro's chip-counting sequence is the model), screen glow when the turn timer runs low (Snap). Every animation must be interruptible; Exploding Kittens 2 is criticized for animations that block input. Offer reduce-motion and vibration toggles.

**Social layer poker apps ship with.** Emotes next to avatars, throwable items, table chat with presets, friend gifting, clubs with leagues. All of these need mute/report/block on day one (Apple 1.2, Play UGC policy).

**Onboarding.** Hearthstone uses six constrained missions; Snap uses a 2-minute scripted battle, then bot matches. Plan: a 3-minute scripted game against bots that forces one decision per concept (draw and pay, take from market, play to tableau, Anti-Monopoly, payout), then bot matches until the first "Play Now".

**Lobby.** One big "Play Now" button; "Create room" produces a 6-character code with share sheet; "Join room" takes a code; friends tab with online status and invites. UNO! Room Mode and Exploding Kittens' room codes are the direct precedents.

**One caution from the blackjack apps.** AbZorba's Blackjack 21 had insurance Yes/No buttons overlapping the emoji button. Keep social affordances out of the decision-button zone.

---

## 4. Keeping players and making money (see `03-engagement-monetization.md`)

**Benchmarks.** Median mobile game: D1 ~22%, D7 ~4%, D30 <1%. Card, board and casino genres have flat D1 but the best long-term curves. Targets for this app: D1 35%, D7 15%, D30 7%, DAU/MAU 20%.

**Retention stack (all precedented, all cosmetic-safe).**
1. Play-gated daily reward: unlocks after N hands, not just login (Zynga's Daily Bonus Vault).
2. Three daily and three weekly quests feeding a free cosmetic track (Hearthstone). Do not inflate grind; Blizzard had to revert a change that did.
3. Monthly ranked season with a free card back for X wins at any rank (Hearthstone's cheapest, most effective hook).
4. Instant rematch and "next table" after every game; visible quest progress after every hand.
5. Clubs with league leaderboards; friend gifting of free currency (UNO!, WSOP).
6. Behavior-triggered push ("your turn", "one more win for your daily reward"), capped and timed to lunchtime rather than morning.

**Monetization.** F2P with IAP is the only model that works for a multiplayer game that needs liquidity; paid-upfront works for single-player (Balatro) only. Social casino ARPDAU runs $0.20-0.80; a cosmetic-only skill game should plan for the low end and win on retention and organic growth instead.

Recommended structure:
| Tier | Price | Contents |
|---|---|---|
| Free | $0 | Full game, all modes, default deck, earnable cosmetics, optional rewarded video for currency |
| Designer (one-time) | $4.99-9.99 | Upload your own card designs, 1-3 deck slots, usable in private rooms |
| Plus (subscription) | $4.99/mo, $29.99/yr | Everything in Designer, more slots, show your deck in public matches, monthly rotating skins, no ads, detailed stats, host-unlocks-table for friends (Board Game Arena's viral trick) |
| A la carte skins | $2.99-9.99 | Curated decks, tables, card backs, priced in real currency |

**Policy constraints that shape this.**
- All digital goods through Apple/Google IAP; restore purchases; subscriptions with real ongoing value.
- No paid loot boxes: Belgium bans them, EU Digital Fairness Act is coming, UK requires disclosure from May 2026.
- Show real-money prices; no countdown "just for you" bundles (Snap gets criticized for these).
- Frame as investing, not gambling, to stay at 13+ on Apple and avoid Google's social-casino disclaimers.

---

## 5. Technical stack (see `04-tech-stack-multiplayer.md`)

**Client: Godot 4.6, GDScript.** Zero licensing, 5-10 MB builds, first-class 2D tween and UI nodes, official Nakama client, and the two most credible card-game studios of the decade (Mega Crit for Slay the Spire 2, Second Dinner for its next game) have moved to it. Mobile export matured in 4.5.2/4.6 with official StoreKit 2 and Play Billing plugins. Use GDScript, not C#, on mobile since C# export is still experimental.

Fallbacks: **Unity 6** if hiring contractors or wanting Snap-grade VFX on day one (Personal tier is free under $200k revenue, Runtime Fee is cancelled). **Flutter** if the team is app developers rather than game developers; Google's I/O FLIP proved a CCG works in plain widgets.

**Server: Nakama, self-hosted.** Authoritative match handlers in TypeScript, built-in matchmaker, friends, groups, chat, leaderboards, storage, and official Godot/Flutter/Unity clients. A 2 vCPU VPS plus Postgres runs it for $20-40/month. Colyseus Cloud ($15/month) is the alternative if the team is TypeScript-native and wants zero ops. Avoid Photon for this game: without Photon Server, a client would shuffle the deck, which breaks hidden information.

**Game state rules (non-negotiable).**
- Server owns the deck, shuffles, and deals. Clients send intents only (`take_from_deck`, `take_from_market{card}`, `play_to_tableau{card}`, `play_to_market{card}`).
- Deterministic reducer with a server-only seeded RNG, append-only action log per match for replays and reconnection.
- Per-player views: opponents receive hand counts, never hand contents.
- Server-side turn timers with a safe auto-play; client timers are cosmetic.
- Bots submit actions through the same intent API; after K missed turns a disconnected seat becomes a bot.
- Private rooms: 6-character code mapped to a Nakama match ID in storage.

**Supporting services.** Firebase Auth (Apple + Google sign-in), FCM push, Analytics, Crashlytics, Remote Config; GameAnalytics alongside for funnels. Cloudflare R2 (no egress fees) + Cloudflare Images for card art; Sightengine for automated moderation; RevenueCat for cross-platform purchase entitlements checked server-side. GitHub Actions + Fastlane for builds to TestFlight and Play internal testing.

**Cost.** Roughly $25-50/month at 1k MAU, $200-300 at 10k, $1,000-1,600 at 100k.

---

## 6. Premium custom card designs (see `05-custom-card-upload.md`)

**UX.** Pick a company slot, pick an image, crop at a locked 5:7 ratio with a safe-zone overlay, add optional text/logo, preview front and back with a 3D flip, see the deck fanned at real in-game scale, save, share to friends. The frame with company glyph and share count stays locked; user art fills only the art window (Marvel Snap and Dulst's pattern), so custom decks stay readable and on-brand.

**Pipeline.** Accept JPEG/PNG/HEIC/WebP up to 10 MB and 4096 px, reject under ~600x840. Master stored at 750x1050 with 375x525 and 188x263 variants as WebP. Content-addressed by SHA-256 so duplicates share storage and moderation verdicts. Deck manifest is sent in room state at lobby time; clients prefetch before "Ready"; 5-second timeout falls back to the default deck with a small badge. A Startups-sized deck (six company designs, ~45 faces plus back) is roughly 1.5 MB. Never let users host images by URL: Tabletop Simulator's dead-link problem is the cautionary tale.

**Moderation and legal (required before launch of this feature).**
- Apple 1.2 and Google Play UGC: automated pre-publish scan, in-app "Report deck", block user (hides their decks), moderation queue, published contact, action within 24 hours.
- Sightengine ($29/month entry) or AWS Rekognition ($1 per 1,000 images) for automated scanning; cost is negligible.
- Register a DMCA agent with the US Copyright Office ($6), publish it, run notice-and-takedown with a repeat-infringer policy. Expect uploads of Pokémon and sports logos.
- Gate uploads at 13+ (16+ in EU) since photos are personal data under COPPA.
- **Custom decks show only in private rooms by default.** Public-match display is a Plus perk and opt-in per viewer. This shrinks moderation exposure and keeps ranked play looking curated.

**AI-generated art.** Ship as a later, credit-based add-on if at all: prompt-only, same moderation pipeline, "AI-generated" badge, report button. Google Play requires a report mechanism for AI output; Apple requires consent before sending personal data to third-party AI; the card-game community reacts badly to AI art, so keep it opt-in and clearly labeled.

---

## 7. Recommended plan

### Phase 0: decisions (1-2 weeks)
1. Email Oink Games about licensing. Proceed with re-theming in parallel; do not wait.
2. Pick the working theme: six fictional companies with distinct color and icon per company, a name that is not "Startups".
3. Confirm stack: Godot + Nakama. Spike a Godot client talking to a local Nakama match in a day to validate.
4. Write the rules spec, including tie-breaking for the Anti-Monopoly chip and a ruling on the hand/market cycling exploit. Verify against the physical rulebook.

### Phase 1: playable core (6-8 weeks)
- Nakama match handler: full rules engine as a pure reducer with unit tests, per-player views, turn timers, bots.
- Godot client: portrait table for 3-7 seats, hand fan, market row, chips, tableau pips, end-of-game payout sequence.
- Quick play (matchmaker + bot fill) and private rooms with codes.
- Guest auth with device ID; link Apple/Google later.
- Internal TestFlight/Play testing with friends. Goal: is a 5-player game fun in under 8 minutes with timers?

### Phase 2: soft launch (6-8 weeks)
- Interactive tutorial; contextual tips in the first three real games.
- Profiles, friends, invites, emotes with mute/report/block.
- Daily reward, daily/weekly quests, free cosmetic track, one ranked season.
- Push notifications, analytics funnels, Crashlytics, Remote Config.
- Two or three curated decks and table skins sold a la carte through RevenueCat.
- Soft launch in two or three small English-speaking markets; measure D1/D7 against the targets above.

### Phase 3: premium and growth (6-8 weeks)
- Designer unlock: upload, crop, template render, private-room display, moderation pipeline, report/block, DMCA agent, age gate.
- Plus subscription: extra slots, public-match display opt-in, monthly skins, no ads, stats, host-unlocks-table.
- Clubs and league leaderboards; friend gifting; spectating.
- Global launch.

### Later
- Deck sharing gallery; AI art credits; landscape toggle; tablet layout; multi-round variant as a room option.

---

## 8. Open questions for you

1. **Licensing or re-theme?** This is the only decision that blocks art production. The plan assumes re-theme.
2. **Team shape.** Godot is the pick for a solo founder or small team on a budget. If you plan to hire contractors quickly, Unity's hiring pool argues for switching before code is written.
3. **Age target.** The plan targets 13+ by avoiding casino framing. If you specifically want a casino aesthetic, expect an 18+ rating and a smaller audience.
4. **Premium shape.** One-time unlock plus subscription is recommended. If you prefer a single subscription only, the Designer tier folds into Plus.

## 9. Research caveats

Many primary sources (BoardGameGeek, Oink Games, App Store and Play Store listings, Sensor Tower, GDC Vault, Google support pages) were blocked by the research sandbox's network policy, so several facts come from search-engine extracts of those pages. Every claim is cited in the source reports; the rules in particular should be verified against the physical rulebook before the engine is written.
