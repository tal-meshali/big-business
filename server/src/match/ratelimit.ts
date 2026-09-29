/**
 * Per-user rate limits for RPCs a modified client could hammer. One storage
 * row per (user, bucket) in the `ratelimit` collection (server-only
 * permissions) holds a fixed window: `{start, count}`.
 *
 * WHY storage and not a module-level Map: Nakama runs RPCs on a pool of
 * JavaScript VMs, each with its own globals, so an in-memory map would let a
 * client through once per VM. A versioned storage write makes the check
 * atomic: if two calls race, the second write fails and is treated as
 * limited. The extra read and write per call are cheap next to what these
 * RPCs already do.
 */
import { reject } from './input';

export const RATE_COLLECTION = 'ratelimit';
export const RATE_WINDOW_MS = 60_000;

/** Calls allowed per user per minute. */
export const RATE_LIMITS = {
  find_player: 20,
  invite_friend: 10,
  report_player: 5,
  create_room: 6,
  add_friends: 20,
};

export interface Bucket {
  /** Epoch ms when the current window opened. */
  start: number;
  /** Calls made in the current window. */
  count: number;
}

/**
 * Pure decision: the bucket after one more call, or null when the call
 * exceeds `limit` inside the window. A missing or malformed row counts as
 * an empty bucket.
 */
export function advanceBucket(row: Partial<Bucket> | null | undefined, limit: number, windowMs: number, now: number): Bucket | null {
  const start = row && typeof row.start === 'number' && isFinite(row.start) ? row.start : 0;
  const count = row && typeof row.count === 'number' && isFinite(row.count) ? row.count : 0;
  if (now - start >= windowMs || start > now) return { start: now, count: 1 };
  if (count >= limit) return null;
  return { start, count: count + 1 };
}

/** Rejects with 'too many requests' once `userId` exceeds `limit` calls per minute on `bucket`. */
export function checkRate(nk: nkruntime.Nakama, userId: string, bucket: keyof typeof RATE_LIMITS, now: number): void {
  const limit = RATE_LIMITS[bucket];
  const rows = nk.storageRead([{ collection: RATE_COLLECTION, key: bucket, userId }]);
  const row = rows[0];
  const next = advanceBucket(row ? (row.value as Partial<Bucket>) : null, limit, RATE_WINDOW_MS, now);
  if (!next) reject('too many requests');
  try {
    nk.storageWrite([
      {
        collection: RATE_COLLECTION,
        key: bucket,
        userId,
        value: next,
        version: row ? row.version : '*',
        permissionRead: 0,
        permissionWrite: 0,
      },
    ]);
  } catch (e) {
    // Version conflict: another call from the same user raced this one.
    reject('too many requests');
  }
}
