/**
 * Social RPCs: find a player by exact username, and invite a friend to a
 * private room with a Nakama in-app notification. Adding, accepting,
 * removing, blocking and listing friends happen client-side through
 * Nakama's friends API, so no RPC is needed for them.
 */
import { isUserId, normalizeCode, parseBody, readString, reject, requireUser, USERNAME_MAX } from './input';
import { INVITE_CODE } from './protocol';
import { checkRate } from './ratelimit';

// WHY: duplicated from main.ts rather than imported: the match layer never
// imports main (docs/conventions.md), and the room lookup must match join_room.
const ROOM_COLLECTION = 'rooms';
const SYSTEM_USER = '00000000-0000-0000-0000-000000000000';

/** Nakama friend states. */
export const FRIEND_STATE_MUTUAL = 0;
export const FRIEND_STATE_INVITE_SENT = 1;
export const FRIEND_STATE_INVITE_RECEIVED = 2;
export const FRIEND_STATE_BLOCKED = 3;

/**
 * Longest sender name embedded in an invite notification. The name is the
 * server-side username (Nakama validates its characters), never the
 * client-editable display name, and never a string from the RPC payload.
 */
export const FROM_NAME_MAX = 32;

export { normalizeCode } from './input';

/** Everything the invite decision depends on, gathered by the RPC. */
export interface InviteCheck {
  callerId: string;
  targetId: string;
  code: string;
  /** Friend states the caller sees, keyed by the other user's id. */
  callerFriends: { [userId: string]: number };
  /** Friend states the target sees, keyed by the other user's id. */
  targetFriends: { [userId: string]: number };
  /** Whether the room code resolves to a match. */
  roomExists: boolean;
}

/**
 * Returns the reason an invite must be refused, or null when it may be sent.
 * Only mutual friends may invite each other: in an all-ages app a stranger
 * must not be able to reach a child with a room code (decision D4).
 */
export function inviteError(check: InviteCheck): string | null {
  if (!check.targetId || check.targetId === check.callerId) return 'invalid user';
  if (!check.code) return 'invalid code';
  if (check.targetFriends[check.callerId] === FRIEND_STATE_BLOCKED) return 'not friends';
  if (check.callerFriends[check.targetId] !== FRIEND_STATE_MUTUAL) return 'not friends';
  if (!check.roomExists) return 'room not found';
  return null;
}

/** Friend states one user has toward others (filtered by `state`), keyed by user id. */
function friendStates(nk: nkruntime.Nakama, userId: string, state: number): { [userId: string]: number } {
  const out: { [userId: string]: number } = {};
  const list = nk.friendsList(userId, 100, state);
  for (const f of list.friends || []) {
    if (f.user && f.state !== undefined) out[f.user.userId] = f.state;
  }
  return out;
}

/** RPC find_player: exact username lookup; never returns the caller. */
export const rpcFindPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const callerId = requireUser(ctx);
  const name = readString(parseBody(payload), 'name', USERNAME_MAX + 1);
  if (!name || name.length > USERNAME_MAX) reject('not found');
  checkRate(nk, callerId, 'find_player', Date.now());
  const users = nk.usersGetUsername([name]);
  const user = users.find((u) => u.username === name && u.userId !== callerId);
  if (!user) reject('not found');
  return JSON.stringify({ userId: user.userId, username: user.username });
};

/**
 * RPC invite_friend: sends a persistent in-app notification carrying the
 * room code to a mutual friend who has not blocked the caller.
 */
export const rpcInviteFriend: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const callerId = requireUser(ctx);
  const req = parseBody(payload);
  const rawTarget = req['userId'];
  const targetId = isUserId(rawTarget) ? rawTarget : '';
  const code = normalizeCode(req['code']);
  const hasTarget = targetId !== '' && targetId !== callerId;
  if (!hasTarget) reject('invalid user');
  if (!code) reject('invalid code');
  checkRate(nk, callerId, 'invite_friend', Date.now());
  const rows = nk.storageRead([{ collection: ROOM_COLLECTION, key: code, userId: SYSTEM_USER }]);
  const check: InviteCheck = {
    callerId,
    targetId,
    code,
    callerFriends: friendStates(nk, callerId, FRIEND_STATE_MUTUAL),
    targetFriends: friendStates(nk, targetId, FRIEND_STATE_BLOCKED),
    roomExists: rows.length > 0,
  };
  const error = inviteError(check);
  if (error) reject(error);
  const caller = nk.usersGetId([callerId])[0];
  const fromName = (caller && caller.username ? caller.username : 'A friend').slice(0, FROM_NAME_MAX);
  nk.notificationSend(targetId, 'Room invite', { code, fromName, fromUserId: callerId }, INVITE_CODE, callerId, true);
  logger.info('invite %s -> %s room %s', callerId, targetId, code);
  return JSON.stringify({ ok: true });
};
