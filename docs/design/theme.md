# Big Business: theme and companies

Working theme: a bright, slightly retro world of six ambitious companies fighting for market dominance. Players are investors collecting shares. Everything is friendly and readable for all ages: no casino imagery, no gambling language.

**Visual direction (decided 2026-09-28): title-deed cards on a board-green table.** The look borrows the language of classic property-trading board games: off-white cards with a black border and a solid colour band naming the company, black text, a pale green playing surface with a darker green rim, and white panels with ink borders. It must not copy any specific board game's logo, mascot, property names or exact board layout.

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

- Background: board green `#C7DFC9` with a darker green rim. A dark "night table" skin is a later cosmetic, not the default.
- Your seat at the bottom. Opponents around a vertical oval, each on a white panel with an ink border; the active seat gets a warm highlight and a timer arc.
- Each seat: avatar, name, capital count, company-colour pips showing shares in the portfolio (drawn like small deed bands), and regulator tokens.
- The Market is a horizontal strip across the middle; coins stack on each share card.
- The share supply sits at the left of the Market with a count.
- Panels that interrupt play (tutorial coach, dividend day) are white deed-style cards with a coloured title band: orange for the coach, gold for dividend day. The lobby title sits on a red band.

## Regulator token

A small round token in the company colour with a white "R" and the company icon. Tooltip on first appearance: "You hold the most Tidewater shares. You can't take Tidewater from the Market, but you don't pay onto Tidewater shares when you draw."

## Coins

- Bronze coin: capital 1. Gold coin: capital 3.
- Dividend day flips coins from bronze to gold with a satisfying spin. Coins never show a currency symbol.

## Bots

Named after office archetypes so they read as friendly, not fake people: Intern Ivy, Analyst Avi, Broker Bo, Auditor Ada, CEO Cal, Investor Ines. Bots have a small "bot" badge; no bot is ever presented as a human.
