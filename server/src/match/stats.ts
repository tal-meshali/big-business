/**
 * Lifetime game stats, recorded for every player after each real game (not
 * the tutorial) so they are already there when someone joins Plus. Plus
 * members see the full breakdown; everyone else sees games and wins, which
 * the profile already shows. Pure; storage and the RPC are in rpc_stats.ts.
 */
import type { DividendResult } from '../engine';

export const STATS_COLLECTION = 'stats';
export const STATS_KEY = 'lifetime';
/** Recent games kept for the form line. */
export const RECENT_MAX = 20;

export interface RecentGame {
  /** Epoch ms the game ended. */
  at: number;
  score: number;
  rank: number;
  seats: number;
  humans: number;
}

export interface StatsRow {
  games: number;
  wins: number;
  /** Games finished first, second or third. */
  podiums: number;
  totalScore: number;
  bestScore: number;
  /** Games with at least one other person at the table. */
  peopleGames: number;
  /** Times this player held the majority of each company on dividend day. */
  majorities: number[];
  recent: RecentGame[];
}

export function emptyStats(): StatsRow {
  return { games: 0, wins: 0, podiums: 0, totalScore: 0, bestScore: 0, peopleGames: 0, majorities: [0, 0, 0, 0, 0, 0], recent: [] };
}

function count(v: unknown): number {
  return typeof v === 'number' && isFinite(v) && v >= 0 ? Math.floor(v) : 0;
}

export function normalizeStats(raw: unknown): StatsRow {
  const o = (typeof raw === 'object' && raw !== null ? raw : {}) as { [k: string]: unknown };
  const maj = Array.isArray(o['majorities']) ? (o['majorities'] as unknown[]) : [];
  const recent: RecentGame[] = [];
  for (const g of Array.isArray(o['recent']) ? (o['recent'] as unknown[]) : []) {
    const r = (typeof g === 'object' && g !== null ? g : {}) as { [k: string]: unknown };
    if (count(r['rank']) > 0) recent.push({ at: count(r['at']), score: count(r['score']), rank: count(r['rank']), seats: count(r['seats']), humans: count(r['humans']) });
  }
  return {
    games: count(o['games']),
    wins: count(o['wins']),
    podiums: count(o['podiums']),
    totalScore: count(o['totalScore']),
    bestScore: count(o['bestScore']),
    peopleGames: count(o['peopleGames']),
    majorities: [0, 1, 2, 3, 4, 5].map((i) => count(maj[i])),
    recent: recent.slice(0, RECENT_MAX),
  };
}

/** The row after one finished game for `seat`; null when the seat has no score. */
export function applyGame(row: StatsRow, result: DividendResult, seat: number, seats: number, humans: number, at: number): StatsRow | null {
  let mine = null;
  for (const s of result.scores) if (s.seat === seat) mine = s;
  if (!mine) return null;
  const majorities = row.majorities.slice();
  for (const c of result.companies) if (c.majority === seat && c.company >= 0 && c.company < 6) majorities[c.company] = (majorities[c.company] || 0) + 1;
  return {
    games: row.games + 1,
    wins: row.wins + (mine.rank === 1 ? 1 : 0),
    podiums: row.podiums + (mine.rank <= 3 ? 1 : 0),
    totalScore: row.totalScore + Math.max(0, mine.score),
    bestScore: Math.max(row.bestScore, mine.score),
    peopleGames: row.peopleGames + (humans >= 2 ? 1 : 0),
    majorities,
    recent: [{ at, score: mine.score, rank: mine.rank, seats, humans }].concat(row.recent).slice(0, RECENT_MAX),
  };
}

/** What get_stats returns: everything for Plus, games and wins otherwise. */
export function statsView(row: StatsRow, plus: boolean): { [k: string]: unknown } {
  if (!plus) return { plus: false, games: row.games, wins: row.wins };
  const avg = row.games > 0 ? Math.round((row.totalScore / row.games) * 10) / 10 : 0;
  const winRate = row.games > 0 ? Math.round((row.wins / row.games) * 1000) / 10 : 0;
  return { plus: true, ...row, averageScore: avg, winRate };
}
