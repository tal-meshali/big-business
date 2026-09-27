/**
 * Nakama runtime entry point. Registers the Big Business match handler, the
 * room-code RPCs and the matchmaker hook.
 */
import { matchInit, matchJoin, matchJoinAttempt, matchLeave, matchLoop, matchSignal, matchTerminate } from './match/handler';
import { DEFAULT_PARAMS, MATCH_MODULE } from './match/protocol';

const ROOM_COLLECTION = 'rooms';
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

function makeCode(): string {
  let code = '';
  for (let i = 0; i < 6; i++) code += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return code;
}

/** RPC create_room: creates a private match and returns { code, matchId }. */
const rpcCreateRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const req = payload ? (JSON.parse(payload) as { stepSeconds?: number; maxSeats?: number }) : {};
  let code = makeCode();
  for (let attempt = 0; attempt < 5; attempt++) {
    const existing = nk.storageRead([{ collection: ROOM_COLLECTION, key: code, userId: '00000000-0000-0000-0000-000000000000' }]);
    if (existing.length === 0) break;
    code = makeCode();
  }
  const matchId = nk.matchCreate(MATCH_MODULE, {
    isPrivate: true,
    roomCode: code,
    minSeats: 3,
    maxSeats: Math.min(7, Math.max(2, req.maxSeats || 7)),
    stepSeconds: req.stepSeconds === undefined ? DEFAULT_PARAMS.stepSeconds : req.stepSeconds,
  });
  nk.storageWrite([
    {
      collection: ROOM_COLLECTION,
      key: code,
      userId: '00000000-0000-0000-0000-000000000000',
      value: { matchId, createdBy: ctx.userId, createdAt: Date.now() },
      permissionRead: 2,
      permissionWrite: 0,
    },
  ]);
  logger.info('room %s -> %s', code, matchId);
  return JSON.stringify({ code, matchId });
};

/** RPC join_room: resolves a room code to a match id. */
const rpcJoinRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void ctx; void logger;
  const req = JSON.parse(payload || '{}') as { code?: string };
  const code = (req.code || '').toUpperCase().trim();
  if (code.length !== 6) throw Error('invalid code');
  const rows = nk.storageRead([{ collection: ROOM_COLLECTION, key: code, userId: '00000000-0000-0000-0000-000000000000' }]);
  const row = rows[0];
  if (!row) throw Error('room not found');
  const value = row.value as { matchId: string };
  return JSON.stringify({ code, matchId: value.matchId });
};

/**
 * RPC quick_play: finds an open public lobby with room or creates one.
 * Simpler than the matchmaker for a turn-based game with bot fill.
 */
const rpcQuickPlay: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void ctx; void payload;
  const query = '+label.mode:public +label.open:1';
  const matches = nk.matchList(10, true, '', 0, DEFAULT_PARAMS.maxSeats - 1, query);
  const open = matches[0];
  if (open) return JSON.stringify({ matchId: open.matchId });
  const matchId = nk.matchCreate(MATCH_MODULE, { isPrivate: false });
  logger.info('quick play created %s', matchId);
  return JSON.stringify({ matchId });
};

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {
  void ctx; void nk;
  initializer.registerMatch(MATCH_MODULE, {
    matchInit,
    matchJoinAttempt,
    matchJoin,
    matchLeave,
    matchLoop,
    matchTerminate,
    matchSignal,
  });
  initializer.registerRpc('create_room', rpcCreateRoom);
  initializer.registerRpc('join_room', rpcJoinRoom);
  initializer.registerRpc('quick_play', rpcQuickPlay);
  logger.info('Big Business runtime loaded');
}

// Reference so the bundler keeps the global entry point.
!InitModule && InitModule.bind(null);
