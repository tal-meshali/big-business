# Tech stack: cross-platform turn-based multiplayer card game (September 2026)

## Summary recommendation (solo founder / small team)

**Client: Godot 4.6 (GDScript) or Unity 6 (C#).** Pick Godot if cost-sensitive and comfortable with a slightly rougher mobile pipeline; pick Unity for the deepest card-game precedent, asset store, and hiring pool. Flutter is the dark horse if the team is app developers rather than game developers.

**Backend: Nakama (self-hosted on a $20-40 VPS, TypeScript/Go match handlers) or Colyseus Cloud (from $15/mo, TypeScript rooms).** Both give authoritative rooms, matchmaking, private room codes, reconnection, and official Unity/Godot/Flutter/JS clients.

**Everything else:** Firebase (Auth, FCM, Analytics, Crashlytics, Remote Config) + Cloudflare R2 + Cloudflare Images + Sightengine for user card art.

---

## 1. Client frameworks

| Framework | Card-game strengths | Animation tooling | Empty-app size | Runtime user images | Notable card games | Verdict |
|---|---|---|---|---|---|---|
| **Unity 6 (C#)** | Most proven CCG engine; uGUI + DOTween is the de-facto card stack; huge asset store | DOTween/PrimeTween, Timeline, UI Toolkit (runtime UI now viable), Spine | ~12-20 MB iOS after stripping ([Unity docs](https://docs.unity3d.com/Manual/iphone-playerSizeOptimization.html)) | `UnityWebRequestTexture` / `Texture2D.LoadImage`, trivial | Hearthstone ([GamesBeat](https://venturebeat.com/games/even-hearthstone-runs-on-unity-and-thats-why-its-already-on-ipad/)), Marvel Snap ([Unity case study](https://unity.com/case-study/marvel-snap)), Legends of Runeterra | Largest hiring pool. Personal is free under $200k revenue/funding; Pro $2,310/seat/yr after a 5% Jan-2026 increase; Runtime Fee fully cancelled ([Unity](https://unity.com/blog/unity-is-canceling-the-runtime-fee), [CG Channel](https://www.cgchannel.com/2024/09/unity-scraps-controversial-runtime-fee-but-raises-prices/)). |
| **Godot 4.6 (GDScript/C#)** | MIT, zero cost, fast iteration, excellent Control/Tween nodes for 2D UI | Built-in Tween, AnimationPlayer, shaders; Spine/Rive via GDExtension | ~5-10 MB APK optimized ([Godot forums](https://godotforums.org/d/21005-extreme-attempts-at-reducing-the-apk-size-of-the-game)) | `Image.load_png_from_buffer` / `ImageTexture`, trivial | Slay the Spire 2 (moved from Unity, [PC Gamer](https://www.pcgamer.com/games/card-games/slay-the-spire-2-ditched-unity-for-open-source-engine-godot-after-2-years-of-development/)); Second Dinner (Marvel Snap) building its next game on Godot ([W4 Games](https://www.w4games.com/blog/w4-games-news-1/second-dinner-studios-becomes-a-strategic-investor-in-w4-games-and-plans-to-build-the-largest-game-in-godot-yet-37)) | Mobile export matured a lot in 4.5.2/4.6: device mirroring, safer iOS export defaults, official StoreKit 2 / Play Billing plugins ([Godot mobile update Apr 2026](https://godotengine.org/article/godot-mobile-update-apr-2026/)). **Use GDScript on mobile**: C# iOS/Android export is still labelled experimental ([Godot](https://godotengine.org/article/platform-state-in-csharp-for-godot-4-2/)). Hiring pool smaller but growing fast. |
| **Flutter (widgets + Rive, or Flame)** | Card games are "app-shaped": lists, decks, profiles, shops. Widgets + implicit animations cover 90%; Flame only needed for a game loop | Rive (state machines), `flame_rive`, Lottie, Impeller renderer | ~15-20 MB typical, ~5 MB minimum | `Image.network` / `Image.memory`, trivial | Google's I/O FLIP CCG built with pure widgets, no engine ([Flutter blog](https://medium.com/flutter/how-its-made-i-o-flip-da9d8184ef57)); Casual Games Toolkit ships a card-game template ([docs](https://docs.flutter.dev/resources/games-toolkit)) | Fastest dev speed for UI-heavy screens, large app-dev hiring pool. Weaker for particle-heavy juice; fine for card flips/slides. |
| **React Native (Expo + Skia + Reanimated 4)** | Same "app-shaped" argument; Skia is a GPU canvas | Reanimated 4 worklets, Skia, Rive RN | ~20-30 MB | Trivial | No well-known card games; the RN "game engine gap" is real ([DEV](https://dev.to/grzott/the-react-native-game-engine-gap-in-2026-rnge-skia-phaser-in-webview-expo-gl-55hp)) | Only if the team is already RN experts. |
| **Cocos Creator** | Strong in Asia for 2D mobile card/casual; TypeScript | Built-in tween, Spine, DragonBones | Small | Trivial | Many Chinese card games | English docs/community weaker; hiring outside Asia thin. |
| **Defold** | Smallest builds (~7-12 MB APK), Lua, free, monthly releases, official Nakama extension ([Defold + Nakama](https://defold.com/2021/03/02/Creating-online-games-using-Nakama-and-Defold/)) | GUI nodes, Spine ext, property tweens | Smallest | Trivial | Used by King; few known card titles | Great engineering, tiny hiring pool, Lua. |
| **Phaser 3 in Capacitor webview** | JS ecosystem; fastest to prototype | Phaser tweens, Spine plugin | ~5 MB shell | Trivial | Casual/HTML5 card games | WebView jank and audio quirks on Android; needs WebView tuning ([Capacitor games guide](https://capacitorjs.com/docs/guides/games)). Fine for MVP, not a long-term bet. |

**Rationale for Godot-first:** zero licensing, small builds, first-class 2D UI/tween system, official GDScript Nakama client, and the two most credible card-game studios of the decade (Mega Crit, Second Dinner) have bet on it. Choose Unity instead if you expect to hire contractors or want Marvel-Snap-grade VFX from day one.

## 2. Multiplayer backend

**Non-negotiable:** the server shuffles, deals, and owns the deck. Clients only send intents (`play_card{id}`), never state.

| Option | Pricing (2026) | Rooms / matchmaking / private codes | Reconnect | Hosting | Client fit |
|---|---|---|---|---|---|
| **Nakama** | OSS Apache-2, self-host free (a 2 vCPU VPS + Postgres ~ $20-40/mo). Heroic Cloud $600-6,000/mo, no CCU limits ([Heroic](https://heroiclabs.com/pricing/), [Crux](https://crux.supercraft.host/blog/nakama-open-source-vs-managed-backend/)) | Authoritative match handlers (Go/TS/Lua) with tick loop, explicit "active turn-based" mode; built-in matchmaker; private room = create match + share match ID or store a 6-char code -> matchId in storage ([docs](https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/)) | Presence join/leave callbacks; client re-joins by matchId, server re-sends state | Self / Heroic Cloud | Official Unity, Godot 4 (GDScript), Dart/Flutter, JS, Defold, .NET ([client libs](https://heroiclabs.com/docs/nakama/client-libraries/)) |
| **Colyseus 0.17** | MIT; Colyseus Cloud from $15/mo flat, no CCU/MAU limits, 32 regions ([Colyseus Cloud](https://colyseus.io/cloud-managed-hosting/)) | TypeScript `Room` classes with auto-synced schema, `filterBy`/lobby, `joinById` for room codes, built-in `matchMaker` | 0.17 added automatic reconnection with `allowReconnection(client, seconds)` ([blog](https://colyseus.io/blog/colyseus-017-is-here/)) | Self / Colyseus Cloud | JS/TS first; official Unity C#, Defold, Haxe; Godot via community/WebSocket; Flutter via community |
| **Photon Realtime/Fusion** | Realtime/PUN: 20 CCU free, 100 CCU $95 one-time; Fusion/Quantum: 100 CCU free, then $125/500 CCU, $250/1k, $500/2k ([Photon](https://www.photonengine.com/fusion/pricing), [Crux](https://crux.supercraft.host/blog/photon-fusion-pricing-2026/)) | Excellent rooms/lobby/custom room names (good for codes) | Good | Photon Cloud only | Unity-centric; **no server-side custom logic without Photon Server/Plugins**, so a master client would shuffle, which violates the authoritative rule. Avoid for hidden-info games. |
| **PlayFab** | Dev mode free (1k players), Standard $99/mo, Premium $1,999/mo + meters ([PlayFab](https://developer.microsoft.com/en-us/games/products/playfab/pricing/)) | Lobby + Matchmaking APIs, Azure Functions (CloudScript) for turn logic | Lobby handles it | Azure | Unity SDK best; Godot/Flutter via REST only. Turn logic in Azure Functions is workable but clunky. |
| **Firebase (Firestore + Cloud Functions)** | Pay-as-you-go; cheap at small scale | No native rooms; you build them; Functions bypass rules so they can be the authority ([Doug Stevenson](https://medium.com/firebase-developers/patterns-for-security-with-firebase-combine-rules-with-cloud-functions-for-more-flexibility-d03cdc975f50)) | Firestore listeners are naturally resumable | GCP | Unity/Flutter SDKs; Godot via REST. OK for slow async games; cold starts and per-doc reads hurt at 100k MAU. |
| **Supabase** | Free tier, Pro $25/mo incl. 5M Realtime msgs, 2M Edge Function invocations ([UI Bakery](https://uibakery.io/blog/supabase-pricing)) | Postgres + Realtime channels; logic in Edge Functions/PG | Channel re-subscribe | Supabase | Same caveats as Firebase; no game-specific matchmaking. |
| **Hathora** | **Shut down May 5 2026** (team joined Fireworks AI; customers moved to Nitrado GameFabric) ([GamesBeat](https://gamesbeat.com/hathora-acquired-will-exit-game-infrastructure-biz-and-hand-over-customers-to-nitrado/)) | n/a | n/a | n/a | Cautionary tale: prefer OSS you can self-host. |
| **Edgegap / Gameye / GameLift** | Edgegap pay-per-second, $1 min ([Edgegap](https://edgegap.com/resources/pricing)); GameLift instance-hours, FlexMatch free with hosting ([AWS](https://aws.amazon.com/gamelift/servers/pricing/flexmatch-pricing/)) | Orchestrate dedicated server containers | Your code | Cloud | Overkill for turn-based; built for session-based dedicated servers. |
| **Rivet** | OSS Apache-2; cloud metered ($0.05/1k awake actor-hrs, sleeping actors free) ([Rivet](https://rivet.dev/cloud/)) | Actors = one durable actor per room; good fit conceptually | State persists | Self / Rivet Cloud | TS-first; young for games. |
| **Unity Multiplayer Services** | Per-service free tiers, pay-as-you-go ([Unity](https://support.unity.com/hc/en-us/articles/30303074122772-How-much-is-the-cost-of-Multiplayer-services)) | Lobby (has join-codes), Matchmaker, Relay | Relay reconnect | Unity Cloud | Unity-only; Relay is peer-hosted, so needs Cloud Code for authority. |
| **Custom Node/Go + WebSockets** | VPS $10-40/mo | You build everything | You build it | Self | Any client. Reasonable only if you'd rather write a room manager than learn Nakama/Colyseus. |

**Pick:** Nakama if you want auth/friends/leaderboards/storage/chat bundled and Godot/Flutter-native clients; Colyseus if your team is TypeScript-first and wants the cheapest managed hosting.

## 3. Turn-based game state design

- **Deterministic reducer on the server:** `state' = reduce(state, action, rng)`. Keep the RNG seeded and server-only; clients never see the seed.
- **Event sourcing:** persist an append-only action log per match (Nakama storage / Postgres JSONB). Replay = re-run the reducer; rejoin = send snapshot + actions since the client's last acked sequence number.
- **Hidden information:** build a per-player view (boardgame.io's `playerView` pattern is the reference: strip `secret` and other players' hands before sending) ([boardgame.io](https://github.com/boardgameio/boardgame.io/blob/main/docs/documentation/secret-state.md)). Send `handCount` for opponents, real cards only to the owner. Deck contents are never serialized to clients.
- **Turn timers:** server-side deadline stored in state; on expiry the match loop auto-plays a safe default and logs it as a system action. Client timers are cosmetic.
- **Bots:** matchmaker waits N seconds, then fills seats with server-side bot agents that submit actions through the same intent API; no special casing in the reducer.
- **Disconnect/rejoin:** keep the seat reserved for a grace period (Colyseus `allowReconnection`, Nakama presence + rejoin by matchId); after K missed turns convert the seat to a bot.
- **Cheat prevention:** validate every intent against `state.currentPlayer`, phase, and legality; rate-limit; ignore client timestamps; sign nothing on the client. Log rejections for detection.

## 4. Auth, social, push, analytics

- **Auth:** Nakama/Colyseus support device-ID guest -> link Apple/Google Sign-In; or Firebase Auth tokens verified server-side. Sign in with Apple is mandatory on iOS if you offer Google.
- **Friends/profiles:** Nakama has friends, groups, chat, leaderboards built in; Colyseus needs a small Postgres/Supabase side-service.
- **Push:** FCM (free) covers Android and wraps APNs for iOS ([Firebase](https://firebase.google.com/products/cloud-messaging)). Send "your turn" from the server's match loop via the FCM HTTP v1 API.
- **Analytics/crash/config:** Firebase Analytics + Crashlytics are free; Remote Config absorbed A/B Testing and moved to usage-based pricing with a free daily-fetch tier from Sept 2026 ([Firebase](https://firebase.google.com/products/remote-config)). GameAnalytics is free and game-specific (funnels, retention) and works alongside Firebase ([Mitzu](https://mitzu.io/post/top-5-gaming-analytics-tools-to-use/)). All have Unity, Flutter, and Godot (via plugins) SDKs.

## 5. User-uploaded card art (infrastructure view)

- **Storage:** Cloudflare R2 ($0.015/GB-mo, **$0 egress**) vs S3 ($0.023/GB + $0.09/GB egress) ([comparison](https://tech-insider.org/cloudflare-r2-vs-s3-vs-backblaze-b2-2026/)). Firebase Storage is convenient but egress-heavy.
- **Processing + CDN:** Cloudflare Images ($5/mo for 100k originals, $1 per 100k delivered; remote transforms from R2 $0.50/1k after 5k free) resizes to fixed variants (e.g. 512x716 WebP) so clients never load arbitrary-size originals ([Cloudflare Images pricing](https://dev.to/nayankyada/cloudflare-images-pricing-2026-storage-limits-delivery-costs-when-to-upgrade-3aof)). Cap uploads at ~5 MB and 4096 px, strip EXIF, re-encode server-side.
- **Moderation:** Sightengine is the best price/accuracy for startups ($29-99/mo entry); Rekognition ~$0.001/img at volume; Google Vision SafeSearch 1k free units/mo; Hive is most accurate but ~$3/1k; OpenAI omni-moderation is free for images+text ([Eden AI](https://www.edenai.co/post/best-image-moderation-apis), [Mixpeek](https://mixpeek.com/curated-lists/best-nsfw-detection-apis)). Pipeline: upload via presigned URL -> worker runs moderation -> mark `approved` -> only approved image IDs may be referenced in a deck. Add a report button and human review queue.
- **Syncing custom decks:** decks are server-side records (deck ID -> list of card IDs -> art URLs). When a room starts, the server sends each player the opponents' card *metadata + CDN URLs* and the client lazily fetches/caches images. Hidden cards still only reveal art when played.

See `05-custom-card-upload.md` for the product and policy side of this feature.

## 6. Rough monthly backend cost

Assumes turn-based play, ~5% peak concurrency, 20 MB art per uploader, 10% of users uploading.

| MAU | Nakama self-host / Colyseus Cloud | Storage + CDN | Moderation | Firebase/FCM/analytics | **Total** |
|---|---|---|---|---|---|
| 1k | $20-40 VPS or $15 Colyseus | ~$5 | free tiers | $0 | **~$25-50** |
| 10k | 2x 4 vCPU + managed Postgres ~ $120-200 | R2 ~$15 + Images ~$15 | ~$30-60 | ~$0-20 | **~$200-300** |
| 100k | 3-4 nodes + HA Postgres + Redis ~ $600-1,000 (or Heroic Cloud $600+, Photon 2k CCU $500) | R2 ~$100 + Images ~$60 | ~$150-300 | ~$50-100 | **~$1,000-1,600** |

Firebase-only would be cheaper at 1k and more expensive at 100k due to per-read pricing; Photon is competitive at 100k but lacks server authority.

## 7. CI/CD

- **Godot/Unity/Flutter:** GitHub Actions (macOS runners now $0.062/min; a 20-min iOS build ~ $1.24 ([GitHub changelog](https://github.blog/changelog/2025-12-16-coming-soon-simpler-pricing-and-a-better-experience-for-github-actions/))) + **Fastlane** (`match` for signing, `pilot` for TestFlight, `supply` for Play internal testing). Godot builds are scriptable headless; Unity via GameCI images.
- **Codemagic:** free tier, Teams $35/seat/mo, Unity/Flutter/Godot preinstalled, cheaper macOS minutes than Unity Cloud Build ([Codemagic](https://docs.codemagic.io/billing/pricing/)).
- **Unity Build Automation:** pay-as-you-go beyond free tier since Mar 2026 ([Unity](https://support.unity.com/hc/en-us/articles/34748492914964-Understanding-New-Unity-DevOps-charges-starting-from-Mar-1-2026)).
- **EAS (only for RN):** free 15+15 builds/mo, Production $199/mo ([Expo](https://docs.expo.dev/billing/usage-based-pricing/)).
- Distribute via TestFlight (external testers need review) and Play Console internal testing (instant, up to 100 testers); automate both from the same pipeline on tagged commits.

## Final stack

Godot 4.6 (GDScript) -> Nakama (self-hosted, TypeScript match handlers, Postgres) -> Firebase Auth/FCM/Analytics/Crashlytics/Remote Config -> Cloudflare R2 + Images + Sightengine -> GitHub Actions + Fastlane. Expect <$50/mo until traction, ~$250/mo at 10k MAU, ~$1.3k/mo at 100k MAU. Swap Godot -> Unity if VFX ambition or hiring dominates; swap Nakama -> Colyseus Cloud if the team is TypeScript-native and wants zero ops.
