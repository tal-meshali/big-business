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
- Real games open with a 4-second get-ready countdown showing the seat order; nobody may act during it, and the first step's timer starts when it ends. The tutorial has no countdown (its coach opens with a welcome card).

### 3.4 Forfeit

- A player may forfeit at any time before dividend day. A bot plays their seat to the end of the game, and they cannot rejoin it.
- A forfeit counts as a game played, with no XP, win or season points, whatever the seat's final rank.
- If every human at the table has forfeited, the match closes at once.

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

## 8. Auto-move and bots

The engine has two policies. Both only ever return a legal action.

### 8.1 Simple auto-move (timeouts and tutorial bots)

`autoAction` in `server/src/engine/auto.ts` gives one deterministic move per step. It plays for a human whose step timer expires (tie-break 0) and for the tutorial's bots (tie-break 0), because the tutorial's coach steps are scripted against a fixed seed and this exact behaviour.

Take step:
1. If any Market share is takeable and carries at least 2 coins, take the one with the most coins (tie: the company the player already has the most of).
2. Else if drawing costs at most 1 coin and is affordable, draw.
3. Else if any Market share is takeable, take the one with the most coins.
4. Else draw.

Play step:
1. If the Market holds fewer than 4 shares, sell to the Market a lone share (the only one of its company in Portfolio + hand, and not of the company taken this turn), lowest company first.
2. Otherwise play to Portfolio the share of the company the player holds most of in Portfolio + hand (tie: highest share-count company).

A table where every seat uses this policy can cycle Market shares forever without drawing (seen in simulation). A match never has such a table: the tutorial always has its human seat, and every other bot seat uses the heuristic bot.

### 8.2 Heuristic bot (real games)

Bots in real games, including seats converted to bots after repeated timeouts, use `botAction` in `server/src/engine/bot.ts`. It decides from its own seat's view (section 10), so it never sees other hands, the Supply order or the removed shares. Its randomness is not derived from the game seed.

How it decides:
- **Company values.** For each company it estimates the dividend value of ending the game with k shares: 3 per share owed to it as majority holder, minus 1 per share it owes as a minority holder. Each opponent's final count is modelled as Portfolio + hidden hand + future gains. The unseen shares of a company are its total minus every share the bot can see. Hidden hands are modelled as correlated (players sell singletons and keep pairs), and future gains as widely spread (some players pick a company up late).
- **One focus company.** It expects to keep growing only the company it holds most of. Other companies are valued as they stand, so stray shares get sold rather than kept as long shots.
- **Scoring actions.** Every legal action is scored as coins after the action plus the value of the resulting holdings. A take is scored with the best play that could follow it, and a draw averages over the unseen shares. In practice it takes Market shares with coins on them rather than paying to draw, sells shares it cannot win, and keeps its majority company.
- **Variety.** Small random noise separates near-equal actions, so bots are not identical.
- **Stall guard.** If Market takes so far exceed 3 × draws + 15 (from the public turn number and Supply count), it draws when drawing is legal and does not sell. This keeps an all-bot table from cycling forever, so every game ends.
- **Keep pace.** On value alone the bot kept its best shares in hand and cycled Market shares for their coins (the loop in section 9), so its Portfolio barely grew: at 3 seats its longest run of sells averaged 12 turns, and 18 to 32% of bots had at most one Portfolio share at mid-game. Players read that as bots never keeping shares. Now, when a bot has kept on fewer than 30% of its turns so far (its Portfolio size against the public turn number), keeping a share of its focus company scores 1 point higher. With one simple seat standing in for a person, bots keep on about a third of their plays and almost none reach mid-game with a near-empty Portfolio. The cost is 1 to 2 points a game against the version without it.

Measured against the simple policy with one heuristic bot and the other seats simple, over 150 fixed deals with every seat rotation of each deal (`bot.test.ts` runs a smaller version on every check):

| Seats | Heuristic bot avg score | Simple bots avg score | Heuristic bot win rate | Fair win rate |
|---|---|---|---|---|
| 3 | 20.1 | 13.1 | 57% | 33% |
| 4 | 18.8 | 13.7 | 37% | 25% |
| 5 | 17.0 | 13.7 | 26% | 20% |
| 6 | 16.6 | 13.3 | 23% | 17% |
| 7 | 15.3 | 13.2 | 16% | 14% |

With several heuristic bots at a 5-seat table, each still averages 16.7 (2 heuristic vs 3 simple, 25% win rate each) or 16.3 (3 vs 2, 25% each), against 12.9 and 11.5 for the simple bots. Every decision takes well under a millisecond in Node.

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
