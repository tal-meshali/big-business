/**
 * Social RPCs: find a player by exact username, and invite a friend to a
 * private room with a Nakama in-app notification. Adding, accepting,
 * removing, blocking and listing friends happen client-side through
 * Nakama's friends API, so no RPC is needed for them.
 */
import { INVITE_CODE } from './protocol';

// WHY: duplicated from main.ts rather than imported: the match layer never
// imports main (docs/conventions.md), and the room lookup must match join_room.
const ROOM_COLLECTION = 'rooms';
const SYSTEM_USER = '00000000-0000-0000-0000-000000000000';

/** Nakama friend states. */
export const FRIEND_STATE_MUTUAL = 0;
export const FRIEND_STATE_INVITE_SENT = 1;
export const FRIEND_STATE_INVITE_RECEIVED = 2;
export const FRIEND_STATE_BLOCKED = 3;

const CODE_LENGTH = 6;

/** Upper-cases and trims a room code; returns '' when it cannot be one. */
export function normalizeCode(code: string | undefined | null): string {
  const c = (code || '').toUpperCase().trim();
  return c.length === CODE_LENGTH ? c : '';
}

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

function requireUser(ctx: nkruntime.Context): string {
  if (!ctx.userId) throw Error('unauthenticated');
  return ctx.userId;
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
  const req = JSON.parse(payload || '{}') as { name?: string };
  const name = (req.name || '').trim();
  if (!name) throw Error('not found');
  const users = nk.usersGetUsername([name]);
  const user = users.find((u) => u.username === name && u.userId !== callerId);
  if (!user) throw Error('not found');
  return JSON.stringify({ userId: user.userId, username: user.username });
};

/**
 * RPC invite_friend: sends a persistent in-app notification carrying the
 * room code to a mutual friend who has not blocked the caller.
 */
export const rpcInviteFriend: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const callerId = requireUser(ctx);
  const req = JSON.parse(payload || '{}') as { userId?: string; code?: string };
  const targetId = req.userId || '';
  const code = normalizeCode(req.code);
  const hasTarget = targetId !== '' && targetId !== callerId;
  let roomExists = false;
  if (code) {
    const rows = nk.storageRead([{ collection: ROOM_COLLECTION, key: code, userId: SYSTEM_USER }]);
    roomExists = rows.length > 0;
  }
  const check: InviteCheck = {
    callerId,
    targetId,
    code,
    callerFriends: hasTarget ? friendStates(nk, callerId, FRIEND_STATE_MUTUAL) : {},
    targetFriends: hasTarget ? friendStates(nk, targetId, FRIEND_STATE_BLOCKED) : {},
    roomExists,
  };
  const error = inviteError(check);
  if (error) throw Error(error);
  const caller = nk.usersGetId([callerId])[0];
  const fromName = caller ? caller.displayName || caller.username : 'A friend';
  nk.notificationSend(targetId, 'Room invite', { code, fromName, fromUserId: callerId }, INVITE_CODE, callerId, true);
  logger.info('invite %s -> %s room %s', callerId, targetId, code);
  return JSON.stringify({ ok: true });
};
