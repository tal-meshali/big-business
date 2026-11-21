# Big Business: theme and companies

Working theme: a bright, slightly retro world of six ambitious companies fighting for market dominance. Players are investors collecting shares. Everything is friendly and readable for all ages: no casino imagery, no gambling language.

**Visual direction (decided 2026-09-28): title-deed cards on a board-green table.** The look borrows the language of classic property-trading board games: off-white cards with a black border and a solid colour band naming the company, black text, a pale green playing surface with a darker green rim, and white panels with ink borders. It must not copy any specific board game's logo, mascot, property names or exact board layout.

**Game finish (decided 2026-11-15): "After-hours trading floor".** Research on Clash Royale, Brawl Stars, casual hits and Balatro (direction page: https://claude.ai/artifact/4vBjfqE9DCKq12jtw6XrrD) gave the app the finish of a top mobile game around the unchanged cards:

- Lobby room: royal purple glow (`UiTheme.NIGHT`, `ROYAL`, `ROYAL_GLOW`) with slow gold rays and rising sparkles (`LobbyBackdrop`). The table room still follows the picked felt.
- Buttons (`GlossBox`): a thick ink outline (`#1A1238`), a dark lip under the face, three toon-shaded bands and a white streak; pressed, the face sinks into the lip and the button squashes and springs back (`UiTheme.juice`). Labels are white Archivo Black with an ink outline. Colours by role: gold `#FFC83D` for the one main action per screen, violet `#6A4CF0` for the rest, mint `#26C96F` for rewards, red `#FF3B55` for danger and badges, cream for quiet actions (Close, Skip).
- Wordmark (`LogoTitle`): two-tone gold face, ink outline, brown extrusion, tilted -3 degrees, with a glint every 4 s. The same drawing slams in as "YOUR TURN" at the table.
- Lobby HUD: avatar with a level diamond, name over the XP bar, streak flame, season trophy and the daily gift (wiggles with a red "!" while a bonus waits). The PLAY button breathes and has a light sweep. A dock along the bottom edge holds Friends, Quests (red badge = quests ready to claim), Shop, Clubs and More, as drawn icon tiles (`IconTile`, `GameIcons`).
- Motion is short (0.06 to 0.3 s) and always tied to something that happened or something waiting for a tap; only one element per screen loops for attention.

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

Off-white with an ink border, a row of six company-colour stripes top and bottom with an ink rule under each, and "BIG BUSINESS" set in ink. Custom decks may replace the back with any 5:7 image (premium).

## Table

The "3D table" design (2026-10, canvas "Big Business — 3D Table": start page, tutorial, table). Sizes below are design points on a 390 x 844 phone; the client multiplies them by `UiTheme.layout_scale` (about 1.85 on a 720 px wide canvas).

- Room: a dark radial glow derived from the picked felt (`UiTheme.room_colors`), so every felt skin gets a matching room.
- Felt: a 380 x 620 rounded table tilted 32 degrees away from you and seen in perspective (`TableBoard`), with a 14 dp rim in the edge colour and two darker layers under it for thickness. Printed on it in spaced capitals: Supply with its count at the far end, the Market in the middle, your Portfolio near you. Zones are dashed outlines that fill and pulse when you can use them.
- Cards on the felt shrink with distance: Market shares at half size in up to two rows, the supply pile face down with its stacked edges, your kept shares in one small stack per company.
- Your hand stands at the near edge of the felt, fanned 7 degrees per card. Anything you can tap now (the supply, Market shares, hand cards) has an orange ring; a Market share your own token blocks is hatched.
- Opponents sit on white plates around the far side (left, top, right, clockwise from your left), with their face-down hands fanned on the felt in front of them. A plate shows avatar, name with a "bot" or "away" tag, capital, and a pip per company held with a gold "R" seal for each token. The seat whose turn it is lifts and glows yellow, with the timer arc around its avatar.
- Top bar: red BIG BUSINESS chip, whose turn it is, the timer, Leave or Forfeit. Bottom bar (cream, rounded top): you (capital and pips), emotes, rules, the prompt (what to do, or what the others just did), and the move buttons.
- Panels that interrupt play (tutorial coach, dividend day, season standings) are white cards with a hard ink drop and a coloured title band: orange for the coach, gold for dividend day, purple for the season. The coach dims the table except the area its step is about.
- Type: Archivo Black for titles, counts and scores; Nunito Sans (ExtraBold for labels and buttons, Bold for paragraphs). Buttons are white, yellow (`#F2C230`) for the main action or cream, with an ink border and a thicker bottom edge as a drop shadow.
- Start page: a little felt with the six shares fanned above it (they sway, and flip when tapped), the title card on a red band, your portfolio (name, level, XP, streak, daily bonus, season standings), Play now, How to play, private rooms; friends, quests, the shop, rules, account and server below the fold.

## Profile and the name step

The profile opens from the avatar and name in the lobby's HUD (`ProfilePanel`), in the lobby's purple room.

- The hero is the investor card (`InvestorCard`): the player drawn as a share, in the same title-deed layout as the six companies. The gold band carries the level where a share prints its count, then "INVESTOR" and the name; the name line carries the club, or "Independent investor"; the art window holds the avatar on a sunburst; the footer reads "Level N investor". It sits at the logo's tilt, and a tap turns it over to the card back the player has equipped.
- Opening it, the card grows out of the HUD avatar (0.3 s), the rest fades in behind it, the XP bar runs up to its value and one sheen crosses the card. Closing is a 0.12 s fade.
- Under the card: the XP bar with the XP inside it (the level is on the card), then the record on a cream panel set like a deed's rent table, a label, a dotted leader and the value in Archivo Black (`LedgerRow`). Games played, wins, best finish and daily streak inform; under a hairline, Season, Club and Look have a chevron and open the standings, the clubs and the card-back picker.
- Plus members get a second panel: win rate, average and best capital, top-three finishes, games with people, six company-colour chips with the majorities held, and the last ten finishes as round chips (a win is gold). While Plus is on offer and the player has none, the panel is one sentence and a "See Plus" button; otherwise it is hidden.
- Last, quiet on the purple: Change name and Copy name, how the account is kept (guest or linked) and the link buttons.
- Room is left for what the XP and quests plan adds: a career title can take the card's name line or footer, a rank emblem and a picked tag chip fit the band and the art window's corners, an avatar picture with a frame replaces the initial on the sunburst, and badges and streak history are further panels in the scroll.

The name step (`NamePrompt`) is an orange deed sheet that rises at the bottom of the screen with one field, under a tilted investor card that fills in as the player types. It covers the screen with the purple room, so nothing of the lobby reads through. It is shown once at first launch ("Pick a name", "Let's play", no way out but a name) and from the profile ("Change your name", with Cancel beside Save; a tap outside the sheet cancels too, unless a new name was typed, when it only puts the keyboard away). With the keyboard up, the card gives up height so the name being typed stays on screen. The copy asks for a nickname, not a real name, because players of every age see each other's names. One line under the field gives the rules ("2 to 16 letters or numbers.") and turns red with what is wrong when a name is refused, while the field shakes once. If saving fails for a reason that is not the name (no connection, an outage, too many tries), a "Not now" button appears, so a new player is never locked out; the lobby asks again at the next connection. Until a name is picked, the HUD reads "New investor" and the card "Your name", never the random string the server made, and Change name starts from an empty field; the lobby remembers this between launches.

## Regulator token

A small round token in the company colour with a white "R" and the company icon. Tooltip on first appearance: "You hold the most Tidewater shares. You can't take Tidewater from the Market, but you don't pay onto Tidewater shares when you draw."

## Coins

- Bronze coin: capital 1. Gold coin: capital 3.
- Dividend day flips coins from bronze to gold with a satisfying spin. Coins never show a currency symbol.

## Bots

Named after office archetypes so they read as friendly, not fake people: Intern Ivy, Analyst Avi, Broker Bo, Auditor Ada, CEO Cal, Investor Ines. Bots have a small "bot" badge; no bot is ever presented as a human.
