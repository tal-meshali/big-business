/**
 * Profile storage helpers and the quest / cosmetic RPCs. The pure logic is in
 * quests.ts and cosmetics.ts; this file only reads and writes the profile row.
 */
import { equipCosmetic, unlockedCosmetics } from './cosmetics';
import { normalizeProgress, PROFILE_COLLECTION, PROFILE_KEY, type Progress } from './progression';
import { claimQuest, questProfile } from './quests';

export function requireUser(ctx: nkruntime.Context): string {
  if (!ctx.userId) throw Error('unauthenticated');
  return ctx.userId;
}

/** Reads the profile row, filling fields older rows do not have. */
export function readProgress(nk: nkruntime.Nakama, userId: string): Progress {
  const rows = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId }]);
  const row = rows[0];
  return normalizeProgress(row ? (row.value as Partial<Progress>) : null);
}

export function writeProgress(nk: nkruntime.Nakama, userId: string, p: Progress): void {
  nk.storageWrite([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: p, permissionRead: 1, permissionWrite: 0 }]);
}

/** Quest rows, track points, unlocked and equipped cosmetics for get_profile. */
export function profileExtras(p: Progress, nowMs: number): ReturnType<typeof questProfile> {
  return questProfile(p, nowMs);
}

/** RPC claim_quest {id}: adds a completed quest's points to the track, once. */
export const rpcClaimQuest: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = JSON.parse(payload || '{}') as { id?: string };
  const result = claimQuest(readProgress(nk, userId), String(req.id || ''), Date.now());
  if (result.ok) writeProgress(nk, userId, result.progress);
  return JSON.stringify({ ok: result.ok, trackPoints: result.progress.trackPoints, unlocked: unlockedCosmetics(result.progress.trackPoints) });
};

/** RPC equip_cosmetic {slot, id}: selects an unlocked card back or table felt. */
export const rpcEquipCosmetic: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = JSON.parse(payload || '{}') as { slot?: string; id?: string };
  const p = readProgress(nk, userId);
  const result = equipCosmetic(p.equipped, p.trackPoints, String(req.slot || ''), String(req.id || ''));
  if (result.ok) writeProgress(nk, userId, { ...p, equipped: result.equipped });
  return JSON.stringify({ ok: result.ok, equipped: result.equipped });
};
