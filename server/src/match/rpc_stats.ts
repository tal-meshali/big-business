/** Lifetime stats storage, the end-of-game record, and the get_stats RPC (stats.ts holds the rules). */
import type { DividendResult } from '../engine';
import { requireUser } from './input';
import { readOwned } from './purchases';
import { applyGame, normalizeStats, statsView, STATS_COLLECTION, STATS_KEY } from './stats';
import { PLUS } from './store';

/**
 * Adds one finished game to a player's stats row. Best effort, like the
 * rest of the awards step: the caller logs a failure and carries on.
 * Versioned, so a second match ending at the same moment cannot drop one.
 */
export function recordStats(nk: nkruntime.Nakama, userId: string, result: DividendResult, seat: number, seats: number, humans: number, at: number): void {
  for (let attempt = 0; attempt < 2; attempt++) {
    const r = nk.storageRead([{ collection: STATS_COLLECTION, key: STATS_KEY, userId }])[0];
    const current = normalizeStats(r && r.permissionWrite === 0 ? r.value : null);
    const next = applyGame(current, result, seat, seats, humans, at);
    if (!next) return;
    try {
      nk.storageWrite([{ collection: STATS_COLLECTION, key: STATS_KEY, userId, value: next, version: r ? r.version : '*', permissionRead: 1, permissionWrite: 0 }]);
      return;
    } catch (e) {
      if (attempt === 1) throw e;
    }
  }
}

/** RPC get_stats: the caller's lifetime stats; the full breakdown with Plus. */
export const rpcGetStats: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const r = nk.storageRead([{ collection: STATS_COLLECTION, key: STATS_KEY, userId }])[0];
  const row = normalizeStats(r && r.permissionWrite === 0 ? r.value : null);
  return JSON.stringify(statsView(row, readOwned(nk, userId).owned.indexOf(PLUS) >= 0));
};
