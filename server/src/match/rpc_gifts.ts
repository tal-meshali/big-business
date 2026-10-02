/**
 * Gift RPCs: send a mutual friend a gift of track points once a day, see
 * what is waiting, and collect it. Both rows are server-only (reports.ts
 * SERVER_COLLECTIONS); each RPC writes its rows in one storage call with
 * their versions, so a race is refused as a whole and never pays twice.
 */
import { availableCosmetics } from './cosmetics';
import { addGift, claimGifts, claimsLeft, GIFT_COLLECTION, GIFT_POINTS, GIFTS_SEND_PER_DAY, normalizeInbox, normalizeSent, sendBlocker, waiting } from './gifts';
import { isUserId, parseBody, reject, requireUser } from './input';
import { loadProfile } from './profile';
import { PROFILE_COLLECTION, PROFILE_KEY } from './progression';
import { readOwned } from './purchases';
import { checkRate } from './ratelimit';
import { areMutualFriends } from './social';

const INBOX_KEY = 'inbox';
const SENT_KEY = 'sent';
/** Names shown with the waiting gifts. */
const NAMES_SHOWN = 5;

function readRow(nk: nkruntime.Nakama, key: string, userId: string): { value: unknown; version: string } {
  const r = nk.storageRead([{ collection: GIFT_COLLECTION, key, userId }])[0];
  // WHY: a row the client created (permissionWrite 1) is ignored, like the profile.
  if (!r || r.permissionWrite !== 0) return { value: null, version: r ? r.version : '*' };
  return { value: r.value, version: r.version };
}

function req(key: string, userId: string, value: unknown, version: string): nkruntime.StorageWriteRequest {
  return { collection: GIFT_COLLECTION, key, userId, value: value as { [k: string]: unknown }, version, permissionRead: 0, permissionWrite: 0 };
}

function writeAll(nk: nkruntime.Nakama, reqs: nkruntime.StorageWriteRequest[]): void {
  try {
    nk.storageWrite(reqs);
  } catch (e) {
    reject('try again');
  }
}

/** RPC gift_state: waiting gifts, how many can be collected today, and who got one from you today. */
export const rpcGiftState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const now = Date.now();
  const inbox = normalizeInbox(readRow(nk, INBOX_KEY, userId).value);
  const sent = normalizeSent(readRow(nk, SENT_KEY, userId).value, now);
  const list = waiting(inbox, now);
  return JSON.stringify({
    waiting: list.length,
    names: list.slice(0, NAMES_SHOWN).map((g) => g.name),
    claimLeft: claimsLeft(inbox, now),
    sentToday: sent.to,
    sendLeft: Math.max(0, GIFTS_SEND_PER_DAY - sent.to.length),
    points: GIFT_POINTS,
  });
};

/** RPC send_gift {userId}: one gift a day to a mutual friend who has not blocked you. */
export const rpcSendGift: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const target = parseBody(payload)['userId'];
  if (!isUserId(target) || target === userId) reject('invalid player');
  checkRate(nk, userId, 'send_gift', Date.now());
  if (!areMutualFriends(nk, userId, target)) reject('not friends');
  const now = Date.now();
  const sentRow = readRow(nk, SENT_KEY, userId);
  const sent = normalizeSent(sentRow.value, now);
  const blocker = sendBlocker(sent, target);
  if (blocker) reject(blocker);
  const inboxRow = readRow(nk, INBOX_KEY, target);
  const me = nk.usersGetId([userId])[0];
  const inbox = addGift(normalizeInbox(inboxRow.value), { from: userId, name: me ? me.username : '', at: now }, now);
  const nextSent = { day: sent.day, to: sent.to.concat([target]) };
  writeAll(nk, [req(SENT_KEY, userId, nextSent, sentRow.version), req(INBOX_KEY, target, inbox, inboxRow.version)]);
  logger.debug('gift %s -> %s', userId, target);
  return JSON.stringify({ sent: target, sendLeft: Math.max(0, GIFTS_SEND_PER_DAY - nextSent.to.length) });
};

/** RPC claim_gifts: collects waiting gifts (up to today's cap) as track points. */
export const rpcClaimGifts: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'claim_gifts', Date.now());
  const now = Date.now();
  const inboxRow = readRow(nk, INBOX_KEY, userId);
  const result = claimGifts(normalizeInbox(inboxRow.value), now);
  const profile = loadProfile(nk, userId);
  const progress = { ...profile.progress, trackPoints: profile.progress.trackPoints + result.points };
  if (result.count > 0) {
    writeAll(nk, [
      req(INBOX_KEY, userId, result.inbox, inboxRow.version),
      { collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: progress as unknown as { [k: string]: unknown }, version: profile.version === null ? '*' : profile.version, permissionRead: 1, permissionWrite: 0 },
    ]);
  }
  return JSON.stringify({
    claimed: result.count,
    points: result.points,
    trackPoints: progress.trackPoints,
    unlocked: availableCosmetics(progress.trackPoints, readOwned(nk, userId).owned),
    waiting: result.inbox.pending.length,
  });
};
