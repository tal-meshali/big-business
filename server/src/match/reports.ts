/** Moderation: report_player RPC and the friend-request rate hook. Registered by main.ts. */
import { isClientError, isUserId, MATCH_ID_MAX, parseBody, readString, reject, REPORT_NOTE_MAX, requireUser } from './input';
import { utcDate } from './progression';
import { checkRate } from './ratelimit';
import { SYSTEM_USER } from './rooms';

const REPORT_COLLECTION = 'reports';
const REPORT_REASONS = ['name', 'behaviour', 'cheating', 'other'];

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
  const previous = existing ? (existing.value as { count?: unknown }).count : 0;
  const count = (typeof previous === 'number' && isFinite(previous) ? previous : 0) + 1;
  nk.storageWrite([
    {
      collection: REPORT_COLLECTION,
      key,
      userId: SYSTEM_USER,
      value: { reporter, reported, reason, matchId, note, at: now, count },
      permissionRead: 0,
      permissionWrite: 0,
    },
  ]);
  logger.info('report filed %s by %s against %s (%s) x%d', key, reporter, reported, reason, count);
  return JSON.stringify({ ok: true });
};

/**
 * Friend requests go straight to Nakama's API, which already refuses requests
 * to users who blocked the caller and merges duplicates, but does not limit
 * how many strangers one account can ping. This hook adds the same per-user
 * budget the RPCs use; a storage failure lets the request through (logged).
 */
export const beforeAddFriends: nkruntime.BeforeHookFunction<nkruntime.AddFriendsRequest> = (ctx, logger, nk, data) => {
  if (ctx.userId) {
    try {
      checkRate(nk, ctx.userId, 'add_friends', Date.now());
    } catch (e) {
      if (isClientError(e)) throw e;
      logger.warn('add_friends rate check failed: %s', String(e));
    }
  }
  return data;
};

// Nakama resolves registerRpc arguments to named function literals in this
// module (it refuses wrappers such as guardRpc(fn)), so each guarded RPC is a
