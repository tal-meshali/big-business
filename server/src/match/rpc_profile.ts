/** Profile RPCs: get_profile and claim_daily. Registered by main.ts. */
import { requireUser } from './input';
import { trackActive } from './metrics';
import { loadProfile, readProgress, saveProfile } from './profile';
import { claimDaily, utcDate } from './progression';
import { readOwned } from './purchases';
import { profileExtras } from './rpc_quests';

export const rpcGetProfile: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void payload;
  const now = Date.now();
  const userId = requireUser(ctx);
  // The lobby loads the profile on every visit, so this is the day-active signal.
  trackActive(nk, logger, userId, now);
  const p = readProgress(nk, userId);
  return JSON.stringify({ progress: p, dailyAvailable: p.lastDailyClaim !== utcDate(now), ...profileExtras(p, now, readOwned(nk, userId).owned) });
};

/** RPC claim_daily: once per UTC day; streak grows on consecutive days. */
export const rpcClaimDaily: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const row = loadProfile(nk, userId);
  const result = claimDaily(row.progress, Date.now());
  if (result.claimed) saveProfile(nk, userId, result.progress, row.version);
  return JSON.stringify({ claimed: result.claimed, xpAwarded: result.xpAwarded, progress: result.progress });
};

/**
 * RPC report_player: files a report into a moderation queue that only the
 * console can read (Apple 1.2 / Play UGC). Blocking is done client-side
 * through Nakama's friends API.
 *
 * WHY one row per (day, reporter, reported): repeated reports of the same
 * player update that row's count instead of growing the collection, and the
 * per-user rate limit bounds how many distinct rows a day one account adds.
 */
