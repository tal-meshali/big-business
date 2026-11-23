/**
 * Player progression: XP and levels awarded at the end of a game, a daily
 * streak bonus, and the points written to the monthly season leaderboard.
 * XP is the one reward (decision D23): it fills the career level and the
 * cosmetic track.
 * Pure functions; storage is handled by the caller.
 */

export const PROFILE_COLLECTION = 'profile';
export const PROFILE_KEY = 'progress';
export const SEASON_LEADERBOARD = 'season';

/** Progress on one quest: how far along and whether its XP was collected. */
export interface QuestProgress {
  progress: number;
  claimed: boolean;
}

/** Quest state keyed by the UTC day and ISO week it belongs to. */
export interface QuestState {
  /** UTC date (YYYY-MM-DD) the daily entries belong to, or ''. */
  day: string;
  daily: { [questId: string]: QuestProgress };
  /** ISO week (YYYY-Www) the weekly entries belong to, or ''. */
  week: string;
  weekly: { [questId: string]: QuestProgress };
}

export function emptyQuestState(): QuestState {
  return { day: '', daily: {}, week: '', weekly: {} };
}

export interface Progress {
  xp: number;
  level: number;
  gamesPlayed: number;
  wins: number;
  /** Consecutive daily claims. */
  streak: number;
  /** UTC date (YYYY-MM-DD) of the last daily claim, or ''. */
  lastDailyClaim: string;
  bestRank: number;
  /**
   * XP counted toward the free cosmetic track (cosmetics.ts TRACK). Every XP
   * award adds here too; decision D23 retired the separate track points.
   */
  trackXp: number;
  quests: QuestState;
  /** Selected cosmetics by slot; ids from match/cosmetics.ts. */
  equipped: { cardBack: string; table: string };
}

export function emptyProgress(): Progress {
  return {
    xp: 0,
    level: 1,
    gamesPlayed: 0,
    wins: 0,
    streak: 0,
    lastDailyClaim: '',
    bestRank: 0,
    trackXp: 0,
    quests: emptyQuestState(),
    equipped: { cardBack: 'back_classic', table: 'table_green' },
  };
}

/**
 * Fills fields missing from rows stored before quests and cosmetics existed.
 * WHY: storage rows are never migrated in place; every reader normalises.
 */
export function normalizeProgress(raw: (Partial<Progress> & { trackPoints?: unknown }) | null | undefined): Progress {
  const base = emptyProgress();
  if (!raw || typeof raw !== 'object') return base;
  const q = raw.quests;
  const e = raw.equipped;
  // Counters are finite non-negative integers; anything else falls back.
  const count = (v: unknown, fallback: number): number =>
    typeof v === 'number' && isFinite(v) && v >= 0 ? Math.floor(v) : fallback;
  return {
    xp: count(raw.xp, base.xp),
    level: Math.max(1, count(raw.level, base.level)),
    gamesPlayed: count(raw.gamesPlayed, base.gamesPlayed),
    wins: count(raw.wins, base.wins),
    streak: count(raw.streak, base.streak),
    lastDailyClaim: typeof raw.lastDailyClaim === 'string' ? raw.lastDailyClaim.slice(0, 10) : base.lastDailyClaim,
    bestRank: count(raw.bestRank, base.bestRank),
    // WHY: rows written before D23 hold quest points. Converting at the
    // rate the thresholds were scaled by keeps every unlocked cosmetic
    // unlocked and the bar at the same fraction.
    trackXp: raw.trackXp !== undefined ? count(raw.trackXp, base.trackXp) : count(raw.trackPoints, 0) * TRACK_XP_PER_POINT,
    quests: q && typeof q === 'object'
      ? { day: q.day || '', daily: q.daily || {}, week: q.week || '', weekly: q.weekly || {} }
      : base.quests,
    equipped: e && typeof e === 'object'
      ? { cardBack: typeof e.cardBack === 'string' ? e.cardBack : base.equipped.cardBack, table: typeof e.table === 'string' ? e.table : base.equipped.table }
      : base.equipped,
  };
}

/** XP one retired track point is worth; the track thresholds were scaled by the same factor. */
export const TRACK_XP_PER_POINT = 12;

/** The two numbers that turn a finished game into XP; operators tune them in Remote Config. */
export interface XpRates {
  /** XP for finishing a game. */
  base: number;
  /** XP per coin of final capital. */
  perCoin: number;
}

export const DEFAULT_XP_RATES: XpRates = { base: 20, perCoin: 2 };

/** Adds XP to the career total and the cosmetic track, and recomputes the level. */
export function addXp(p: Progress, amount: number): Progress {
  const gain = Math.max(0, Math.floor(amount));
  const xp = p.xp + gain;
  return { ...p, xp, level: levelForXp(xp), trackXp: p.trackXp + gain };
}

/** Level thresholds grow quadratically: level n needs 50 * (n-1)^2 XP. */
export function levelForXp(xp: number): number {
  return Math.floor(Math.sqrt(Math.max(0, xp) / 50)) + 1;
}

export function xpForLevel(level: number): number {
  return 50 * (level - 1) * (level - 1);
}

/** What one finished game pays, split the way the earnings report shows it. */
export interface GameXp {
  /** XP for finishing. */
  finish: number;
  /** XP for the capital the player ended with. */
  capital: number;
  /** XP per coin after the bot-only halving; the report prints "capital x rate". */
  rate: number;
}

/**
 * XP for finishing a game: a fixed part plus a part linear in final capital
 * (decision D23). There is no win bonus: the winner already holds the most
 * capital. Games against only bots pay half.
 */
export function xpForGame(capital: number, humanCount: number, rates: XpRates = DEFAULT_XP_RATES): GameXp {
  const scale = humanCount >= 2 ? 1 : 0.5;
  const rate = rates.perCoin * scale;
  return {
    finish: Math.round(rates.base * scale),
    capital: Math.round(Math.max(0, capital) * rate),
    rate,
  };
}

/** Season points: rank-based, only for games with at least two humans. */
export function seasonPointsForGame(rank: number, seatCount: number, humanCount: number): number {
  if (humanCount < 2) return 0;
  return Math.max(0, seatCount - rank) * 3 + (rank === 1 ? 5 : 0);
}

export function applyGameResult(p: Progress, rank: number, capital: number, humanCount: number, rates: XpRates = DEFAULT_XP_RATES): Progress {
  const game = xpForGame(capital, humanCount, rates);
  return {
    ...addXp(p, game.finish + game.capital),
    gamesPlayed: p.gamesPlayed + 1,
    wins: p.wins + (rank === 1 ? 1 : 0),
    bestRank: p.bestRank === 0 ? rank : Math.min(p.bestRank, rank),
  };
}

/** A forfeit counts as a game played, with no XP, win or season points. */
export function applyForfeit(p: Progress): Progress {
  return { ...p, gamesPlayed: p.gamesPlayed + 1 };
}

export function utcDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

export interface DailyClaim {
  claimed: boolean;
  progress: Progress;
  xpAwarded: number;
}

/** Daily bonus: 10 XP plus 5 per streak day up to 7. Missing a day resets the streak. */
export function claimDaily(p: Progress, nowMs: number): DailyClaim {
  const today = utcDate(nowMs);
  if (p.lastDailyClaim === today) return { claimed: false, progress: p, xpAwarded: 0 };
  const yesterday = utcDate(nowMs - 86_400_000);
  const streak = p.lastDailyClaim === yesterday ? p.streak + 1 : 1;
  const xpAwarded = 10 + 5 * Math.min(streak, 7);
  return { claimed: true, xpAwarded, progress: { ...addXp(p, xpAwarded), streak, lastDailyClaim: today } };
}
