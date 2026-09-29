/**
 * The quest / cosmetic RPCs. The pure logic is in quests.ts and cosmetics.ts;
 * this file only validates the payload and reads and writes the profile row.
 */
import { equipCosmetic, unlockedCosmetics } from './cosmetics';
import { parseBody, readString, requireUser } from './input';
import { loadProfile, saveProfile } from './profile';
import { claimQuest, questProfile } from './quests';
import type { Progress } from './progression';

export { readProgress, writeProgress } from './profile';
export { requireUser } from './input';

/** Quest rows, track points, unlocked and equipped cosmetics for get_profile. */
export function profileExtras(p: Progress, nowMs: number): ReturnType<typeof questProfile> {
  return questProfile(p, nowMs);
}

/** RPC claim_quest {id}: adds a completed quest's points to the track, once. */
export const rpcClaimQuest: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const row = loadProfile(nk, userId);
  const result = claimQuest(row.progress, readString(req, 'id', 32), Date.now());
  if (result.ok) saveProfile(nk, userId, result.progress, row.version);
  return JSON.stringify({ ok: result.ok, trackPoints: result.progress.trackPoints, unlocked: unlockedCosmetics(result.progress.trackPoints) });
};

/** RPC equip_cosmetic {slot, id}: selects an unlocked card back or table felt. */
export const rpcEquipCosmetic: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const row = loadProfile(nk, userId);
  const p = row.progress;
  const result = equipCosmetic(p.equipped, p.trackPoints, readString(req, 'slot', 16), readString(req, 'id', 32));
  if (result.ok) saveProfile(nk, userId, { ...p, equipped: result.equipped }, row.version);
  return JSON.stringify({ ok: result.ok, equipped: result.equipped });
};
