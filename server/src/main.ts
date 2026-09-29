/**
 * Nakama runtime entry point. Registers the Big Business match handler, the
 * room-code, profile, moderation, social, account-link, quest and cosmetic RPCs.
 *
 * Every RPC goes through `guardRpc` (only messages raised with `reject`
 * reach the client) and reads its payload through the validators in
 * match/input.ts: the client is untrusted.
 */
import { matchInit, matchJoin, matchJoinAttempt, matchLeave, matchLoop, matchSignal, matchTerminate } from './match/handler';
import { guardRpc, isClientError, isUserId, MATCH_ID_MAX, normalizeCode, parseBody, readBool, readInt, readString, reject, REPORT_NOTE_MAX, requireUser } from './match/input';
import { loadProfile, readProgress, saveProfile } from './match/profile';
import { claimDaily, SEASON_LEADERBOARD, utcDate } from './match/progression';
import { DEFAULT_PARAMS, MATCH_MODULE, TUTORIAL_SEED } from './match/protocol';
import { checkRate } from './match/ratelimit';
import { profileExtras, rpcClaimQuest, rpcEquipCosmetic } from './match/rpc_quests';
import { rpcAccountLinks, rpcFindPlayer, rpcInviteFriend } from './match/social';

const SYSTEM_USER = '00000000-0000-0000-0000-000000000000';
const REPORT_COLLECTION = 'reports';
const REPORT_REASONS = ['name', 'behaviour', 'cheating', 'other'];

const ROOM_COLLECTION = 'rooms';
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I; keep in sync with ROOM_CODE_RE
const CODE_ATTEMPTS = 5;
const MIN_STEP_SECONDS = 5;
const MAX_STEP_SECONDS = 120;

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

/** RPC create_room: creates a private match and returns { code, matchId }. */
const rpcCreateRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const stepSeconds = readInt(req, 'stepSeconds', MIN_STEP_SECONDS, MAX_STEP_SECONDS, DEFAULT_PARAMS.stepSeconds);
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
  const matchId = nk.matchCreate(MATCH_MODULE, { isPrivate: true, roomCode: code, minSeats: 3, maxSeats, stepSeconds });
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
const rpcJoinRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
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
 * With {"tutorial": true} it creates a solo tutorial match instead.
 */
const rpcQuickPlay: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  requireUser(ctx);
  if (readBool(parseBody(payload), 'tutorial')) {
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

/** RPC get_profile: progression, the daily bonus flag, and the quest / cosmetic track. */
const rpcGetProfile: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const now = Date.now();
  const p = readProgress(nk, requireUser(ctx));
  return JSON.stringify({ progress: p, dailyAvailable: p.lastDailyClaim !== utcDate(now), ...profileExtras(p, now) });
};

/** RPC claim_daily: once per UTC day; streak grows on consecutive days. */
const rpcClaimDaily: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const row = loadProfile(nk, userId);
  const result = claimDaily(row.progress, Date.now());
  if (result.claimed) saveProfile(nk, userId, result.progress, row.version);
  return JSON.stringify({ claimed: result.claimed, xpAwarded: result.xpAwarded, progress: result.progress });
};

/**
 * RPC report_player: files a report into a moderation queue that only the
 * console can read (Apple 1.2 / Play UGC). Blocking is done client-side
 * through Nakama's friends API.
 *
 * WHY one row per (day, reporter, reported): repeated reports of the same
 * player update that row's count instead of growing the collection, and the
 * per-user rate limit bounds how many distinct rows a day one account adds.
 */
const rpcReportPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
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
const beforeAddFriends: nkruntime.BeforeHookFunction<nkruntime.AddFriendsRequest> = (ctx, logger, nk, data) => {
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
  initializer.registerRpc('create_room', guardRpc(rpcCreateRoom));
  initializer.registerRpc('join_room', guardRpc(rpcJoinRoom));
  initializer.registerRpc('quick_play', guardRpc(rpcQuickPlay));
  initializer.registerRpc('get_profile', guardRpc(rpcGetProfile));
  initializer.registerRpc('claim_daily', guardRpc(rpcClaimDaily));
  initializer.registerRpc('claim_quest', guardRpc(rpcClaimQuest));
  initializer.registerRpc('equip_cosmetic', guardRpc(rpcEquipCosmetic));
  initializer.registerRpc('report_player', guardRpc(rpcReportPlayer));
  initializer.registerRpc('find_player', guardRpc(rpcFindPlayer));
  initializer.registerRpc('invite_friend', guardRpc(rpcInviteFriend));
  initializer.registerRpc('account_links', guardRpc(rpcAccountLinks));
  initializer.registerBeforeAddFriends(beforeAddFriends);
  logger.info('Big Business runtime loaded');
}

// Reference so the bundler keeps the global entry point.
!InitModule && InitModule.bind(null);
