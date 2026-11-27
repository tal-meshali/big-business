# Big Business: theme and companies

Working theme: a bright, slightly retro world of six ambitious companies fighting for market dominance. Players are investors collecting shares. Everything is friendly and readable for all ages: no casino imagery, no gambling language.

**Visual direction (decided 2026-09-28): title-deed cards on a board-green table.** The look borrows the language of classic property-trading board games: off-white cards with a black border and a solid colour band naming the company, black text, a pale green playing surface with a darker green rim, and white panels with ink borders. It must not copy any specific board game's logo, mascot, property names or exact board layout.

**Game finish (decided 2026-11-15): "After-hours trading floor".** Research on Clash Royale, Brawl Stars, casual hits and Balatro (direction page: https://claude.ai/artifact/4vBjfqE9DCKq12jtw6XrrD) gave the app the finish of a top mobile game around the unchanged cards:

- Lobby room: royal purple glow (`UiTheme.NIGHT`, `ROYAL`, `ROYAL_GLOW`) with slow gold rays and rising sparkles (`LobbyBackdrop`). The table room still follows the picked felt.
- Buttons (`GlossBox`): a thick ink outline (`#1A1238`), a dark lip under the face, three toon-shaded bands and a white streak; pressed, the face sinks into the lip and the button squashes and springs back (`UiTheme.juice`). Labels are white Archivo Black with an ink outline. Colours by role: gold `#FFC83D` for the one main action per screen, violet `#6A4CF0` for the rest, mint `#26C96F` for rewards, red `#FF3B55` for danger and badges, cream for quiet actions (Close, Skip).
- Capital (`CapitalChip`): a glossy minted coin (copper `#C7742E` for capital, gold `#FFC83D` for dividends; pale spot up-left, dark rim, ink lip) with the count beside it in Archivo Black and no backing: solid ink on a light surface, cream with a thick ink outline on a dark one (`CapitalChip.draw(..., on)` picks by the surface colour; the word beside it is quieter: 65% ink, or lilac on dark). Opponent plates, your strip, Market shares and flying coins all use it, and coins fly to and from the chip's coin. When a count changes it ticks: the number swells to 1.35x out of the coin (from its left edge) and flashes gold, the coin nudges 1.12x (0.08 s up, 0.22 s back; on light surfaces the gold count grows an ink outline while it flashes; the word fades while the count swells over it), and a mint "+N" or red "-N" shows right after its count where there is room, holds, then fades. With reduced motion on, only the flash and the fade remain.
- Wordmark (`LogoTitle`): two-tone gold face, ink outline, brown extrusion, tilted -3 degrees, with a glint every 4 s. The same drawing slams in as "YOUR TURN" at the table.
- App icon and boot splash: the lobby's room (royal purple glow, sixteen gold rays at the lobby's width and colour, two gold glints) behind three share cards fanned like a hand (Pinecone 6, Redline 10 on top, Tidewater 7; white numbers with an ink outline) and a glossy gold capital coin struck with a rising arrow. Outlines are heavier than in the game (22/1024) so they hold at home-screen size, and the icon has no text. The Android adaptive icon puts the room alone in the background layer and the cards and coin, inside the 66 dp safe circle, in the foreground. The splash is portrait (drawn at 1620x2880, stretch mode Cover) and starts as the lobby's first frame: the same room with the rays in the same place, and the BIG BUSINESS wordmark at `LogoTitle`'s size and position, so at the cut only the hand changes. Source: `tools/logo_art.py` writes the SVGs (`client/icon.svg`, `tools/art/`); `tools/make_icons.gd` rasterises them into `client/icons/`.
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

Palette: table `#C7DFC9` with rim `#9BBE9F`; card face `#FFFDF6`; panels white; ink `#1C1C1C`; bronze coin `#B8722E` (capital coins on the table now use the `CapitalChip` copper, see above); gold coin `#E2B23A`; coach band orange `#F7941D`; dividend band gold; alerts and the title plate red `#D6262C`. All text is ink on light surfaces, or white on a colour band (ink on the yellow band).

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
- Felt: a 380 x 620 rounded table tilted 32 degrees away from you and seen in perspective (`TableBoard`), with a 14 dp rim in the edge colour and two darker layers under it for thickness. Printed on it in spaced capitals: the Market in the middle, your Portfolio near you; the supply pile at the far end carries only its count. Zones are dashed outlines that fill and pulse when you can use them.
- Cards on the felt shrink with distance: Market shares at half size in up to two rows, the supply pile face down with its stacked edges, your kept shares in one small stack per company.
- Your hand stands at the near edge of the felt, fanned 7 degrees per card. Anything you can tap now (the supply, Market shares, hand cards) has an orange ring; a Market share your own token blocks is hatched.
- Opponents sit on white plates with an ink edge around the far side (left, top, right, clockwise from your left), with their face-down hands fanned on the felt in front of them. A plate shows avatar, name with a "bot" or "away" tag, capital, and a pip per company held with a gold "R" seal for each token. Names are ink (a softer ink while away); the "bot" or "away" tag is ink on a pale lilac pill. The seat whose turn it is turns pale gold with a gold rim, with the timer arc around its avatar.
- The table keeps its light surfaces: seat plates and the bottom bar are white and cream with ink text, not the royal night colours (Tal's call, 2026-11-23). The night scheme is for what opens over the table (dividend day, forfeit, reconnecting, the emote bar, the seat menu, notices) and for the lobby's sheets and panels.
- Top bar (on the room's own background, no band; it hugs the screen's top edge and its row starts at the safe-area inset the phone reports): the logo on the left, no words, then the timer in a solid night pill (gold rim on your own turn, red in the last seconds), then a quiet cream Leave on the right, which becomes a red Forfeit once leaving would cost the game. No status words: the gold plate says whose turn it is, the panels and the prompt say the rest (Tal's call, 2026-11-27). Bottom bar (cream, rounded top, ink text): you (capital and pips), emotes, rules, the prompt (what to do, or what the others just did), and the move buttons.
- Panels (tutorial coach, dividend day, forfeit, reconnecting, and the lobby sheets: shop, friends, clubs, Designer, stats, season, join, more) are night panels: royal body, ink edge with a thicker bottom lip, a glossy title band and cream text. The band is violet, except orange for the coach, gold for dividend day and red for forfeit. The coach dims the table except the area its step is about.
- The rules and Quests are full-height royal sheets with tabs instead of a title band (`UiTheme.royal_sheet_style`, `TabStrip`); inside, they use the same text roles, wells and meters as the night panels.
- Type: Archivo Black for titles, counts and scores; Nunito Sans (ExtraBold for labels and buttons, Bold for paragraphs). Buttons are glossy: violet by default, gold for the main action, mint for rewards, red for danger, cream for quiet ones (Close, Leave). Gold is the one main action of a screen, or of a row in a list (Accept, Join); it also marks the thing in use (the picked crest, the card back you play with). A disabled button is grey whatever its colour was. Display type gets a slightly wider word space, so two-word labels do not close up under their outline.
- Start page: a little felt with the six shares fanned above it (they sway, and flip when tapped), the title card on a red band, your portfolio (name, level, XP, streak, daily bonus, season standings), Play now, How to play, private rooms; friends, quests, the shop, rules, account and server below the fold.

## Text on screen

One rule decides where words go: a name touches the thing it names, a sentence goes where there is room for it, and a message that passes goes in a place that passes.

- Roles (sizes in design points, see `UiTheme.TYPE_*`): title 20 (panel bands, big scores), heading 16 (names, the line that leads a row), body 14 (sentences), label 13 (detail lines under a name, notices, small buttons), caption 11 (section names in spaced capitals). Nothing is smaller than 11, the lobby's level and XP figures included.
- Colours on the table's light surfaces (seat plates, bottom bar): ink `#1A1238` for text, soft ink `#6B6585` for an away name, pale lilac `#D3CBF2` behind a "bot" or "away" tag, pale gold `#FFF1C9` for the active plate.
- Colours on dark surfaces: cream `#FFF6DE` for text, lilac `#B7AEE6` for quieter text, gold for scores and the thing in use, mint for rewards and "live". Labels on colourful or glossy surfaces (buttons, bands, the rays) get an ink outline.
- On the felt: "THE MARKET" and "YOUR PORTFOLIO" are printed in the felt's own dark tone, standing on the top-left of each zone's outline; while a zone can be used its name turns into gold letters on an ink tab. When the Market wraps to a second row, which reaches over the Portfolio's top line, "YOUR PORTFOLIO" becomes an ink tab on the zone's bottom line, drawn above your shares so a tall stack cannot hide it. The supply shows only its count: a gold number on an ink tab at the foot of the pile; the prompt and the Draw button name it.
- The top bar has no status words. Sentences about the game go to the prompt in the bottom bar. One-off messages (muted, report sent, a forfeit, an error from the server) show in a notice pill of two lines at most in the strip between the top bar and the highest seat plate, and fade. Where there is no strip (safe-area insets on notched phones, a tall prompt) the pill lies on the top bar's own row instead of on the players' names. A lost connection dims the table under a violet Reconnecting panel ("Connection lost. Reconnecting…") with a quiet Back to lobby; in a game it keeps trying until the network is back. If the game cannot be rejoined, or the server cannot be reached outside a game, the panel says so and Back to lobby turns gold. "YOUR TURN" slams with its hint only on your first three turns of a game.
- Lists are rows in dark wells: a name over a quieter detail line, the figure in gold on the right. Standings rows carry a medal with the place; your own row is lit violet, on dividend day too. A list that can outgrow the screen scrolls inside its panel with Close fixed under it; in the season standings your own place past the top ten stays pinned under the list. Facts (the stats panel) are rows too: the name on the left, the figure in gold on the right.
- Rare or irreversible actions leave the row: a friend row keeps Invite, Watch and Gift, and "Remove friend" sits in the menu behind "•••"; "Leave club" is the last, quiet, narrow button of its panel and asks for a second tap.
- Helpers in `client/scripts/ui/ui_theme.gd`: `panel`, `well`, `standing_row`, `title`, `body`, `caption`, `meter`, `ink_box`, `dot_icon`. `client/tests/screenshot_panels.gd` renders every panel for a look; pass a locale and a height after the folder (`... -- out en 1280`) to check the shortest screen.

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
