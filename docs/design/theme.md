# Big Business: theme and companies

Working theme: a bright, slightly retro world of six ambitious companies fighting for market dominance. Players are investors collecting shares. Everything is friendly and readable for all ages: no casino imagery, no gambling language.

**Visual direction (decided 2026-09-28): title-deed cards on a board-green table.** The look borrows the language of classic property-trading board games: off-white cards with a black border and a solid colour band naming the company, black text, a pale green playing surface with a darker green rim, and white panels with ink borders. It must not copy any specific board game's logo, mascot, property names or exact board layout.

**Screens (design canvas "Big Business — 3D Table", 2026-09-28, implemented in the Godot client the same day).** Three artboards at 390×844 define the app: the start page, the tutorial and the playable table. The table is seen in perspective: a stadium-shaped felt tilted 32° in a dark green room, with the share supply and the Market lying on it, your Portfolio in small stacks below the Market, the opponents' hands fanned face down along the far edge under their plates, and your own hand held upright in front of the table above a cream bottom bar. The client draws all of this in 2D through one projection (`client/scripts/ui/table_surface.gd`), so cards and coins move on the same tilted plane.

Typography: **Archivo** (ExtraBold and Black) for titles, counts and scores; **Nunito Sans** (Bold and ExtraBold) for everything else. Both are OFL fonts bundled in `client/assets/fonts/`. Sizes in code are the design's CSS px times 720/390.

Buttons and panels are "deed" boxes: white or cream face, 2 px ink border, a rounded corner and a hard offset shadow (no blur). The primary button is yellow `#F2C230`; ghost buttons are cream; the pressed state sinks 2 px into its shadow. The active seat's plate turns `#FFF1C9` with a yellow ring and lifts 3 px. Overlays (season standings, dividend day, the coach) shade the screen with `#08120D` at 64 %.

## Vocabulary

| Concept | In-app word | Never use |
|---|---|---|
| Card | Share | Card (in UI copy), stock (ambiguous) |
| Chip value 1 / value 3 | Capital (bronze coin) / Capital (gold coin, worth 3) | Chip, bet, wager |
| Market row | The Market | Pool, table |
| Face-up cards in front of you | Your Portfolio | Tableau |
| Anti-Monopoly chip | Regulator token | Anti-Monopoly (Oink's term) |
| Draw pile | Share supply | Deck (fine in code, avoid in UI) |
| End-of-game payout | Dividend day | Scoring |
| Match | Round / Game | Hand (poker term) |

## The six companies

Share counts must be 5, 6, 7, 8, 9, 10 (45 shares). Each company has a unique hue **and** a unique icon silhouette, so colorblind players can tell them apart by shape. The share count is printed on every card so a player never has to remember it.

| # | Company | Shares | Sector | Band colour (hex) | Icon silhouette | Personality |
|---|---|---|---|---|---|---|
| 0 | **Sunny Side Solar** | 5 | Energy | Yellow `#F2C230` (ink text on band) | Sun (circle with rays) | Cheerful, scarce, the "small majority" company |
| 1 | **Pinecone Foods** | 6 | Food | Green `#3F9E4F` | Pinecone (tall triangle) | Wholesome, steady |
| 2 | **Tidewater Freight** | 7 | Shipping | Blue `#2E6FD8` | Anchor | Reliable, big volume |
| 3 | **Cogwheel Robotics** | 8 | Tech | Orange `#F07A1E` | Gear (toothed circle) | Busy, ambitious |
| 4 | **Nimbus Air** | 9 | Travel | Violet `#7B4FC6` | Cloud | Glamorous, expensive to hold |
| 5 | **Redline Motors** | 10 | Automotive | Red `#D6262C` | Wheel with lightning bolt | The giant everyone fights over |

Palette: table `#C7DFC9` with rim `#9BBE9F`; card face `#FFFDF6`; panels white; ink `#1C1C1C`; bronze coin `#B8722E`; gold coin `#E2B23A`; coach band orange `#F7941D`; dividend band gold; alerts and the title plate red `#D6262C`. All text is ink on light surfaces, or white on a colour band (ink on the yellow band).

Contrast rule: yellow and orange are the closest pair, so their icons (sun vs gear) are the most different silhouettes, and every band also carries the share count.

## Card face layout (portrait 5:7), title-deed style

```
+----------------------+
| |7   SHARE OF   [ic]| |   colour band with ink border: share count top-left,
| |    FREIGHT        | |   company short name large
|  Tidewater Freight   |   full name, ink, small
|  --------------------|
|  |   ART WINDOW    | |   the only area a custom design may replace
|  --------------------|
|   7 shares issued    |   deed-style footer line
+----------------------+
```

- The band is at the top, so the share count and name stay visible in a fanned hand.
- The art window sits in the body between two thin rules. Custom designs (premium) fill only the art window; the band and footer stay fixed so a custom deck is always readable and never hides game information.
- Default art: flat, playful illustrations per company (a sun with sunglasses, a pinecone in a chef's hat, and so on). One illustration per company; shares of the same company are identical.

## Card back

Off-white with an ink border, a row of six company-colour stripes top and bottom, and "BIG BUSINESS" set in ink. Custom decks may replace the back with any 5:7 image (premium).

## Table

- Felt: board green `#C7DFC9` with a `#9BBE9F` rim and an ink outline, a stadium 380×620 design px, tilted 32° and seen from 900 px, standing in a dark green room (a radial gradient derived from the felt, so the navy and burgundy cosmetic felts get their own rooms). A true "night table" skin is a later cosmetic.
- Zones on the felt are dashed rounded rectangles with small caps labels: THE MARKET (two rows of up to five shares), SUPPLY · n (the face-down stack), YOUR PORTFOLIO (kept shares in stacks by company). A zone glows cream when it is the place to act: the supply while you may draw, the Market and Portfolio while you decide where a selected share goes.
- Your hand: three or four upright shares fanned 7° apart in front of the table. A tappable share carries an orange action ring; the selected one lifts. A Market share of a company whose regulator token you hold is hatched: off limits for you.
- Opponents: face-down fans on an arc along the far edge (1 to 6 seats), each under a white plate: avatar with initial, name with a "bot" or "away" badge, capital, and one colour pip per company held with an R bubble for a regulator token. The active plate is warm with a yellow ring, and a timer arc runs around its avatar.
- Top bar: red BIG BUSINESS plate, whose turn it is, the timer, sound, emotes, leave. Turn changes announce themselves with a dark pill toast.
- Bottom bar: cream, rounded top: your own row (avatar, capital, pips), the prompt in plain words, and the actions (Draw from supply; Keep / Sell to Market / Cancel once a share is selected).
- Panels that interrupt play are deed cards with a coloured title band: orange for the coach, gold for dividend day (ranked rows with name, "n bronze + m gold" and the score), purple for season standings, blue for reconnecting. The lobby title sits on a red band.

## Start page

A hero of the six shares floating over a small felt with coin stacks (the cards bob, and flip when tapped), the red title deed with the tagline, "Your portfolio" (avatar, name, level badge, XP track with streak, daily bonus, season standings, friends, quests, help), then Play now (big yellow), How to play, Create private room, and the room-code row (join by code, or your room's code with Copy). The server address row stays at the bottom for testers.

## Tutorial

The coach shades the screen and cuts a spotlight around the thing being explained (the supply, the Market, your hand and bar, or your row). Rule cards close with "Got it"; guided moves show a hint row with a tapping hand instead ("Tap the glowing supply", "Tap Redline Motors, then Keep") and leave the spotlight interactive, so the learner plays through it. The band shows the step counter with eleven dots.

## Regulator token

A small round token in the company colour with a white "R" and the company icon. Tooltip on first appearance: "You hold the most Tidewater shares. You can't take Tidewater from the Market, but you don't pay onto Tidewater shares when you draw."

## Coins

- Bronze coin: capital 1. Gold coin: capital 3.
- Dividend day flips coins from bronze to gold with a satisfying spin. Coins never show a currency symbol.

## Bots

Named after office archetypes so they read as friendly, not fake people: Intern Ivy, Analyst Avi, Broker Bo, Auditor Ada, CEO Cal, Investor Ines. Bots have a small "bot" badge; no bot is ever presented as a human.
