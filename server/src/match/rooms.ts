/** Room-code RPCs: create_room, join_room, quick_play. Registered by main.ts. */
import { normalizeCode, parseBody, readBool, readInt, reject, requireUser } from './input';
import { clampStepSeconds, DEFAULT_PARAMS, MATCH_MODULE, SYSTEM_USER, TUTORIAL_SEED } from './protocol';
import { checkRate } from './ratelimit';
import { readRemoteConfig } from './rpc_config';

export { SYSTEM_USER } from './protocol';

export const ROOM_COLLECTION = 'rooms';
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I; keep in sync with ROOM_CODE_RE
const CODE_ATTEMPTS = 5;

function makeCode(): string {
  let code = '';
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return code;
}

/** The match a room row points to, or null when it has ended or never existed. */
function liveMatchId(nk: nkruntime.Nakama, row: nkruntime.StorageObject | undefined): string | null {
  if (!row) return null;
  const matchId = (row.value as { matchId?: unknown }).matchId;
  if (typeof matchId !== 'string' || !matchId) return null;
  try {
    return nk.matchGet(matchId) ? matchId : null;
  } catch (e) {
    return null;
  }
}

/** The live match behind a room code, or null when there is none. */
export function roomMatchId(nk: nkruntime.Nakama, code: string): string | null {
  return liveMatchId(nk, nk.storageRead([{ collection: ROOM_COLLECTION, key: code, userId: SYSTEM_USER }])[0]);
}

/** RPC create_room: creates a private match and returns { code, matchId }. */
export const rpcCreateRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const stepSeconds = clampStepSeconds(req['stepSeconds']);
  const maxSeats = readInt(req, 'maxSeats', 2, 7, 7);
  checkRate(nk, userId, 'create_room', Date.now());
  // WHY: 32^6 codes make a collision with a live room vanishingly rare, but a
  // row whose match has ended must not block its code forever, and after the
  // last attempt the code must never be handed out twice.
  let code = '';
  for (let attempt = 0; attempt < CODE_ATTEMPTS && !code; attempt++) {
    const candidate = makeCode();
    const existing = nk.storageRead([{ collection: ROOM_COLLECTION, key: candidate, userId: SYSTEM_USER }]);
    if (liveMatchId(nk, existing[0]) === null) code = candidate;
  }
  if (!code) reject('try again');
  const matchId = nk.matchCreate(MATCH_MODULE, { isPrivate: true, roomCode: code, minSeats: 3, maxSeats, stepSeconds, hostId: userId });
  nk.storageWrite([
    {
      collection: ROOM_COLLECTION,
      key: code,
      userId: SYSTEM_USER,
      value: { matchId, createdBy: userId, createdAt: Date.now() },
      // WHY: server-only. With public read a client could list the system
      // user's `rooms` collection and enumerate every live room code.
      permissionRead: 0,
      permissionWrite: 0,
    },
  ]);
  logger.info('room %s -> %s', code, matchId);
  return JSON.stringify({ code, matchId });
};

/** RPC join_room: resolves a room code to a match id; stale rows are removed. */
export const rpcJoinRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  requireUser(ctx);
  const code = normalizeCode(parseBody(payload)['code']);
  if (!code) reject('invalid code');
  const rows = nk.storageRead([{ collection: ROOM_COLLECTION, key: code, userId: SYSTEM_USER }]);
  const matchId = liveMatchId(nk, rows[0]);
  if (!matchId) {
    if (rows[0]) nk.storageDelete([{ collection: ROOM_COLLECTION, key: code, userId: SYSTEM_USER }]);
    reject('room not found');
  }
  return JSON.stringify({ code, matchId });
};

/**
 * RPC quick_play: finds an open public lobby with room or creates one.
 * Simpler than the matchmaker for a turn-based game with bot fill.
 * With {"tutorial": true} it creates a solo tutorial match instead, and with
 * {"bots": true} a game against bots that starts as soon as the caller joins.
 */
export const rpcQuickPlay: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  // WHY: every tutorial call, and a call with no open lobby, creates a match
  // that ticks until it empties; without a budget one account could start
  // thousands.
  checkRate(nk, userId, 'quick_play', Date.now());
  const body = parseBody(payload);
  if (readBool(body, 'tutorial')) {
    const tutorialId = nk.matchCreate(MATCH_MODULE, { tutorial: true, seed: TUTORIAL_SEED });
    logger.info('tutorial created %s', tutorialId);
    return JSON.stringify({ matchId: tutorialId, tutorial: true });
  }
  if (readBool(body, 'bots')) {
    const botsId = nk.matchCreate(MATCH_MODULE, { solo: true, hostId: userId });
    logger.info('bot game created %s', botsId);
    return JSON.stringify({ matchId: botsId, bots: true });
  }
  const query = '+label.mode:public +label.open:yes';
  const matches = nk.matchList(10, true, null, 0, DEFAULT_PARAMS.maxSeats - 1, query);
  const open = matches[0];
  if (open) return JSON.stringify({ matchId: open.matchId });
  const matchId = nk.matchCreate(MATCH_MODULE, { isPrivate: false, lobbyWaitSeconds: readRemoteConfig(nk).quickPlayWaitSeconds });
  logger.info('quick play created %s', matchId);
  return JSON.stringify({ matchId });
};

/** RPC get_profile: progression, the daily bonus flag, and the quest / cosmetic track. */
