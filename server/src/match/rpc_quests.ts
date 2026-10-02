/**
 * The quest / cosmetic RPCs. The pure logic is in quests.ts and cosmetics.ts;
 * this file only validates the payload and reads and writes the profile row.
 */
import { availableCosmetics, equipCosmetic } from './cosmetics';
import { parseBody, readString, requireUser } from './input';
import { loadProfile, saveProfile } from './profile';
import { readOwned } from './purchases';
import { claimQuest, questProfile } from './quests';
import type { Progress } from './progression';

export { readProgress, writeProgress } from './profile';
export { requireUser } from './input';

/** Quest rows, track points, unlocked (track and owned skins) and equipped cosmetics for get_profile. */
export function profileExtras(p: Progress, nowMs: number, owned: ReadonlyArray<string> = []): ReturnType<typeof questProfile> {
  return questProfile(p, nowMs, owned);
}

/** RPC claim_quest {id}: adds a completed quest's points to the track, once. */
export const rpcClaimQuest: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const row = loadProfile(nk, userId);
  const result = claimQuest(row.progress, readString(req, 'id', 32), Date.now());
  if (result.ok) saveProfile(nk, userId, result.progress, row.version);
  return JSON.stringify({ ok: result.ok, trackPoints: result.progress.trackPoints, unlocked: availableCosmetics(result.progress.trackPoints, readOwned(nk, userId).owned) });
};

/** RPC equip_cosmetic {slot, id}: selects an unlocked or purchased card back or table felt. */
export const rpcEquipCosmetic: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const row = loadProfile(nk, userId);
  const p = row.progress;
  const result = equipCosmetic(p.equipped, p.trackPoints, readString(req, 'slot', 16), readString(req, 'id', 32), readOwned(nk, userId).owned);
  if (result.ok) saveProfile(nk, userId, { ...p, equipped: result.equipped }, row.version);
  return JSON.stringify({ ok: result.ok, equipped: result.equipped });
};
