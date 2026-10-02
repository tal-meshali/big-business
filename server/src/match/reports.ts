/** Moderation: report_player RPC and the friend-request rate hook. Registered by main.ts. */
import { isClientError, isUserId, MATCH_ID_MAX, parseBody, readString, reject, REPORT_NOTE_MAX, requireUser } from './input';
import { utcDate } from './progression';
import { checkRate, RATE_COLLECTION, RATE_LIMITS } from './ratelimit';
import { PROFILE_COLLECTION } from './progression';
import { ANALYTICS_COLLECTION, COHORT_COLLECTION } from './analytics';
import { PUSH_COLLECTION } from './push';
import { CONFIG_COLLECTION } from './remote_config';
import { ROOM_COLLECTION, SYSTEM_USER } from './rooms';
import { PURCHASE_COLLECTION } from './store';

export const REPORT_COLLECTION = 'reports';
const REPORT_REASONS = ['name', 'behaviour', 'cheating', 'other'];
/** Reports kept per (day, reporter, reported) row; later ones only raise `count`. */
export const REPORT_ENTRIES_MAX = 10;

export interface ReportEntry {
  reason: string;
  matchId: string;
  note: string;
  at: number;
}

/**
 * The stored row after one more report: every report adds to `count`, and
 * the first REPORT_ENTRIES_MAX keep their reason, match and note so a later
 * report never overwrites the evidence of an earlier one.
 */
export function addReport(previous: unknown, reporter: string, reported: string, entry: ReportEntry): { reporter: string; reported: string; count: number; entries: ReportEntry[] } {
  const prev = (typeof previous === 'object' && previous !== null ? previous : {}) as { count?: unknown; entries?: unknown };
  const count = typeof prev.count === 'number' && isFinite(prev.count) && prev.count > 0 ? prev.count : 0;
  const entries = Array.isArray(prev.entries) ? (prev.entries as ReportEntry[]).slice(0, REPORT_ENTRIES_MAX) : [];
  if (entries.length < REPORT_ENTRIES_MAX) entries.push(entry);
  return { reporter, reported, count: count + 1, entries };
}

export const rpcReportPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const reporter = requireUser(ctx);
  const req = parseBody(payload);
  const reported = req['userId'];
  if (!isUserId(reported) || reported === reporter) reject('invalid user');
  const reasonRaw = readString(req, 'reason', 16);
  const reason = REPORT_REASONS.indexOf(reasonRaw) >= 0 ? reasonRaw : 'other';
  const matchId = readString(req, 'matchId', MATCH_ID_MAX);
  const note = readString(req, 'note', REPORT_NOTE_MAX);
  const now = Date.now();
  checkRate(nk, reporter, 'report_player', now);
  if (nk.usersGetId([reported]).length === 0) reject('invalid user');
  const key = `${utcDate(now)}-${reporter}-${reported}`;
  const existing = nk.storageRead([{ collection: REPORT_COLLECTION, key, userId: SYSTEM_USER }])[0];
  const value = addReport(existing ? existing.value : null, reporter, reported, { reason, matchId, note, at: now });
  try {
    // Versioned: two concurrent reports of the same player cannot both read
    // the same count and drop one.
    nk.storageWrite([
      {
        collection: REPORT_COLLECTION,
        key,
        userId: SYSTEM_USER,
        value,
        version: existing ? existing.version : '*',
        permissionRead: 0,
        permissionWrite: 0,
      },
    ]);
  } catch (e) {
    reject('try again');
  }
  logger.info('report filed %s by %s against %s (%s) x%d', key, reporter, reported, reason, value.count);
  return JSON.stringify({ ok: true });
};

/**
 * Friend requests go straight to Nakama's API, which already refuses requests
 * to users who blocked the caller and merges duplicates, but does not limit
 * how many strangers one account can ping. This hook adds the same per-user
 * budget the RPCs use, charged per user named in the request (one request
 * can name many); a storage failure lets the request through (logged).
 */
export const beforeAddFriends: nkruntime.BeforeHookFunction<nkruntime.AddFriendsRequest> = (ctx, logger, nk, data) => {
  if (ctx.userId) {
    const targets = (data.ids ? data.ids.length : 0) + (data.usernames ? data.usernames.length : 0);
    if (targets > RATE_LIMITS.add_friends) reject('too many requests');
    try {
      checkRate(nk, ctx.userId, 'add_friends', Date.now(), Math.max(1, targets));
    } catch (e) {
      if (isClientError(e)) throw e;
      logger.warn('add_friends rate check failed: %s', String(e));
    }
  }
  return data;
};

// Nakama resolves registerRpc arguments to named function literals in this
// module (it refuses wrappers such as guardRpc(fn)), so each guarded RPC is a

/** Collections only the server writes; clients may never write or delete in them. */
export const SERVER_COLLECTIONS = [
  PROFILE_COLLECTION,
  RATE_COLLECTION,
  ROOM_COLLECTION,
  REPORT_COLLECTION,
  PURCHASE_COLLECTION,
  ANALYTICS_COLLECTION,
  COHORT_COLLECTION,
  CONFIG_COLLECTION,
  PUSH_COLLECTION,
];

/** True when a client storage request touches a server-only collection. */
export function touchesServerCollection(objects: ReadonlyArray<{ collection?: string }> | undefined | null): boolean {
  for (const o of objects || []) {
    if (o && SERVER_COLLECTIONS.indexOf(String(o.collection || '')) >= 0) return true;
  }
  return false;
}

/**
 * WHY: Nakama lets a client create its own storage objects with any
 * permissions, including permissionWrite 0, before the server has written
 * them. Without this hook a client could pre-seed a profile (XP, unlocked
 * cosmetics) or a rate-limit window the server would then trust.
 */
export const beforeWriteStorageObjects: nkruntime.BeforeHookFunction<nkruntime.WriteStorageObjectsRequest> = (ctx, logger, nk, data) => {
  void ctx; void logger; void nk;
  if (touchesServerCollection(data.objects)) reject('storage collection is server-only');
  return data;
};

export const beforeDeleteStorageObjects: nkruntime.BeforeHookFunction<nkruntime.DeleteStorageObjectsRequest> = (ctx, logger, nk, data) => {
  void ctx; void logger; void nk;
  if (touchesServerCollection(data.objectIds)) reject('storage collection is server-only');
  return data;
};
