# Big Business: theme and companies

Working theme: a bright, slightly retro world of six ambitious companies fighting for market dominance. Players are investors collecting shares. Everything is friendly and readable for all ages: no casino imagery, no gambling language.

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

| # | Company | Shares | Sector | Colour (hex) | Icon silhouette | Personality |
|---|---|---|---|---|---|---|
| 0 | **Sunny Side Solar** | 5 | Energy | Yellow `#F5C542` | Sun (circle with rays) | Cheerful, scarce, the "small majority" company |
| 1 | **Pinecone Foods** | 6 | Food | Green `#4CAF6A` | Pinecone (tall triangle) | Wholesome, steady |
| 2 | **Tidewater Freight** | 7 | Shipping | Blue `#3B82F6` | Anchor | Reliable, big volume |
| 3 | **Cogwheel Robotics** | 8 | Tech | Orange `#F4813F` | Gear (toothed circle) | Busy, ambitious |
| 4 | **Nimbus Air** | 9 | Travel | Violet `#8B5CF6` | Cloud | Glamorous, expensive to hold |
| 5 | **Redline Motors** | 10 | Automotive | Red `#E5484D` | Wheel with lightning bolt | The giant everyone fights over |

Contrast rule: all six hues sit on a dark navy table (`#121826`) and on a white card face; the icon is drawn in the company colour with a dark outline so it reads on either. Yellow and orange are the closest pair, so their icons (sun vs gear) are the most different silhouettes.

## Card face layout (portrait 5:7)

```
+--------------------+
| [icon] 7           |   top-left: icon + share count, large, bold
|                    |
|                    |
|      ART WINDOW    |   the only area a custom design may replace
|                    |
|                    |
|  TIDEWATER FREIGHT |   company name band in company colour
+--------------------+
```

- Top-left corner cluster is always visible in a fanned hand.
- Art window is 66% of the card height. Custom designs (premium) fill only the art window; the corner cluster and name band stay fixed so a custom deck is always readable and never hides game information.
- Default art: flat, playful illustrations per company (a sun with sunglasses, a pinecone in a chef's hat, and so on). One illustration per company; shares of the same company are identical.

## Card back

Dark navy with a gold "BB" monogram and a subtle diagonal pattern. Custom decks may replace the back with any 5:7 image (premium).

## Table

- Background: dark navy `#121826` with a soft radial vignette. A green-felt skin is a later cosmetic, not the default.
- Your seat at the bottom. Opponents around a vertical oval.
- Each opponent seat: avatar, name, capital count, six tiny company pips showing shares in their portfolio, and the regulator tokens they hold.
- The Market is a horizontal strip across the middle; coins stack on each share card.
- The share supply sits at the left of the Market with a count.

## Regulator token

A small round token in the company colour with a white "R" and the company icon. Tooltip on first appearance: "You hold the most Tidewater shares. You can't take Tidewater from the Market, but you don't pay onto Tidewater shares when you draw."

## Coins

- Bronze coin: capital 1. Gold coin: capital 3.
- Dividend day flips coins from bronze to gold with a satisfying spin. Coins never show a currency symbol.

## Bots

Named after office archetypes so they read as friendly, not fake people: Intern Ivy, Analyst Avi, Broker Bo, Auditor Ada, CEO Cal, Investor Ines. Bots have a small "bot" badge; no bot is ever presented as a human.
