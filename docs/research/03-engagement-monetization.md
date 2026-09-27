# Retention, social, monetization and store policy for mobile card games

Method note: most primary fetch targets (GameAnalytics, Sensor Tower, AppMagic, PocketGamer, Google support) were blocked during research, so figures come from search-result summaries of those sources. Third-party revenue numbers are estimates.

## 1. Retention loops and benchmarks

**Benchmarks (2025-26)**
- GameAnalytics 2025/2026 (11,600 games, 1.48B MAU): median D1 ~22%, D7 just under 4%, D30 ~0.7-0.8%. Top 25% ~31-33% D1 on iOS, ~7-8% D7. Top 1%: 64-68% D1, 13-15% D30. Median session ~3.1-3.5 min, ~3.8 sessions/day. GameAnalytics singles out card, board, casino and puzzle as the best genres for medium/long-term retention: "unremarkable" D1 but stable long-term curves driven by familiarity and habit. [GameAnalytics 2026](https://www.gameanalytics.com/reports/2026-mobile-pc-gaming-benchmarks), [2025](https://www.gameanalytics.com/reports/2025-mobile-gaming-benchmarks), [GGA KPI roundup](https://gamegrowthadvisor.com/blog/2026-03-17-mobile-game-kpis-benchmarks-2026/)
- Cross-genre averages cited by Segwise: D1 25-33%, D7 6-14%, D30 1-7%; casino holds up well at D30. [Segwise](https://segwise.ai/blog/mobile-gaming-app-user-retention-strategies)
- Practical targets for a card game: D1 30-40%, D7 10-20%, D30 5-10% (top-quartile territory). [Playio](https://blog.playio.co/d1-d7-d30-retention-benchmarks-2026)
- Marvel Snap: 20.2% DAU/MAU and ~$6.78 revenue per download. [Udonis](https://www.blog.udonis.co/statistics/marvel-snap), [Snap deconstruction](https://medium.com/@shenshenlove/marvel-snap-deconstructed-can-player-value-and-monetization-co-exist-5e1f50d994ae)

**Mechanics that work in card games**
- Daily login + streaks: Zynga Poker gives a 7-10 day escalating daily bonus that resets on a missed day, plus a once-daily "Daily Bonus Vault" earned by playing N hands (a play-gated, not just login-gated, reward). [Zynga Poker](https://play.google.com/store/apps/details?id=com.zynga.livepoker&hl=en), [Zynga help](https://zyngasupport.helpshift.com/hc/en/27-zynga-poker/faq/19523-what-are-rose-s-rewards/)
- Daily/weekly quests feeding a rewards track: Hearthstone dailies reset at midnight, weeklies on Monday. Blizzard had to revert a weekly-quest change that made them ~3x harder for ~20% more reward: players punish grind inflation. [Blizzard](https://news.blizzard.com/en-gb/article/23585675/rewards-track-update-coming-soon), [HS Top Decks](https://www.hearthstonetopdecks.com/hearthstone-progression-update-weekly-quest-revert-improved-rewards-track-tavern-brawl-card-packs/)
- Clash Royale Daily Tasks: log in + win 3 matches yields bounded, non-purchasable random rewards. [Supercell](https://supercell.com/en/games/clashroyale/blog/release-notes/game-update-lucky-drops/)
- Seasons/passes: Hearthstone Tavern Pass $20, paid track is cosmetic-only plus XP boost. Marvel Snap monthly pass $9.99; "Super Premium" tier rose from $14.99 to $19.99 in Jan 2025. Clash Royale Diamond Pass ~$11.99; Supercell added regional pricing in 100+ countries. [GINX](https://www.ginx.tv/en/hearthstone/hearthstone-tavern-pass-explained-free-paid-reward-track-cost-rewards-xp-boost-and-more), [Snap.fan](https://snap.fan/news/card-monetization-marvel-snap/), [Sportskeeda](https://www.sportskeeda.com/mobile-games/clash-royale-season-72-pass-royale-price-rewards-explored), [Supercell regional pricing](https://supercell.com/en/news/clash-royale-regional-pricing-global/)
- Battle-pass conversion: well-timed passes convert 15-20%; 26% of US players 8+ have bought a season/battle pass (ESA 2026). [Kevuru](https://kevurugames.com/blog/game-monetization-statistics-in-app-purchases-ads-and-premium-models/), [Bruin](https://getbruin.com/use-cases/mobile-gaming/battle-pass-renewal-rate-season-over-season/)
- Ranked/leagues: Hearthstone gives a unique monthly card back for 5 ranked wins at any rank, a cheap, collectible retention hook. Zynga Poker runs "Poker Seasons" and club leagues; WSOP has a 7-level loyalty ladder and tiered Clubs. [Blizzard Watch](https://blizzardwatch.com/2020/12/04/how-to-get-hearthstone-monthly-card-back/), [PokerNews WSOP](https://www.pokernews.com/free-online-games/play-wsop/)
- Push: behavior-triggered pushes ("one more win to claim your daily reward"), capped frequency; one game moved its daily-reward push from morning to lunchtime and lifted D7 retention 18%. [PushEngage](https://www.pushengage.com/push-notifications-game-retention/), [OneSignal](https://onesignal.com/blog/push-notifications-messaging-for-game-developers/)
- "One more hand": short match length (Snap ~3 min) + immediate rematch/queue + visible progress on quest/track after every hand keeps sessions in the 3-5 min sweet spot while stacking multiple sessions per day.

## 2. Social features (precedents)

- Friends + free gifting: UNO! Mobile lets friends send free coins daily; Clubs give regular groups a place to schedule play; Room Mode = private rooms with custom house rules; 2v2 co-op mode. [UNO modes](https://www.letsplayuno.com/support/modes.html), [UNO Room Mode](https://unogame.fandom.com/wiki/Room_Mode)
- Poker: table chat, table gifts to buddies, clubs with league competition (Zynga, WSOP). [WSOP App Store](https://apps.apple.com/us/app/wsop-poker-texas-holdem-game/id719525810)
- Hearthstone: Friendly Challenge (counts for quests), spectate friends (also quest-linked). [HS wiki](https://hearthstone.wiki.gg/wiki/Gameplay)
- Board Game Arena: only one Premium member per table is needed to unlock premium games for everyone; groups, tournaments. [BGA premium](https://en.boardgamearena.com/premium)
- Design takeaway: gifting and "host unlocks the table" mechanics turn one payer into a viral loop; chat/emotes must ship with mute/report/block (see section 5).

## 3. Monetization models and benchmarks

- Market size: casino card games ~$784M revenue (-3% YoY), 412M downloads (AppMagic 2025). [AppMagic](https://appmagic.rocks/research/casual-report-2025)
- Social casino ARPDAU $0.20-0.80+ (top decile $0.65-1.10); US payer conversion 9-10% vs 6-8% global. Ads-only casual ARPDAU is $0.01-0.05; hybrid-casual $0.15-0.50. [Juego](https://www.juegostudio.com/blog/arpdau-benchmarks-by-game-genre), [DoubleDown](https://ir.doubledowninteractive.com/news-releases/news-release-details/doubledown-interactive-third-quarter-2025-revenue-rises-155-and), [Liftoff 2025](https://liftoff.ai/2025-casual-gaming-apps-report/)
- Poker apps: WSOP ~$1.2-1.4M/week US; Zynga Poker ~$400-577K/week US (Sensor Tower); chip sales >70% of Zynga Poker revenue. [Sensor Tower Q1 2025](https://sensortower.com/blog/2025-q1-unified-top-5-poker%20games-revenue-us-64bd738ee1714cfff1737dd3), [Stash](https://www.stash.gg/blog/zynga-store)
- Premium one-time: Balatro at $9.99, no IAP/ads, ~3.1M mobile downloads and ~$21.3M mobile revenue; premium mobile releases up 77% in 2025. [Pocket Tactics](https://www.pockettactics.com/premium-mobile-games-increase), [PocketGamer.biz](https://www.pocketgamer.biz/balatro-nears-44m-on-mobile-amid-a-sudden-spending-surge/)
- Subscription: BGA Premium ~$5/month, $36-42/year. [BGA forum](https://forum.boardgamearena.com/viewtopic.php?p=141374&lang=en), [thehobby.us](https://thehobby.us/how-much-is-board-game-arena/)
- What works: for a multiplayer skill card game, F2P + cosmetic pass/subscription + optional rewarded video beats paid-upfront (network effects need scale); premium upfront works only for single-player (Balatro).

## 4. Cosmetic-only premium precedents

- Hearthstone: full hero skin $10 / lite $7; card backs 500-600 gold; 94 card backs made buyable for gold in patch 20.4; paid Tavern Pass track is strictly cosmetic. [HS wiki skins](https://hearthstone.wiki.gg/wiki/Hero_skin), [Out of Games](https://outof.games/news/3210-94-card-backs-and-11-hero-skins-in-hearthstone-will-be-purchasable-for-gold-in-patch-204-this-week/)
- Marvel Snap: variants 700 gold (~$10) rising to 1,200; bundles $9.99-19.99+; "just for you" and weekly rotating offers criticized as pressure tactics. [TheGamer](https://www.thegamer.com/marvel-snap-microtransactions-gold-expensive-whales/), [Snap Zone bundles](https://marvelsnapzone.com/marvel-snap-bundle-value-and-comparison-chart/)
- UNO! Mobile: gems buy themed decks/card backs; dozens of themed decks. [Mattel163 store](https://store.mattel163.com/uno)
- Tabletop Simulator: custom decks are user-uploaded spritesheets, pure UGC, no store. [TTS KB](https://kb.tabletopsimulator.com/custom-content/custom-deck/)
- BGA: premium = access/features, not cosmetics; one subscriber unlocks the table for friends.
- "Done well" pattern: (a) zero gameplay effect, visible to opponents (status), (b) a free earnable path for some cosmetics so premium feels optional, (c) subscription bundles rotating monthly cosmetics + convenience (no ads, private room perks, stats) at $4.99-9.99/mo with a ~50% annual discount, (d) all prices shown in real currency.

## 5. Apple / Google policy constraints

- Apple 3.1.1: all digital unlocks (subscriptions, currencies, cosmetics) must use IAP; purchased currency may not expire; restore mechanism required; loot-box odds must be disclosed before purchase. 3.1.2: auto-renew subs must give ongoing value, min 7 days, work on all devices. 5.3: real-money gaming needs licences and geo-restriction. [Apple guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple 1.2 UGC (chat, custom card art, names): must have content filtering, report mechanism with timely response, block abusive users, published contact info. [Apple guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple age ratings (new tiers since July 2025; questionnaire due Jan 31 2026): infrequent simulated gambling = 13+, frequent simulated gambling = 18+. A poker/blackjack-styled game will likely land at 18+ under "frequent". [Apple age ratings](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/), [Apple news](https://developer.apple.com/news/?id=ks775ehf)
- Google Play: social casino = "simulated gambling-style games where there is no opportunity to win something of value"; must disclaim no real-money gambling, state adult-only intent, not target minors; loot-box odds disclosure required. UGC policy: terms acceptance before posting, in-app report + block, ongoing moderation. [Play RMG policy](https://support.google.com/googleplay/android-developer/answer/9877032?hl=en), [Play UGC policy](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en), [Fenwick](https://www.fenwick.com/insights/publications/google-play-now-requires-disclosure-of-loot-box-odds)
- IARC/PEGI: simulated gambling = PEGI 18 since 2020. Australia (Sept 2024): loot boxes = M (15+), simulated gambling = R18+. [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC10049760/), [AGB](https://agbrief.com/news/australia/20/09/2024/australia-tightens-regulations-on-loot-boxes-and-gambling-features-in-video-games/)

**Implication for this project:** Startups is a stock-investing game with "capital chips", not a betting game. Present it as investing/shares, avoid casino framing (no "bet", no poker-chip iconography, no "casino" in store copy) and the app can sit at 13+ / PEGI 12 with a far wider audience than a poker clone. Borrow poker apps' polish and social loops, not their casino theme.

## 6. Anti-patterns and regulation to avoid

- Paid loot boxes: Belgium treats them as illegal gambling; Antwerp Enterprise Court (16 Jan 2025) held Apple liable for hosting Top War loot boxes. Netherlands is pushing an EU ban. EU Digital Fairness Act proposal expected Q3 2026, may ban loot boxes / require parental consent for minors. UK ASA: from 26 May 2026 loot-box presence must be disclosed in ads and store listings. [Taylor Wessing](https://www.taylorwessing.com/en/insights-and-events/insights/2025/03/an-iphone-a-gambling-problem-and-the-loot-box-debate), [Siege](https://siege.gg/news/several-eu-countries-have-introduced-stricter-regulations-on-loot-boxes-in-games-in-2025), [DFA tracker](https://digitalfairnessact.com/), [ASA](https://www.asa.org.uk/resource/enforcement-notice-disclosure-of-loot-boxes-in-app-stores.html)
- EU CPC key principles (Mar 2025): show real-money price next to virtual-currency price; no bundling that obscures cost; honor 14-day withdrawal on unused currency; no time-pressure offers or direct appeals to children. [Gleiss Lutz](https://www.gleisslutz.com/en/know-how/new-guidelines-game-currencies-digital-consumer-protection-and-expanding-taboo-dark-patterns), [EC press release](https://ec.europa.eu/commission/presscorner/api/files/document/print/en/ip_25_831/IP_25_831_EN.pdf)
- Concrete avoid-list: paid randomized cosmetics; virtual currency with odd denominations that hide price; countdown "just for you" bundles; coercive streak-loss punishment; ads interrupting a hand; premium gating anything competitive; unmoderated chat/custom art.

## Recommendations

1. Ship F2P with rewarded video optional; premium subscription $4.99/mo, ~$29.99/yr (rotating monthly deck/back/table skins, no ads, private rooms with custom rules, host-unlocks-table like BGA, detailed stats, custom card upload). Sell individual skins a la carte at $2.99-9.99 in real currency, no loot boxes.
2. Retention stack: play-gated daily reward (N hands), 3-5 min matches with instant rematch, daily (3) + weekly (3) quests feeding a free cosmetic track, monthly ranked season with a free card back for X wins, clubs with league leaderboards, friend gifting of free currency.
3. Design for 13+ on Apple/Play by avoiding chips/betting framing.
4. Build report/block/mute/filter and a moderation queue before launching chat or custom card art.
5. Target D1 >= 35%, D7 >= 15%, D30 >= 7%, DAU/MAU >= 20%, pass/sub conversion 5-15%.
