# Mobile card game UI/UX: poker, blackjack, and premium card games

Sourcing note: many primary pages (Pokerfuse, Medium, Behance, GDC Vault, App Store/Play Store) were blocked during research; findings come from search extracts of those pages plus a few fully fetched sources. Unverified items are flagged.

## 1. App-by-app UI patterns

**Zynga Poker (Zynga/Take-Two)**
- Landscape table historically; users report needing rotation-control apps to stop it forcing landscape ([XDA](https://xdaforums.com/t/zynga-poker-running-in-multi-window-mode.2483021/)). 9-seat and 5-seat tables; hero at 6 o'clock, community cards center, pot above them ([App Store](https://apps.apple.com/us/app/zynga-poker-texas-holdem/id354902315)).
- Lobby "remembers how you like to play"; buddy gifting; VIP tiers; many modes ([Google Play](https://play.google.com/store/apps/details?id=com.zynga.livepoker&hl=en_US)).

**WSOP (Playtika)**
- Emoji menu; chosen emoji appears next to avatar for all; throwable items (eggs) with animations; 32+ avatars; chip gifts from friends; added a Blackjack mode ([Playtika news](https://news.playtika.com/2025-12-04-World-Series-of-Poker-R-Mobile-Game-Announces-Integration-to-Feature-NFL-Collectibles,-Team-Challenges-and-Exclusive-Rewards-for-a-Limited-Time), [PokerNews review](https://www.pokernews.com/free-online-games/play-wsop/)). Orientation not confirmed from sources; social-casino poker apps remain landscape at the table as far as could be determined.

**PokerStars mobile**
- Added portrait tables that switch between portrait and landscape seamlessly, explicitly for one-handed play ([Poker Industry PRO](https://pokerindustrypro.com/news/article/215907-pokerstars-launches-new-portrait-tables-mobile), [Cardmates](https://cardmates.org/pokerstars_adds_portrait_mode_to_its_mobile_app)). UX write-up: [Lackabane](https://lackabane.com/pokerstars-mobile-app-experience-design).

**partypoker / 888poker (real-money benchmarks)**
- partypoker rebuilt tables portrait-first (2019-2020): buttons and bet slider repositioned for thumb reach; hand replayer redesigned for portrait ([Pokerfuse](https://pokerfuse.com/news/poker-room-news/211022-exclusive-partypokers-new-mobile-app-switches-portrait-mode/), [F5 Poker](https://f5poker.com/poker-news/2019/11/25/partypokers-new-mobile-app-first-look-portrait-table-/)). Its fast-fold app used swipe gestures: swipe cards away to fold, swipe chips in to bet ([Pokerfuse 2014](https://pokerfuse.com/news/media-and-software/2014-07-21-partypoker-unveils-swipe-friendly-fast-fold-mobile-app/)).
- 888poker: portrait lobby as a vertically scrolling grid, pre-selected stakes filters ([Poker Industry PRO](https://pokerindustrypro.com/news/article/211623-888-overhauls-android-mobile-experience-portrait-design)).

**Governor of Poker 3 (Youda)**
- Western-saloon theme; on-table hand-rank highlighting; quick tutorials; emote bubbles, voice lines, animated table props on big wins; full-body avatar customization ([Google Play](https://play.google.com/store/apps/details?id=com.youdagames.gop3multiplayer&hl=en_US&gl=US)).

**Blackjack 21 (AbZorba) and Blackjackist (KamaGames)**
- Blackjackist: 3D motion-captured dealer, multiplayer seats, chat + emojis, side bets, tournaments ([Google Play](https://play.google.com/store/apps/details?id=com.kamagames.blackjack&hl=en)).
- AbZorba's redesign was "minimalistic"; a review flags a real UX bug: insurance Yes/No buttons overlapping the emoji button ([App Store](https://apps.apple.com/us/app/blackjack-21-live-casino-game/id560501166)). Lesson: keep chat/emote affordances out of the decision-button zone.

**Hearthstone (phone)**
- Phone UI was "almost a complete overhaul": hand moved to the side; tap the hand once to zoom and read; drag to play, drop back on hand zone to cancel ([Behance study](https://www.behance.net/gallery/25695693/Hearthstone-UI)). GDC 2015 talk: "our game is UI," flavor over efficiency, physical board-as-toy ([GDC Vault](https://gdcvault.com/play/1022036/Hearthstone-How-to-Create-an), [YouTube](https://www.youtube.com/watch?v=axkPXCNjOh8)).
- Tutorial: six heavily directed missions with limited actions, then contextual tips on each new screen and in the first real match ([Hearthstone wiki](https://hearthstone.wiki.gg/wiki/Tutorial)).

**Marvel Snap (Second Dinner)**
- Portrait, 3 locations, 6 turns; "cards always take precedence in visual hierarchy"; dark "piano glass" UI with holographic light buttons; "frame break" art; turn timer is a bar on the End Turn button, screen glows red when time is short ([Medium case study](https://medium.com/design-bootcamp/marvels-snap-ui-ux-case-study-9f727d8f3875), [Unity case study](https://unity.com/case-study/marvel-snap), [Snap help center](https://marvelsnap.helpshift.com/hc/en/3-marvel-snap/faq/46-how-long-do-i-have-to-take-my-turn/?p=android)).
- Snap triggers a light show + haptics; per-card VFX/SFX/haptics; retreat labeled "Escaped!" to remove loss framing ([Apple Behind the Design](https://developer.apple.com/news/?id=sosm2p7q), [XDA on haptics](https://www.xda-developers.com/marvel-snap-mobile-game-haptics/)).

**Balatro mobile**
- Landscape only on iOS (a common complaint); touch drag/tap redesigned; haptics; High Contrast Cards option; toggles for vibration, screen shake, reduced motion, game speed ([Engadget](https://www.engadget.com/gaming/balatro-is-an-almost-perfect-mobile-port-163050971.html), [Family Gaming DB](https://www.familygamingdatabase.com/accessibility/Balatro)). Community portrait mod: stats/action buttons anchored top, uniform large buttons, left/right-handed shift, swipe-to-play ([GitHub mod](https://github.com/KtourzaJeremy/balatro-portrait-mobile)). Juice breakdown: chip counting, escalating pitch, screen shake ([Blake Crosley](https://blakecrosley.com/guides/design/balatro)).

**UNO! Mobile (Mattel163)**
- Portrait; tap-to-play; 3-minute matches; Quick Play, Room Mode (custom rules, invites), 2v2; preset phrases, emoticons, throwable eggs/gifts ([letsplayuno modes](https://www.letsplayuno.com/support/modes.html), [App Store](https://apps.apple.com/us/app/uno/id1344700142)).

**Exploding Kittens**
- 2-5 players; host gets a room code shareable via iMessage/Messenger; big animation when a card is stolen; EK2 reviewers report sluggish animations that block input ([App Store](https://apps.apple.com/us/app/exploding-kittens-2/id6478287619), [TouchArcade](https://toucharcade.com/2016/03/16/exploding-kittens-finally-has-online-multiplayer-including-private-games/)). Lesson: animations must never block input.

**Board Game Arena**
- 5-tab app (Play, Games, Friends, Notifications, Profile); private + public tables; lobby surfaces tables by friend activity; mobile UI criticized as cramped for card-heavy games ([Google Play](https://play.google.com/store/apps/details?id=com.boardgamearena.bgaapp&hl=en_US), [BGA mobile doc](http://en.boardgamearena.com/doc/Your_game_mobile_version)). Web card-game clones use room-code join ([PlayingCards.io](https://playingcards.io/)).

## 2. Portrait vs landscape for 3-7 players

- Trend since 2019: real-money poker (partypoker, 888, PokerStars) moved to portrait-first for one-handed play; one industry piece cites 63% of poker sessions being one-handed ([SparkTime](https://sparktime.co.uk/developing-mobile-first-poker-apps/)). Legacy social-casino apps (Zynga) still force landscape. Every premium casual card game (Snap, UNO, Exploding Kittens) is portrait.
- Concrete portrait recipe from an open-source poker client: native portrait stage (850x1600), hand-authored seat rings for 2/4/6/9, hero alone at 6 o'clock, one 44px header row, action bar as an on-turn-only safe-area overlay ([block52 issue #632](https://github.com/block52/ui/issues/632)). Do not rotate a landscape stage; build a real portrait layout.
- **Recommendation:** portrait-first with up to 6 opponents arranged in a vertical oval; landscape optional later (PokerStars-style toggle), never primary.

## 3. Visual style, readability, juice

- Style: dark navy/charcoal "modern casino" is dominant; green felt survives as a selectable skin. Snap's dark glass + light-projected buttons is the premium reference ([Yanina Games](https://yaninagames.com/blog/the-impact-on-ui-ux-design-on-mobile-poker-app-interfaces/)).
- Cards: jumbo-index faces; online poker uses four-color decks for small screens ([Wikipedia](https://en.wikipedia.org/wiki/Four-color_deck)). Put key values top-left at high contrast; ~4.5% of players are colorblind so encode identity by shape/icon, not just color ([Medium: 5 lessons](https://medium.com/@acbassettone/5-ux-ui-lessons-from-designing-a-card-game-b689d3f3187)). Slay the Spire iOS shows the failure mode: fan edges clip text and the finger occludes what you drag ([jlericson](https://jlericson.com/2021/03/04/slay_the_spire_ios.html)).
- Type: minimum ~12-16px body; bold numerals for chip counts ([Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/use-an-easily-readable-default-font-size/)).
- Juice: tweening, squash/stretch, particles, screen shake, layered SFX ("Juice it or lose it", [GDC Vault](https://www.gdcvault.com/play/1016487/Juice-It-or-Lose)). Pair audio + haptics via Core Haptics; honor reduce-motion/vibration toggles as Balatro does ([Apple HIG](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)).

## 4. Onboarding

- Directed interactive tutorial with constrained actions (Hearthstone 6 missions; Snap: 2-minute scripted battle, then bot matches) ([Marvel Snap Zone](https://marvelsnapzone.com/marvel-snap-beginners-guide/)). Governor of Poker highlights hand rankings live on the table. Aim for value in under 5 minutes ([Userpilot](https://userpilot.com/blog/onboarding-ux-examples/)).

## 5. Lobby and matchmaking

- Patterns: single "Play Now" primary CTA; Room Mode with shareable code (UNO, Exploding Kittens, PlayingCards.io); table-list grid with filters and remembered preferences (888, Zynga); friends tab with gifting; team option (UNO).

## 6. Tools and pipeline

- Figma exports 1x/2x/3x PNG or SVG; Figma-to-Unity bridges exist ([UnityFigmaBridge](https://github.com/simonoliver/UnityFigmaBridge), [FigmaToUnity](https://github.com/TrackMan/Unity.Package.FigmaToUnity)).
- Card sprites at 256x384 / 512x768 / 1024x1536; sprite atlases with half-scale variants for low-end devices ([I Love Sprites](https://ilovesprites.com/blog/unity-sprite-atlas-mobile-games)).
- Animation: Rive for interactive state-machine UI, Lottie for non-interactive motion, Spine for skeletal avatars ([Motion the Agency](https://www.motiontheagency.com/blog/lottie-vs-rive)). Reference hand-fan/drag/drop implementation: [UiCard](https://github.com/ycarowr/UiCard).

## 7. Talks and case studies

- Hearthstone: How to Create an Immersive UI (GDC 2015) ([Vault](https://gdcvault.com/play/1022036/Hearthstone-How-to-Create-an)); Juice It or Lose It (GDC Europe 2012); Marvel Snap UI/UX case study ([Medium](https://medium.com/design-bootcamp/marvels-snap-ui-ux-case-study-9f727d8f3875)); Fairtravel Battle card UI ([GDKeys](https://gdkeys.com/the-card-games-ui-design-of-fairtravel-battle/)); Game UI Database entries for [Snap](https://www.gameuidatabase.com/gameData.php?id=1785), [Hearthstone](https://www.gameuidatabase.com/gameData.php?id=628), [Balatro](https://www.gameuidatabase.com/gameData.php?id=1935); Squeezing more juice ([Game Developer](https://www.gamedeveloper.com/design/squeezing-more-juice-out-of-your-game-design-)).
