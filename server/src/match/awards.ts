/**
 * Writes XP, levels, season points and quest progress for every human seat
 * once a game ends, and keeps each player's earnings receipt on the match
 * state for the report the client shows (protocol.ts EarningsMessage).
 */
import { unlockedCosmetics } from './cosmetics';
import { trackActive, trackMilestone } from './metrics';
import { loadProfile, saveProfile } from './profile';
import { applyForfeit, applyGameResult, DEFAULT_XP_RATES, SEASON_LEADERBOARD, seasonPointsForGame, xpForGame, type Progress, type XpRates } from './progression';
import type { EarningsLine, EarningsMessage, EarningsQuest } from './protocol';
import { applyGameToQuests, collectQuests, gameStats, openQuests, type GameStats } from './quests';
import { readRemoteConfig } from './rpc_config';
import { creditClub } from './rpc_clubs';
import { recordStats } from './rpc_stats';
import type { MatchState } from './state';

/** The XP rates in force; the defaults when the config row cannot be read. */
function xpRates(nk: nkruntime.Nakama, logger: nkruntime.Logger): XpRates {
  try {
    const cfg = readRemoteConfig(nk);
    return { base: cfg.xpGameBase, perCoin: cfg.xpPerCoin };
  } catch (e) {
    logger.warn('remote config unreadable, default XP rates used: %s', String(e));
    return DEFAULT_XP_RATES;
  }
}

/** What a seat a bot finished is paid: the bot earned that capital, not the player. */
/** Versioned tries at the profile write before the last, unconditional one. */
const GUARDED_SAVES = 2;

interface Settled {
  progress: Progress;
  earnings: EarningsMessage;
}

/**
 * Reads the profile, settles the game on it and writes it back. WHY the
 * version: a daily or gift claim that lands between the read and the write
 * would otherwise be overwritten, and its XP lost. A conflict reads again;
 * the last try writes regardless, because a finished game must be paid.
 */
function settleAndSave(nk: nkruntime.Nakama, userId: string, settle: (current: Progress) => Settled): Settled {
  for (let attempt = 0; ; attempt++) {
    // WHY loadProfile: it ignores rows the client created itself, so a
    // pre-seeded profile is never carried into the server-owned one.
    const row = loadProfile(nk, userId);
    const settled = settle(row.progress);
    if (attempt >= GUARDED_SAVES) {
      saveProfile(nk, userId, settled.progress);
      return settled;
    }
    try {
      saveProfile(nk, userId, settled.progress, row.version);
      return settled;
    } catch (e) {
      // Changed since the read: settle again on the fresh row.
    }
  }
}

/** One seat's result, as the awards step needs it. */
export interface SeatResult {
  rank: number;
  seats: number;
  /** Final capital (the engine's score: bronze plus three per gold). */
  capital: number;
  /** Humans still playing when the game ended. */
  humans: number;
}

/**
 * Pure: the profile after one finished game and the receipt for it. `stats`
 * is null when the game earns no quest credit (tutorial, or a seat a bot
 * finished after repeated timeouts).
 */
export function settleGame(before: Progress, r: SeatResult, stats: GameStats | null, rates: XpRates, nowMs: number): { progress: Progress; earnings: EarningsMessage } {
  const game = xpForGame(r.capital, r.humans, rates);
  let next = applyGameResult(before, r.rank, r.capital, r.humans, rates);
  const lines: EarningsLine[] = [
    { kind: 'capital', xp: game.capital },
    { kind: 'finish', xp: game.finish },
  ];
  let open: EarningsQuest[] = [];
  if (stats) {
    next = { ...next, quests: applyGameToQuests(next.quests, stats, nowMs) };
    const got = collectQuests(next, nowMs);
    next = got.progress;
    for (const def of got.collected) lines.push({ kind: 'quest', xp: def.xp, text: def.text });
    open = openQuests(before.quests, next.quests, nowMs);
  }
  const had = unlockedCosmetics(before.trackXp);
  const unlocked = unlockedCosmetics(next.trackXp).filter((id) => had.indexOf(id) < 0);
  return {
    progress: next,
    earnings: {
      rank: r.rank,
      seats: r.seats,
      capital: r.capital,
      rate: game.rate,
      botsOnly: r.humans < 2,
      lines,
      xp: next.xp - before.xp,
      xpBefore: before.xp,
      xpAfter: next.xp,
      levelBefore: before.level,
      levelAfter: next.level,
      seasonPoints: seasonPointsForGame(r.rank, r.seats, r.humans),
      quests: open,
      unlocked,
    },
  };
}

/**
 * Best effort: a storage failure is logged and never breaks the match.
 * Returns true on the call that wrote the awards, so the caller sends the
 * receipts once.
 */
export function awardProgress(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger): boolean {
  if (!s.game || !s.game.result || s.awarded) return false;
  s.awarded = true;
  const seatCount = s.game.seats.length;
  let humans = 0;
  // WHY: a player who forfeited, or who was away until a bot finished their
  // seat, is not playing. A 2-human room where one of them is gone counts as
  // a solo game (no season points, reduced XP), so a second account left
  // idle cannot turn a bot game into a game with people.
  for (const seat of s.game.seats) if (!seat.id.startsWith('bot:') && !s.forfeited[seat.id] && !seat.isBot) humans++;
  const now = Date.now();
  const rates = xpRates(nk, logger);
  for (const score of s.game.result.scores) {
    const seat = s.game.seats[score.seat];
    // Forfeited players were recorded when they forfeited (awardForfeit).
    if (!seat || seat.id.startsWith('bot:') || s.forfeited[seat.id]) continue;
    // WHY: a seat with a player's id that ended as a bot was left to time
    // out, so it is recorded like a forfeit: the game counts as played and
    // nothing the bot did (XP, quests, season points, a win, statistics) is
    // credited. The cosmetic track cannot be earned by idling. A player who
    // comes back, by rejoining or by playing a turn, is a player again
    // (handler.ts matchJoin, actions.ts apply) and is paid in full.
    if (seat.isBot) {
      awardForfeit(nk, logger, seat.id);
      continue;
    }
    try {
      // The tutorial (a scripted game anyone can replay) pays no quest credit.
      const game = s.game;
      const earnsQuests = !s.params.tutorial;
      const result: SeatResult = { rank: score.rank, seats: seatCount, capital: score.score, humans };
      const settled = settleAndSave(nk, seat.id, (current) => {
        if (earnsQuests) {
          try {
            return settleGame(current, result, gameStats(game, s.log, score.seat, humans), rates, now);
          } catch (e) {
            logger.warn('quest progress failed for %s: %s', seat.id, String(e));
          }
        }
        return settleGame(current, result, null, rates, now);
      });
      s.earnings[seat.id] = settled.earnings;
      const points = settled.earnings.seasonPoints;
      if (points > 0) {
        nk.leaderboardRecordWrite(SEASON_LEADERBOARD, seat.id, seat.name, points, score.rank === 1 ? 1 : 0);
        try {
          creditClub(nk, seat.id, seat.name, points);
        } catch (e) {
          logger.warn('club credit failed for %s: %s', seat.id, String(e));
        }
      }
      trackGame(nk, logger, seat.id, s.params.tutorial, humans, now);
      if (!s.params.tutorial) {
        try {
          recordStats(nk, seat.id, s.game.result, score.seat, seatCount, humans, now);
        } catch (e) {
          logger.warn('stats failed for %s: %s', seat.id, String(e));
        }
      }
    } catch (e) {
      logger.warn('progress award failed for %s: %s', seat.id, String(e));
    }
  }
  return true;
}

/** Funnel steps for a finished game (analytics.ts); each counts once per player. */
function trackGame(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, tutorial: boolean, humans: number, now: number): void {
  trackActive(nk, logger, userId, now);
  if (tutorial) {
    trackMilestone(nk, logger, userId, 'tutorial', now);
    return;
  }
  trackMilestone(nk, logger, userId, 'firstGame', now);
  if (humans >= 2) trackMilestone(nk, logger, userId, 'peopleGame', now);
}

/** Records a forfeit on the player's profile. Best effort, like awardProgress. */
export function awardForfeit(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string): void {
  try {
    saveProfile(nk, userId, applyForfeit(loadProfile(nk, userId).progress));
  } catch (e) {
    logger.warn('forfeit record failed for %s: %s', userId, String(e));
  }
}
