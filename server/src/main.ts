/**
 * Nakama runtime entry point. Registers the Big Business match handler and
 * the room-code, profile, moderation and social RPCs.
 */
import { matchInit, matchJoin, matchJoinAttempt, matchLeave, matchLoop, matchSignal, matchTerminate } from './match/handler';
import { DEFAULT_PARAMS, MATCH_MODULE, TUTORIAL_SEED } from './match/protocol';
import { claimDaily, emptyProgress, PROFILE_COLLECTION, PROFILE_KEY, SEASON_LEADERBOARD, utcDate, type Progress } from './match/progression';
import { rpcFindPlayer, rpcInviteFriend } from './match/social';

const SYSTEM_USER = '00000000-0000-0000-0000-000000000000';
const REPORT_COLLECTION = 'reports';
const REPORT_REASONS = ['name', 'behaviour', 'cheating', 'other'];

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
 * With {"tutorial": true} it creates a solo tutorial match instead.
 */
const rpcQuickPlay: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void ctx;
  const req = payload ? (JSON.parse(payload) as { tutorial?: boolean }) : {};
  if (req.tutorial) {
    const tutorialId = nk.matchCreate(MATCH_MODULE, { tutorial: true, seed: TUTORIAL_SEED });
    logger.info('tutorial created %s', tutorialId);
    return JSON.stringify({ matchId: tutorialId, tutorial: true });
  }
  const query = '+label.mode:public +label.open:yes';
  const matches = nk.matchList(10, true, null, 0, DEFAULT_PARAMS.maxSeats - 1, query);
  const open = matches[0];
  if (open) return JSON.stringify({ matchId: open.matchId });
  const matchId = nk.matchCreate(MATCH_MODULE, { isPrivate: false });
  logger.info('quick play created %s', matchId);
  return JSON.stringify({ matchId });
};

function requireUser(ctx: nkruntime.Context): string {
  if (!ctx.userId) throw Error('unauthenticated');
  return ctx.userId;
}

function readProgress(nk: nkruntime.Nakama, userId: string): Progress {
  const rows = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId }]);
  const row = rows[0];
  return row ? (row.value as Progress) : emptyProgress();
}

function writeProgress(nk: nkruntime.Nakama, userId: string, p: Progress): void {
  nk.storageWrite([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: p, permissionRead: 1, permissionWrite: 0 }]);
}

/** RPC get_profile: progression plus whether today's daily bonus is available. */
const rpcGetProfile: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const p = readProgress(nk, requireUser(ctx));
  return JSON.stringify({ progress: p, dailyAvailable: p.lastDailyClaim !== utcDate(Date.now()) });
};

/** RPC claim_daily: once per UTC day; streak grows on consecutive days. */
const rpcClaimDaily: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const result = claimDaily(readProgress(nk, userId), Date.now());
  if (result.claimed) writeProgress(nk, userId, result.progress);
  return JSON.stringify({ claimed: result.claimed, xpAwarded: result.xpAwarded, progress: result.progress });
};

/**
 * RPC report_player: files a report into a moderation queue that only the
 * console can read (Apple 1.2 / Play UGC). Blocking is done client-side
 * through Nakama's friends API.
 */
const rpcReportPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const reporter = requireUser(ctx);
  const req = JSON.parse(payload || '{}') as { userId?: string; reason?: string; matchId?: string; note?: string };
  if (!req.userId || req.userId === reporter) throw Error('invalid user');
  const reason = REPORT_REASONS.indexOf(req.reason || '') >= 0 ? (req.reason as string) : 'other';
  const key = `${Date.now()}-${reporter.slice(0, 8)}`;
  nk.storageWrite([
    {
      collection: REPORT_COLLECTION,
      key,
      userId: SYSTEM_USER,
      value: { reporter, reported: req.userId, reason, matchId: req.matchId || '', note: (req.note || '').slice(0, 200), at: Date.now() },
      permissionRead: 0,
      permissionWrite: 0,
    },
  ]);
  logger.info('report filed %s by %s against %s (%s)', key, reporter, req.userId, reason);
  return JSON.stringify({ ok: true });
};

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {
  void ctx;
  // Monthly season: authoritative, descending, points accumulate, resets on the 1st.
  try {
    // nkruntime is types only at runtime, so pass the enum string values.
    nk.leaderboardCreate(SEASON_LEADERBOARD, true, 'descending' as nkruntime.SortOrder, 'increment' as nkruntime.Operator, '0 0 1 * *');
  } catch (e) {
    logger.warn('leaderboard create: %s', String(e));
  }
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
  initializer.registerRpc('get_profile', rpcGetProfile);
  initializer.registerRpc('claim_daily', rpcClaimDaily);
  initializer.registerRpc('report_player', rpcReportPlayer);
  initializer.registerRpc('find_player', rpcFindPlayer);
  initializer.registerRpc('invite_friend', rpcInviteFriend);
  logger.info('Big Business runtime loaded');
}

// Reference so the bundler keeps the global entry point.
!InitModule && InitModule.bind(null);
