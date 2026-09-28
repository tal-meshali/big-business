/**
 * Daily and weekly quests that feed the free cosmetic track. Pure functions
 * over Progress; storage is handled by the RPCs and the awards step.
 *
 * Runs in goja: ES2016 only, no Math.random (picks are seeded by the date so
 * every player sees the same quests and the server never has to store the
 * selection).
 */
import type { Action, GameState } from '../engine';
import { TRACK, unlockedCosmetics } from './cosmetics';
import { emptyQuestState, utcDate, type Progress, type QuestProgress, type QuestState } from './progression';

/** How a quest accumulates: `sum` adds each game's stat, `best` keeps the highest single game. */
export type QuestKind = 'sum' | 'best';

export type StatKey = 'games' | 'wins' | 'marketTakes' | 'marketCoins' | 'tokensEnd' | 'goldEnd' | 'majorities' | 'withPeople';

export interface QuestDef {
  id: string;
  text: string;
  stat: StatKey;
  kind: QuestKind;
  target: number;
  points: number;
}

export const DAILY_POOL: ReadonlyArray<QuestDef> = [
  { id: 'd_play_3', text: 'Play 3 games', stat: 'games', kind: 'sum', target: 3, points: 10 },
  { id: 'd_win_1', text: 'Win a game', stat: 'wins', kind: 'sum', target: 1, points: 15 },
  { id: 'd_market_4', text: 'Take 4 shares from the Market', stat: 'marketTakes', kind: 'sum', target: 4, points: 10 },
  { id: 'd_coins_5', text: 'Collect 5 coins from Market shares', stat: 'marketCoins', kind: 'sum', target: 5, points: 10 },
  { id: 'd_token', text: 'Hold a regulator token at the end of a game', stat: 'tokensEnd', kind: 'best', target: 1, points: 10 },
  { id: 'd_gold_4', text: 'Finish a game with 4 or more gold coins', stat: 'goldEnd', kind: 'best', target: 4, points: 10 },
  { id: 'd_majority_2', text: 'Be the majority holder of 2 companies in one game', stat: 'majorities', kind: 'best', target: 2, points: 15 },
  { id: 'd_people', text: 'Play a game with other people', stat: 'withPeople', kind: 'sum', target: 1, points: 10 },
];

export const WEEKLY_POOL: ReadonlyArray<QuestDef> = [
  { id: 'w_play_12', text: 'Play 12 games this week', stat: 'games', kind: 'sum', target: 12, points: 30 },
  { id: 'w_win_3', text: 'Win 3 games this week', stat: 'wins', kind: 'sum', target: 3, points: 40 },
  { id: 'w_market_15', text: 'Take 15 shares from the Market', stat: 'marketTakes', kind: 'sum', target: 15, points: 30 },
  { id: 'w_coins_25', text: 'Collect 25 coins from Market shares', stat: 'marketCoins', kind: 'sum', target: 25, points: 30 },
  { id: 'w_people_5', text: 'Play 5 games with other people', stat: 'withPeople', kind: 'sum', target: 5, points: 35 },
  { id: 'w_majority_3', text: 'Be the majority holder of 3 companies in one game', stat: 'majorities', kind: 'best', target: 3, points: 40 },
  { id: 'w_gold_8', text: 'Finish a game with 8 or more gold coins', stat: 'goldEnd', kind: 'best', target: 8, points: 35 },
];

export const DAILY_COUNT = 3;
export const WEEKLY_COUNT = 2;

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

function pad2(n: number): string {
  return n < 10 ? '0' + n : String(n);
}

/** ISO 8601 week of a UTC instant, as "YYYY-Www" (weeks start on Monday). */
export function utcWeek(ms: number): string {
  const d = new Date(ms);
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  // Move to the Thursday of this week; its year is the ISO year.
  const dayNum = (t.getUTCDay() + 6) % 7;
  t.setUTCDate(t.getUTCDate() - dayNum + 3);
  const isoYear = t.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(isoYear, 0, 4));
  firstThursday.setUTCDate(firstThursday.getUTCDate() - ((firstThursday.getUTCDay() + 6) % 7) + 3);
  const week = 1 + Math.round((t.getTime() - firstThursday.getTime()) / (7 * 86_400_000));
  return isoYear + '-W' + pad2(week);
}

// ---------------------------------------------------------------------------
// Deterministic picks
// ---------------------------------------------------------------------------

/** djb2 over the key string; stays below 2^53 without Math.imul. */
function hashKey(key: string): number {
  let h = 5381;
  for (let i = 0; i < key.length; i++) h = ((h * 33) ^ key.charCodeAt(i)) >>> 0;
  return h;
}

/** Picks `count` distinct entries from `pool`, seeded by `key`. */
function pickSeeded(pool: ReadonlyArray<QuestDef>, count: number, key: string): QuestDef[] {
  let seed = hashKey(key) || 1;
  const remaining = pool.slice();
  const out: QuestDef[] = [];
  while (out.length < count && remaining.length > 0) {
    // LCG step (Numerical Recipes constants), kept in 32 bits.
    seed = (seed * 1664525 + 1013904223) >>> 0;
    const idx = seed % remaining.length;
    const def = remaining.splice(idx, 1)[0];
    if (def) out.push(def);
  }
  return out;
}

/** The three daily quests for a UTC date (YYYY-MM-DD). Same for every player. */
export function dailyQuests(dateStr: string): QuestDef[] {
  return pickSeeded(DAILY_POOL, DAILY_COUNT, 'daily:' + dateStr);
}

/** The two weekly quests for an ISO week (YYYY-Www). */
export function weeklyQuests(weekStr: string): QuestDef[] {
  return pickSeeded(WEEKLY_POOL, WEEKLY_COUNT, 'weekly:' + weekStr);
}

export function questById(id: string): QuestDef | null {
  for (const q of DAILY_POOL) if (q.id === id) return q;
  for (const q of WEEKLY_POOL) if (q.id === id) return q;
  return null;
}

// ---------------------------------------------------------------------------
// Per-game stats
// ---------------------------------------------------------------------------

export interface GameStats {
  games: number;
  wins: number;
  marketTakes: number;
  marketCoins: number;
  /** Regulator tokens held when the game ended. */
  tokensEnd: number;
  goldEnd: number;
  /** Companies this seat was the majority holder of at dividend time. */
  majorities: number;
  /** 1 when at least two humans sat at the table. */
  withPeople: number;
  humans: number;
  rank: number;
}

export interface LogEntry {
  seq: number;
  seat: number;
  action: Action;
  source: string;
  /** Coins that came with a Market share, recorded by the handler. */
  coins?: number;
}

/** Stats for one seat from the finished game and the accepted-action log. */
export function gameStats(game: GameState, log: ReadonlyArray<LogEntry>, seat: number): GameStats {
  const me = game.seats[seat];
  let humans = 0;
  for (const s of game.seats) if (!s.id.startsWith('bot:')) humans++;
  let marketTakes = 0;
  let marketCoins = 0;
  for (const entry of log) {
    if (entry.seat !== seat || entry.action.type !== 'take_market') continue;
    marketTakes++;
    marketCoins += entry.coins || 0;
  }
  let tokensEnd = 0;
  for (const holder of game.tokens) if (holder === seat) tokensEnd++;
  let majorities = 0;
  let rank = 0;
  if (game.result) {
    for (const c of game.result.companies) if (c.majority === seat) majorities++;
    for (const sc of game.result.scores) if (sc.seat === seat) rank = sc.rank;
  }
  return {
    games: 1,
    wins: rank === 1 ? 1 : 0,
    marketTakes,
    marketCoins,
    tokensEnd,
    goldEnd: me ? me.gold : 0,
    majorities,
    withPeople: humans >= 2 ? 1 : 0,
    humans,
    rank,
  };
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

function freshEntries(defs: QuestDef[]): { [id: string]: QuestProgress } {
  const out: { [id: string]: QuestProgress } = {};
  for (const d of defs) out[d.id] = { progress: 0, claimed: false };
  return out;
}

function copyEntries(src: { [id: string]: QuestProgress }): { [id: string]: QuestProgress } {
  const out: { [id: string]: QuestProgress } = {};
  for (const id in src) {
    const e = src[id];
    if (e) out[id] = { progress: e.progress, claimed: e.claimed };
  }
  return out;
}

/**
 * Starts a new day or week when the calendar moved on. Unclaimed points from
 * a finished period are lost, which is what keeps the daily rhythm.
 */
export function rolloverQuests(q: QuestState | undefined, nowMs: number): QuestState {
  const state = q || emptyQuestState();
  const day = utcDate(nowMs);
  const week = utcWeek(nowMs);
  return {
    day,
    daily: state.day === day ? copyEntries(state.daily) : freshEntries(dailyQuests(day)),
    week,
    weekly: state.week === week ? copyEntries(state.weekly) : freshEntries(weeklyQuests(week)),
  };
}

function advance(entries: { [id: string]: QuestProgress }, defs: QuestDef[], stats: GameStats): void {
  for (const def of defs) {
    const e = entries[def.id];
    if (!e || e.claimed) continue;
    const value = stats[def.stat];
    const next = def.kind === 'sum' ? e.progress + value : Math.max(e.progress, value);
    e.progress = Math.min(def.target, next);
  }
}

/** Advances today's and this week's quests with one finished game. */
export function applyGameToQuests(q: QuestState | undefined, stats: GameStats, nowMs: number): QuestState {
  const state = rolloverQuests(q, nowMs);
  advance(state.daily, dailyQuests(state.day), stats);
  advance(state.weekly, weeklyQuests(state.week), stats);
  return state;
}

export interface QuestRow {
  id: string;
  text: string;
  target: number;
  points: number;
  progress: number;
  claimable: boolean;
  claimed: boolean;
}

function rows(entries: { [id: string]: QuestProgress }, defs: QuestDef[]): QuestRow[] {
  return defs.map((def) => {
    const e = entries[def.id] || { progress: 0, claimed: false };
    return {
      id: def.id,
      text: def.text,
      target: def.target,
      points: def.points,
      progress: e.progress,
      claimable: !e.claimed && e.progress >= def.target,
      claimed: e.claimed,
    };
  });
}

/** What the client shows: today's and this week's quests with progress. */
export function questView(q: QuestState | undefined, nowMs: number): { daily: QuestRow[]; weekly: QuestRow[] } {
  const state = rolloverQuests(q, nowMs);
  return { daily: rows(state.daily, dailyQuests(state.day)), weekly: rows(state.weekly, weeklyQuests(state.week)) };
}

/** Claims a completed quest once, adding its points to the track. */
export function claimQuest(p: Progress, id: string, nowMs: number): { ok: boolean; progress: Progress } {
  const def = questById(id);
  if (!def) return { ok: false, progress: p };
  const quests = rolloverQuests(p.quests, nowMs);
  const active = id.startsWith('w_') ? weeklyQuests(quests.week) : dailyQuests(quests.day);
  let listed = false;
  for (const d of active) if (d.id === id) listed = true;
  const entries = id.startsWith('w_') ? quests.weekly : quests.daily;
  const e = entries[id];
  if (!listed || !e || e.claimed || e.progress < def.target) return { ok: false, progress: { ...p, quests } };
  e.claimed = true;
  return { ok: true, progress: { ...p, quests, trackPoints: p.trackPoints + def.points } };
}

/** The profile fields the quests panel needs, beyond the base progress. */
export function questProfile(p: Progress, nowMs: number): {
  quests: { daily: QuestRow[]; weekly: QuestRow[] };
  trackPoints: number;
  unlocked: string[];
  equipped: { cardBack: string; table: string };
  track: Array<{ points: number; cosmeticId: string }>;
} {
  return {
    quests: questView(p.quests, nowMs),
    trackPoints: p.trackPoints,
    unlocked: unlockedCosmetics(p.trackPoints),
    equipped: p.equipped,
    track: TRACK.map((t) => ({ points: t.points, cosmeticId: t.cosmeticId })),
  };
}
