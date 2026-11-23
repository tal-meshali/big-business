# Engagement plan: XP, quests, daily rewards, seasons, ranks and swag

Agreed with the project owner on 2026-11-21 (decisions D23 to D27 in `docs/decisions.md`). This is the reference for every progression, reward and growth feature. Nothing here is built yet beyond what section 2 lists; section 13 gives the build order.

Items marked **Proposed** were put to the owner and not objected to, but not explicitly confirmed. Check before building them. Every number is a starting value that lives in Remote Config, so it can be tuned without a release.

## 1. The rule above the others: kind, not aggressive

The owner asked for retention that is "overall kind and not aggressive". Every feature below has to pass these rules. One that breaks a rule is redesigned or dropped.

1. **Nothing earned is ever taken away.** No streak wipe that costs a reward, no rank that drops, no reward that expires unclaimed.
2. **Nothing is "last chance".** A missed season's rewards come back later. No countdown clocks on offers.
3. **A day's goals fit in 15 to 20 minutes.** Nothing rewards playing for hours. No energy bars, no waiting timers.
4. **The game asks before it reminds.** Reminders are off until the player turns them on, rare, and never worded as a warning or as guilt.
5. **One calm marker, not a wall of red dots.** The lobby shows a single "something to collect" marker.
6. **Everything that matters is free.** Money buys looks only, never progress, rank or an advantage.
7. **Nobody is shamed.** Standings show who did well and never single out who did least.

These sit on top of D4 (every age) and D5 (no virtual currency, no loot boxes).

## 2. What exists today

A first version of each piece is merged (`server/src/match/progression.ts`, `quests.ts`, `cosmetics.ts`, `awards.ts`, `gifts.ts`, `boards.ts`). The table is where the plan started from on 2026-11-21; section 13 marks what has been built since.

| Piece | How it works now | What it gives |
| --- | --- | --- |
| XP | 20 per game, plus 10 per player beaten, plus 30 for a win. Half for bot-only games. | A level number |
| Levels | Level n needs 50 x (n-1)^2 XP | Nothing; the number shows on the avatar |
| Daily bonus | Lobby gift button, once per UTC day: 10 XP plus 5 per streak day, capped at day 7 | XP only |
| Streak | Consecutive daily claims; one missed day resets it to 1 | Nothing beyond the larger bonus |
| Daily quests | 3 a day from a pool of 8, same for everyone, 10 to 15 points each; unclaimed points are lost at midnight UTC | Track points |
| Weekly quests | 2 a week from a pool of 7, 30 to 40 points each; reset Monday | Track points |
| Free cosmetic track | 5 steps up to 300 points: 3 card backs, 2 felts | Finished in about 10 active days, then nothing |
| Season | Monthly leaderboard; points only from games with at least 2 people; resets on the 1st | A position; no reward |
| Club league | Season points also count for the club; resets Monday | A position; no reward |
| Friend gifts | 5 track points to a friend, once a day each (D14) | Track points |

Gaps this plan closes: the end-of-game screen shows nothing earned; levels unlock nothing; the track ends; the streak only punishes; seasons end silently; there is no first-week path and no long-term goal; nothing calls a player back; nothing rewards bringing a friend.

## 3. The loop

Players earn one thing, XP. It fills two bars: a career level that never resets and a season track that restarts each month. Track points are retired; quests and gifts pay XP.

| Clock | What the player does | What they get |
| --- | --- | --- |
| Every game (5 to 8 minutes) | Finishes a game | An earnings report on the end screen: final capital turning into XP, quest bars moving, any level-up or unlock |
| Every day | Plays a first game, works on 3 daily quests | The daily dividend, quest XP, a streak day |
| Every week | Works on 2 weekly quests, plays for the club | Larger XP, the club league result |
| Every month | Climbs the season track and the ranks | About 6 free cosmetics, a rank, a recap |
| Always | Gains career levels, completes achievements | Titles, avatar frames, badges |

Pacing target: a normal visit is 2 or 3 games. That day earns about 370 XP (150 from games, 110 from daily quests, 70 from the dividend, 40 as the day's share of weekly quests). A season track of 5,000 XP then takes about 14 active days, so a player who misses half the month still finishes it. These figures come from average scores in bot simulations, not from real players.

## 4. XP

| Source | XP | Note |
| --- | --- | --- |
| Finishing a game with people | 20 + 2 per coin of final capital | Replaces the rank-based formula. **Proposed** rate. |
| Finishing a bot-only game | Half of the above | Option if farming appears: only the first 5 bot games a day pay |
| Daily quest | 30 to 45 | Was 10 to 15 track points |
| Weekly quest | 120 to 160 | Was 30 to 40 track points |
| Daily dividend | 30 rising to 150 on day 7 | Section 6 |
| Friend gift | 15 | Was 5 track points; same caps as D14 |
| Getting-started goal | 50 | One time each |

**Capital becomes XP (owner's request).** XP after a game is linear in the capital the player ends with: bronze coins count 1 and gold coins count 3, the same score that decides the winner (`score` in `server/src/engine/game.ts`). The earnings report shows it as one line, for example "Capital 23 x 2 = 46 XP", with coins flowing into the XP bar. Average capital is about 15, so a typical game still pays about 50 XP and a win with 30 capital pays 80. There is no separate win bonus because the winner already holds the most capital. A forfeit earns nothing. Season points stay based on finishing place and are never affected by XP, quests or purchases.

## 5. Career levels

The level curve stays (level n needs 50 x (n-1)^2 XP). Levels become a career ladder; each rung is a title the player wears, with an avatar frame.

| Level | Title | Active days to reach, at 370 XP a day |
| --- | --- | --- |
| 1 | Intern | Start |
| 5 | Analyst | 2 to 3 |
| 10 | Associate | 11 |
| 15 | Manager | 26 |
| 20 | Director | 49 |
| 30 | Vice President | 114 |
| 40 | President | 205 |
| 50 | Chief Executive | 325 |
| 75 | Chairman | About 2 years |
| 100 | Tycoon | About 3.5 years |

Every fifth level in between pays a small reward (an emote or a badge).

**Proposed:** Quests appear in the lobby after the first finished game and Clubs at level 3. Play, private rooms and friends are open from the first second.

## 6. Daily dividend and streak

- **Paid by playing.** The lobby gift tile stays as the reminder and shows today's amount. The dividend is paid on the earnings report after the first finished game of the UTC day.
- **A 7-day calendar.** Days pay 30, 40, 50, 60, 70, 80 and 150 XP. Day 7 adds a small cosmetic the first few times round. The calendar moves one step per day played and never moves back; a missed day only delays it.
- **The flame.** The streak counter counts days in a row. One missed day a week is covered automatically and shown as a "day off". After a longer break the flame restarts at 1, but the calendar position, every reward and the best streak on the profile stay.
- **Milestones** count total days played (7, 30, 100, 365), not days in a row. Each gives a badge or frame and cannot be lost.

The day changes at midnight UTC for everyone, as today.

## 7. Quests and achievements

| Kind | How many | Resets | Pays | Status |
| --- | --- | --- | --- | --- |
| Daily | 3 a day | Midnight UTC | 30 to 45 XP | Built: pays XP, collected when the game ends |
| Weekly | 2 a week | Monday | 120 to 160 XP | Built: pays XP, collected when the game ends |
| Getting started | 8, once | Never | 50 XP each; a starter card back for all 8 | New |
| Achievements | About 20, in bronze, silver and gold | Never | A profile badge and XP; a few give a title | New |

- Completed quests are collected on the earnings report. A finished quest is never lost at midnight.
- One free swap a day replaces a quest the player does not want.
- New quests reward playing with people: a private room with a friend, a table of 5 or more, a game with a club-mate, sending a gift. At most one of the day's three needs other people and at most one needs a win.
- **Getting started:** finish the tutorial, play a first game, play with people, win a game, pick a card back, add a friend, join a club, link an Apple or Google account. Three of these are funnel steps `analytics.ts` already counts.
- **Achievements, examples:** games played (10, 100, 500), wins (5, 50, 250), majority holder of each company (10, 50, 200 times; one badge per company), a 7-player table, 10 different friends played with, days played, seasons finished. Games, wins and company majorities are already in the lifetime stats row, so those can count earlier games.

## 8. Monthly season and ranks

The season rides on the existing monthly leaderboard reset.

- **Track.** About 6 rewards over 5,000 XP earned that month: a card back, a felt, an emote, an avatar frame, a title and the season badge.
- **Theme.** Each season has a name and a look its cosmetics share ("Opening Bell", "Gold Rush", "Merger Season").
- **Recap.** On first open after the reset: games, wins, best company, final rank and what was earned.
- **Nothing is gone forever.** A missed season's rewards return about six months later as achievement rewards.
- **Season card back** for anyone who plays 10 games with people that season.
- **Club league.** The top three clubs each week get a crest frame for the next week (a free cosmetic, as D13 requires). Later, once clubs have members.
- **Proposed: a Plus lane.** When Plus is on, members get 3 extra rewards on the same track, including the monthly Plus skin (D12). Plus never gives more XP or anything that touches standings.

**Ranks** are an emblem beside the name showing how a player did against people this season. They use the existing season points (3 per player beaten, 5 for a win, games with at least two people; about 6 a game).

| Rank | Season points | Roughly |
| --- | --- | --- |
| Bronze | First game with people | 1 game |
| Silver | 25 | 4 games |
| Gold | 75 | 12 games |
| Platinum | 150 | 25 games |
| Diamond | 270 | 45 games |
| Blue Chip | 420 | 70 average games, about 40 for a strong player |

Ranks only go up within a season. A new season starts from zero, but last season's emblem stays on the profile until a new one is earned and the best rank ever stays for good. Each rank pays XP when first reached in a season, and a frame in its colour from Gold up. The season's number 1 gets a dated Season Champion tag. A hidden skill rating for seating players of similar strength is a later addition, once enough players are online together.

## 9. Tags and special roles

A tag is a small chip beside the name on the profile, at the table and in standings. Only the server grants tags, in a server-only storage row; a player who holds several picks one to show.

| Tag | Who holds it | How it is granted |
| --- | --- | --- |
| Owner | The owner's account only | Operator command (server-to-server RPC on the http_key). Never earned or bought. Styled differently from every other tag. |
| Team | People who help build or moderate | Operator command |
| Founding Investor | Veterans | Automatically to every account created before the public launch day; the owner can add any later account by operator command |
| Top Recruiter, Recruiter | Winner and next places of an invite tournament | When the owner confirms the result |
| Season Champion | Number 1 of a season | Automatically, with the season's name |
| Club Champion | Members of the week's top club | Automatically, for one week |
| Plus | Plus members, once Plus is on | While subscribed |

Players type their own names, so the Owner tag is also the proof of identity; names such as "Owner" and "Admin" are blocked. Founding Investors may be numbered by join order. Tags carry no powers for now.

## 10. The collection, the store and swag

One catalogue holds every cosmetic by category. Each item says how to get it: earned by playing, or bought for a price shown in real money. Nothing is bought with a game currency.

| Category | What it changes | Today | Mostly comes from |
| --- | --- | --- | --- |
| Card backs | The back of every share | 7 | Season track, shop |
| Table felts | The table colour | 5 | Season track, shop |
| Emotes | Reactions sent at the table | 14, all free | Season track, career levels |
| Avatars | The picture beside the name | A letter | Free starter set, achievements, shop |
| Avatar frames | The ring around the avatar | None | Career titles, ranks, days played |
| Nameplates | The plate behind the name at the table | None | Ranks, seasons, shop |
| Titles | The line under the name | None | Career levels, achievements |
| Tags | The chip beside the name | None | Roles and events only |
| Coin and token skins | The look of coins and regulator tokens | None | Seasons, shop |
| Win effects | The celebration on dividend day | None | Seasons, shop |
| Custom decks | The player's own pictures on shares | Designer | The Designer unlock |

"Collection" shows everything, what the player owns and how to get the rest. "Shop" is the same catalogue filtered to what is for sale, plus Designer and Plus. Bundles group a few items in one theme at one real price. No countdown offers, no "just for you" bundles.

**Swag** is the owner's word for what shows on a player during a game that displays their prestige.

| When | What shows on the player | Where it comes from |
| --- | --- | --- |
| All game, on the seat | Avatar with its frame | Career title, rank, days played |
| All game, on the seat | Rank emblem | Season rank |
| All game, on the seat | One tag chip | Roles and events |
| All game, on the seat | Nameplate style | Ranks, seasons, shop |
| All game, on the hand | Card back | Seasons, shop |
| Get-ready countdown | A larger card per player: title, rank, tag, chosen badge | Everything above |
| Dividend day | The winner's win effect | Seasons, shop |
| On tapping a seat | The full player card: title, tags, badges, best rank, Add friend | The profile |

- **Status is earned, style can be bought.** Tags, rank emblems, rank frames and titles are never sold.
- **The game stays readable.** Swag never covers shares, coins, tokens or the timer. At 6 or 7 players the seat shows only frame, emblem and tag.
- **A "plain table" setting** hides other players' swag.

## 11. Reminders

Off until the player says yes, at most three a week, each kind with its own switch, worded as good news. There is no reminder about the streak. Players under 13 get only "your turn" and friend invites.

| Reminder | Sent when |
| --- | --- |
| Your daily dividend is waiting | Played yesterday, not yet today |
| One more game finishes a quest | A quest is one game from done in the evening |
| A friend sent you a gift | On arrival, if the app is closed |
| You are close to a season reward | One good day from the next reward; at most once a season |
| Your season recap is ready | The 1st of the month |

Needs the device side of push first (TODO-local section G).

## 12. Growth inside the app

- **Invite a friend.** Each player has an invite link. When the friend reaches level 3, both get a "Partners" card back; more rewards at 3 and 5 friends.
- **Room links that survive the install.** A private-room link opened without the app goes to the store and lands in the room after install.
- **Result card.** After a win or on the season recap, a picture of the result with a room code goes to the system share sheet.
- **Rating prompt.** The store's own dialog, once, after a win on the third day or later.

**Invite tournament.** An event the owner starts with one operator command (name, start, end); no release needed.

- Counts a new account made through a player's invite link during the event, on a device with no earlier account, that reaches level 3.
- Players see a lobby card with their own count and the top of the board. No extra notifications.
- The winner gets the Top Recruiter tag with the event's name, for good. The next places get Recruiter; everyone with one counted invite gets a badge.
- The server proposes the final board and the owner approves it before tags are granted.
- Hidden from players under 13.

Store page, screenshots and a soft-launch plan are outside this document.

## 13. Build order

Each item is a feature thread that follows the project workflow (build, test, review, fix) and the design skills for UI.

**Phase 1: make what exists pay off (before the soft launch)**

1. Earnings report on the end-of-game screen. **Built (2026-11-23):** after the Dividend day standings, Continue opens the report (`client/scripts/ui/earnings_report.gd`), drawn from the server's receipt (`OP_EARNINGS`). The career title and the rank emblem join it with items 4 and Phase 2.
2. One XP number: capital-based game XP; quests and gifts pay XP; the track reads XP. Cosmetics already unlocked stay unlocked. **Built (2026-11-23):** old track points count 12 XP each, so nobody loses a look; the track's steps are 360, 840, 1,440, 2,400 and 3,600 XP. A finished quest pays when its game ends; the Quests screen keeps a Collect button for a leftover.
3. Daily dividend: paid by the first game, 7-day calendar, forgiving flame.
4. Career titles and frames.
5. Getting-started goals.
6. Values in Remote Config, and counters for the measures below. **Started:** the game XP rates are `xpGameBase` and `xpPerCoin`.

**Phase 2: reasons to stay (soft launch to launch)**

1. Monthly season: track, ranks, recap, the first two seasons' cosmetics.
2. Achievements, badges and tags (Owner and Founding Investor first), on the new profile screen.
3. Swag at the table: frames, emblem, tag, nameplate, the get-ready player cards.
4. Collection screen with categories, quest swap, social quests.
5. Opt-in reminders, once push works on phones.

**Phase 3: growth**

1. Invite rewards and room links that survive the install.
2. Invite tournament, result card, rating prompt.
3. Plus lane (when Plus is on) and club league rewards.

## 14. Measures

| Measure | Target | Source of the target |
| --- | --- | --- |
| Day-1 return | 35% | Research report 03 |
| Day-7 return | 15% | Research report 03 |
| Day-30 return | 7% | Research report 03 |
| Active players collecting the dividend | 70% | Estimate |
| Active players finishing a daily quest | 60% | Estimate |
| Monthly players finishing the season track | 25 to 35% | Estimate |

Also tracked: games per active day and the spread of streak lengths.
