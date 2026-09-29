# Big Business: rules specification

This is the authoritative rules document for the server engine (`server/src/engine`). It is written in our own words. Where the physical game's rulebook is ambiguous or silent, a **ruling** is recorded here and marked as such. Items marked **verify** should be checked against a physical copy of the source game before public launch.

## 1. Players and components

- 3 to 7 seats. Seats not filled by humans are filled by bots. A 2-player private room is played with one bot as a third seat.
- 45 share cards across 6 companies: 5, 6, 7, 8, 9 and 10 shares (see `theme.md` for company identities).
- Capital coins. Every coin is worth 1 (bronze) until it is received as a dividend, after which it is worth 3 (gold). Coins are conserved: they only move between players and the Market.
- 6 regulator tokens, one per company. Tokens start unowned.

## 2. Setup

1. Shuffle all 45 shares with the server's seeded random generator.
2. Remove 5 shares from the game. They are never revealed, not even at the end.
3. Deal 3 shares to every seat.
4. Every seat receives 10 bronze coins.
5. The remaining shares form the Supply, face down. The Market starts empty.
6. Seat order is randomised. The first seat plays first.

Supply size by player count: 3 players 31, 4 players 28, 5 players 25, 6 players 22, 7 players 19.

## 3. Turn structure

A turn has exactly two steps in order: **Take**, then **Play**. A player's hand is 3 shares between turns and 4 during the Play step.

### 3.1 Take step

The player must do exactly one of:

**(a) Draw from the Supply.**
- Before drawing, the player places 1 bronze coin on **every** share currently in the Market, except shares of companies whose regulator token the player holds.
- The player must be able to pay the full amount. If the player has fewer coins than the number of Market shares that require payment, drawing is illegal.
- Coins placed this way come from the player's bronze coins only. **Ruling:** gold coins cannot exist before dividend day, so this never conflicts.
- The player then takes the top share of the Supply into their hand.

**(b) Take a share from the Market.**
- The player chooses one share in the Market and takes it into their hand along with every coin on it. Received coins are bronze (they were never dividends).
- The player may not take a share of a company whose regulator token they hold.
- If the Market is empty, this option is unavailable.

**Verify:** the physical rulebook exempts token-held companies from payment when drawing; the exemption and the take restriction are both implemented per the majority of rules summaries.

**Ruling (forced choice):** if drawing is unaffordable and every Market share is of a company whose token the player holds, that situation is impossible, because token-held companies are exempt from payment, so drawing would cost 0. The engine asserts this invariant in tests.

### 3.2 Play step

The player must play exactly one share from their 4-card hand to one of:

**(a) Their Portfolio**, face up in front of them.
**(b) The Market**, face up with no coins on it.

Restriction: the player may not play to the Market a share of the same company as the share they took this turn (from either the Supply or the Market). **Verify** against the rulebook; most summaries state the restriction by company.

After the Play step, regulator tokens are re-evaluated (section 4), the turn ends and the next seat in order becomes active.

### 3.3 Turn timer

- Default 30 seconds per step (60 per turn) for random matches; private rooms may choose 20, 30, 60 or 120 seconds, or off.
- When the timer expires, the server plays the **auto-move** (section 8) for the current step and records it as a system action.
- A seat that auto-moves on 3 consecutive turns is converted to a bot for the rest of the game. A returning player may reclaim the seat when it is their turn again.

## 4. Regulator tokens

- After every Play step, for each company: the player with **strictly more** shares of that company in their Portfolio than every other player holds that company's token.
- If no player has strictly the most (a tie for the most, or nobody has any), the token does not move: it stays with its current holder, or stays unowned if it was never taken.
- Tokens are never returned to the supply once taken.
- Holding a token has two effects during the Take step: the holder pays nothing onto that company's Market shares when drawing, and may not take that company's shares from the Market.
- Holding a token never restricts the Play step.

**Ruling (tie retention):** the physical rules say the token moves to whoever has the most; the "strictly more" reading, with the current holder keeping it on a tie, is the common interpretation and is what the engine implements. **Verify.**

## 5. Game end

- The game ends when the Supply is empty **and** the player who drew the last Supply share has completed their Play step.
- **Ruling:** if the Supply is empty at the start of a Take step, that situation cannot occur (the game ended already), so the engine never offers a Take on an empty Supply.
- All hands are revealed and each player's 3 hand shares are added to their Portfolio. This may change who has the most of a company.

## 6. Dividend day (scoring)

Resolved for all six companies simultaneously, based on the revealed Portfolios.

For each company:
1. If one player holds strictly more shares than every other player, that player is the **majority holder**. If there is a tie for the most, nobody is majority holder and no dividend is paid for that company.
2. Every other player who holds at least one share of that company owes the majority holder **1 coin per share** they hold of that company.

Payment:
- Each player sums what they owe across all companies and pays it from their bronze coins.
- **Ruling (insufficient coins):** if a player owes more than they have, they pay everything they have. The shortfall is distributed to creditors in company order (company 0 first), one coin at a time, until coins run out. This is deterministic and only affects edge games.
- Every coin received as a dividend becomes gold (worth 3).
- Coins received from one company's dividend are **not** available to pay another company's dividend, because payment is simultaneous. This is a **ruling** chosen for determinism.

Final score = bronze coins remaining × 1 + gold coins received × 3.

Ranking: highest score wins. Ties are broken by more gold coins, then by fewer total shares in Portfolio (a leaner portfolio), then shared.

## 7. Legality summary

An action is legal only if all of the following hold. The server rejects anything else and logs the rejection.

| Action | Legal when |
|---|---|
| `take_supply` | phase is Take, seat is active, Supply non-empty, player can pay coins onto all non-exempt Market shares |
| `take_market(card)` | phase is Take, seat is active, card is in Market, player does not hold that company's token |
| `play_portfolio(card)` | phase is Play, seat is active, card is in hand |
| `play_market(card)` | phase is Play, seat is active, card is in hand, card's company differs from the company taken this turn |

## 8. Auto-move (timeouts and tutorial bots) and bot policy

The engine provides one deterministic auto-move per step. Tutorial bots use it too; ordinary bots use the bot policy below.

Take step:
1. If any Market share is takeable and carries at least 2 coins, take the one with the most coins (tie: the company the player already has the most of).
2. Else if drawing costs at most 1 coin and is affordable, draw.
3. Else if any Market share is takeable, take the one with the most coins.
4. Else draw.

Play step:
1. Play to Portfolio the share of the company the player holds most of in Portfolio + hand (tie: highest share-count company).
2. If holding that company's token would be lost... (no lookahead in v1; keep it simple).

This auto-move is what a timed-out player is charged with, and what the tutorial bots play (a fixed seed plus a fixed tie-break gives every learner the same opening).

### Bot policy

Bots in ordinary games use a stronger policy (`server/src/engine/bot.ts`, `botAction`). It is a short lookahead: every legal action is applied with the pure engine and the resulting state is scored from the bot's seat, using only what that seat can see (its own hand, all Portfolios, the Market, coins, tokens and the Supply count; never the Supply order or other hands). A play is scored one step further: after the next seat's most likely take, chosen with the same evaluation from what that seat can see. With four opponents between two of the bot's turns the Market is picked over before it moves again, so what it leaves there is judged by what the next seat does with it. The score combines:

- **Majority standing per company**: the bot's Portfolio plus hand against every other seat's Portfolio. The company's still-unseen shares (Supply, removed cards and hidden hands) are shared out evenly as expected future pickups, and each rival's extra shares are modelled as a Poisson count, so the chance of a strict lead is the product over rivals. A thin lead is therefore worth much less at a full table than against two rivals, and it stays uncertain while hands are hidden; with nothing unseen it is the exact rule (strictly more wins). That chance times 3 points per opposing share is the projected income; the chance of paying times the bot's own shares is the projected minority cost; a tie for the most pays nobody. A share still in hand is charged only part of its minority cost while it can still be sold. The same projection is computed for every seat, and the bot scores a state by its own projected result against the strongest opponent's (blended with the average opponent), so blocking a rival's majority counts as much as building its own.
- **Coins**: coins in hand at face value, coins paid onto the Market when drawing, coins picked up with a Market share, and a smaller penalty for coins left on Market shares the next taker can pick up.
- **Regulator tokens**: a bonus for each token held (cheaper draws), a cost for a token that blocks the bot from taking a company it collects (every opponent between its turns may sell one it then cannot pick up), a small tax per Market share the bot would have to pay for on its next draw, and no credit for Market shares its own token blocks it from taking.
- **Market danger**: a penalty for every Market share that would hand another seat a majority or a token if they took it, larger for the next seat. This is what stops the bot selling a share the next player needs.
- **Hand clutter**: lone hand shares of companies the bot holds nothing else of each cost a play to sell, so beyond the first they are charged a small cost that grows with the number of opponents.
- **Drawing**: the drawn card is unknown, so the draw is scored as the average over the companies the top card could belong to, weighted by how many of their shares are still unseen.
- **End of game**: as the Supply runs down, the dividend projection is weighted more than the coin terms, because it is about to become the real result.

Actions that score within a small margin of each other are chosen by the bot's random tie-break, so bots at one table do not play identically. As a progress guarantee (the game only ends when the Supply empties), a bot draws whenever Market takes have run ahead of Supply draws by a fixed margin; if it cannot afford to draw it takes the richest Market share and keeps its shares in its Portfolio until it can.

Measured against the auto-move (one bot seat rotated through every position, the rest auto-move, 1600 games at 5 seats and 800 at 3 seats over four seed sets): about 71% rank-1 finishes at 3 seats (range 68% to 73%) and about 30% at 5 seats (range 27% to 34%), where chance is 33% and 20%, at 0.3 ms per decision on average in Node. The reply lookahead is what helps at a full table (it lifted the 5-seat rate from about 27%); a two-step search of the bot's own turn measured no further gain at four times the cost and is switched off. `bot.test.ts` asserts legality, determinism, the progress guarantee, both tournaments and the time budget.

Timeouts still use the simple auto-move above, not the bot policy.

## 9. Known exploit: hand/Market cycling

Discussed on BoardGameGeek: a player can draw, then play a share to the Market, then later retrieve it. The same-company restriction in 3.2 and the fact that every Supply draw costs coins already limit this. **Ruling:** no extra rule. Turn timers and the finite Supply bound the loop. Revisit after playtesting.

## 10. Visibility (per-player view)

Each client receives only:
- Its own hand.
- For every seat: Portfolio (all face up), coin count (bronze and gold separately after dividend day), tokens held, hand **count**, connection state, bot flag.
- Market shares and their coin counts.
- Supply count (not contents).
- Removed-card count (always 5), never their identities.
- Active seat, phase, turn deadline.
- After the game ends: all hands revealed and the dividend breakdown.

Clients never receive the random seed, the Supply order, the removed cards or other hands.

## 11. Action log

Every accepted action (human, bot or timeout) is appended to the match log with sequence number, seat, action and resulting public events. Reconnecting clients receive a snapshot plus any actions after their last acknowledged sequence number. The log is also the replay format.
