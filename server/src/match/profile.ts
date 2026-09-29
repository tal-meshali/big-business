/**
 * The profile storage row: the only place it is read or written. Used by the
 * profile RPCs and by the awards step at the end of a match.
 */
import { reject } from './input';
import { normalizeProgress, PROFILE_COLLECTION, PROFILE_KEY, type Progress } from './progression';

export interface ProfileRow {
  progress: Progress;
  /** Storage version for a conditional write; null when the row does not exist. */
  version: string | null;
}

/**
 * Reads the profile row, filling fields older rows do not have.
 *
 * WHY the permissionWrite check: a client can create `profile/progress` itself
 * through Nakama's storage API before the server has ever written it (client
 * writes may only set permissionWrite 1). Such a row is treated as absent so
 * pre-seeded XP or track points never count; the next server write replaces
 * it with permissionWrite 0, after which the client can no longer touch it.
 */
export function loadProfile(nk: nkruntime.Nakama, userId: string): ProfileRow {
  const rows = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId }]);
  const row = rows[0];
  if (!row) return { progress: normalizeProgress(null), version: null };
  if (row.permissionWrite !== 0) return { progress: normalizeProgress(null), version: row.version };
  return { progress: normalizeProgress(row.value as Partial<Progress>), version: row.version };
}

export function readProgress(nk: nkruntime.Nakama, userId: string): Progress {
  return loadProfile(nk, userId).progress;
}

/**
 * Writes the profile row as server-owned (clients may read their own row,
 * never write it). With `version` from loadProfile the write only succeeds
 * when the row is unchanged since it was read, so two concurrent claims
 * cannot both be paid; the loser is told to try again. Without `version` the
 * write is unconditional (the awards step uses that: XP must never be lost
 * because a claim raced it).
 */
export function saveProfile(nk: nkruntime.Nakama, userId: string, p: Progress, version?: string | null): void {
  const req: nkruntime.StorageWriteRequest = { collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: p, permissionRead: 1, permissionWrite: 0 };
  if (version !== undefined) req.version = version === null ? '*' : version;
  try {
    nk.storageWrite([req]);
  } catch (e) {
    if (version !== undefined) reject('try again');
    throw e;
  }
}

export function writeProgress(nk: nkruntime.Nakama, userId: string, p: Progress): void {
  saveProfile(nk, userId, p);
}
