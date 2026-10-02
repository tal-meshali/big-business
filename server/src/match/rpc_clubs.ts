/**
 * Club RPCs: create, browse, join, leave and remove members, the club
 * screen's state with this week's league, and the step that credits a
 * finished game to the player's club. Clubs are Nakama groups that only the
 * server creates or joins (the client-side group API is closed by the
 * before hooks below), so the one-club rule and the word-list names hold.
 */
import {
  CLUB_LEAGUE,
  CLUB_MAX_MEMBERS,
  CLUB_WEEK,
  clubName,
  crestOf,
  isCrest,
  isMemberState,
  LEAGUE_TOP,
  mayKick,
  nextOwner,
  roleName,
  weekPoints,
} from './clubs';
import { isUserId, parseBody, readString, reject, requireUser, type Body } from './input';
import { checkRate } from './ratelimit';

/** Attempts at a free name number before giving up. */
const NAME_TRIES = 6;

export interface ClubInfo {
  id: string;
  name: string;
  crest: number;
  state: number | undefined;
}

/** The player's club, or null. */
export function clubOf(nk: nkruntime.Nakama, userId: string): ClubInfo | null {
  const list = nk.userGroupsList(userId, 10);
  for (const ug of list.userGroups || []) {
    if (ug.group && isMemberState(ug.state)) return { id: ug.group.id, name: ug.group.name, crest: crestOf(ug.group.metadata), state: ug.state };
  }
  return null;
}

function members(nk: nkruntime.Nakama, clubId: string): Array<{ userId: string; name: string; state: number | undefined }> {
  const out: Array<{ userId: string; name: string; state: number | undefined }> = [];
  const list = nk.groupUsersList(clubId, 100);
  for (const gu of list.groupUsers || []) {
    if (gu.user && isMemberState(gu.state)) out.push({ userId: gu.user.userId, name: gu.user.username, state: gu.state });
  }
  return out;
}

function usernameOf(nk: nkruntime.Nakama, userId: string): string {
  const u = nk.usersGetId([userId])[0];
  return u ? u.username : '';
}

function readIndex(req: Body, key: string, count: number): number {
  const v = req[key];
  if (typeof v !== 'number' || Math.floor(v) !== v || v < 0 || v >= count) reject('invalid ' + key);
  return v;
}

function readClubId(req: Body): string {
  const id = req['clubId'];
  if (!isUserId(id)) reject('invalid club');
  return id;
}

function leagueRow(r: nkruntime.LeaderboardRecord): { id: string; name: string; crest: number; score: number; rank: number } {
  return { id: r.ownerId, name: r.username, crest: crestOf(r.metadata), score: r.score, rank: r.rank };
}

function leagueRank(league: Array<{ id: string; rank: number }>, clubId: string, own: nkruntime.LeaderboardRecord | undefined): number {
  const row = league.filter((c) => c.id === clubId)[0];
  if (row) return row.rank;
  return own && own.rank > 0 ? own.rank : 0;
}

/** RPC club_state: the player's club with members and this week's points, and the league table. */
export const rpcClubState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const board = nk.leaderboardRecordsList(CLUB_LEAGUE, [], LEAGUE_TOP);
  const league = (board.records || []).map(leagueRow);
  const club = clubOf(nk, userId);
  if (!club) return JSON.stringify({ club: null, league, max: CLUB_MAX_MEMBERS });
  const list = members(nk, club.id);
  const week = nk.leaderboardRecordsList(CLUB_WEEK, list.map((m) => m.userId), 1);
  const byOwner: { [id: string]: nkruntime.LeaderboardRecord } = {};
  for (const r of week.ownerRecords || []) byOwner[r.ownerId] = r;
  const mine = nk.leaderboardRecordsList(CLUB_LEAGUE, [club.id], 1).ownerRecords || [];
  const rows = list
    .map((m) => ({ userId: m.userId, name: m.name, role: roleName(m.state), week: weekPoints(byOwner[m.userId], club.id) }))
    .sort((a, b) => b.week - a.week || (a.name < b.name ? -1 : 1));
  return JSON.stringify({
    club: {
      id: club.id,
      name: club.name,
      crest: club.crest,
      role: roleName(club.state),
      members: rows,
      // WHY the table first: owner records can come back unranked (rank 0)
      // while Nakama's rank cache catches up; positions in the table cannot.
      rank: leagueRank(league, club.id, mine[0]),
      score: mine[0] ? mine[0].score : 0,
    },
    league,
    max: CLUB_MAX_MEMBERS,
  });
};

/** RPC club_list: open clubs with room, for the join screen. */
export const rpcClubList: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'club_list', Date.now());
  const req = parseBody(payload);
  const cursor = readString(req, 'cursor', 512);
  const list = nk.groupsList(undefined, undefined, true, undefined, 20, cursor || undefined);
  const clubs = (list.groups || [])
    .filter((g) => g.edgeCount < g.maxCount)
    .map((g) => ({ id: g.id, name: g.name, crest: crestOf(g.metadata), count: g.edgeCount, max: g.maxCount }));
  return JSON.stringify({ clubs, cursor: list.cursor || '' });
};

/** RPC club_create {adjective, noun, crest}: a new club with the caller as owner. */
export const rpcClubCreate: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'club_create', Date.now());
  const req = parseBody(payload);
  const adjective = readIndex(req, 'adjective', 16);
  const noun = readIndex(req, 'noun', 16);
  const crest = req['crest'];
  if (!isCrest(crest)) reject('invalid crest');
  if (clubOf(nk, userId)) reject('leave your club first');
  for (let i = 0; i < NAME_TRIES; i++) {
    const name = clubName(adjective, noun, 1 + Math.floor(Math.random() * 999));
    let group: nkruntime.Group;
    try {
      group = nk.groupCreate(userId, name, userId, 'en', '', '', true, { crest }, CLUB_MAX_MEMBERS);
    } catch (e) {
      // Taken names fail here; try another number.
      logger.debug('club name %s: %s', name, String(e));
      continue;
    }
    resetWeek(nk, userId);
    return JSON.stringify({ id: group.id, name: group.name, crest });
  }
  return reject('try other words');
};

/** RPC club_join {clubId}: joins an open club that has room. */
export const rpcClubJoin: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'club_join', Date.now());
  const clubId = readClubId(parseBody(payload));
  if (clubOf(nk, userId)) reject('leave your club first');
  const group = nk.groupsGetId([clubId])[0];
  if (!group || !group.open) reject('club not found');
  if (group.edgeCount >= group.maxCount) reject('club is full');
  nk.groupUserJoin(clubId, userId, usernameOf(nk, userId));
  resetWeek(nk, userId);
  return JSON.stringify({ id: group.id, name: group.name, crest: crestOf(group.metadata) });
};

/**
 * RPC club_leave: leaves the club. An owner hands the club to the next
 * admin or member first; the last member out closes it.
 */
export const rpcClubLeave: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const club = clubOf(nk, userId);
  if (!club) reject('not in a club');
  const list = members(nk, club.id);
  const heir = nextOwner(list, userId);
  if (!heir) {
    nk.groupDelete(club.id);
    try {
      nk.leaderboardRecordDelete(CLUB_LEAGUE, club.id);
    } catch (e) {
      logger.debug('league record delete: %s', String(e));
    }
  } else {
    const heirRow = list.filter((m) => m.userId === heir)[0];
    const heirState = heirRow ? heirRow.state : 2;
    if (club.state === 0 && heirState !== 0) {
      // Promote until the heir is an owner too (member -> admin -> owner).
      for (let i = heirState === 2 ? 2 : 1; i > 0; i--) nk.groupUsersPromote(club.id, [heir]);
    }
    nk.groupUserLeave(club.id, userId, usernameOf(nk, userId));
  }
  resetWeek(nk, userId);
  return JSON.stringify({ left: club.id });
};

/** RPC club_kick {userId}: an owner or admin removes a member. */
export const rpcClubKick: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'club_kick', Date.now());
  const target = parseBody(payload)['userId'];
  if (!isUserId(target) || target === userId) reject('invalid player');
  const club = clubOf(nk, userId);
  if (!club) reject('not in a club');
  const them = members(nk, club.id).find((m) => m.userId === target);
  if (!them || !mayKick(club.state, them.state)) reject('not allowed');
  nk.groupUsersKick(club.id, [target]);
  resetWeek(nk, target);
  return JSON.stringify({ removed: target });
};

/**
 * Adds a finished game's season points to the player's club and to their
 * own weekly contribution. Best effort: called inside the awards step,
 * which logs and continues on failure.
 */
export function creditClub(nk: nkruntime.Nakama, userId: string, name: string, points: number): void {
  if (points <= 0) return;
  const club = clubOf(nk, userId);
  if (!club) return;
  nk.leaderboardRecordWrite(CLUB_LEAGUE, club.id, club.name, points, 0, { crest: club.crest });
  nk.leaderboardRecordWrite(CLUB_WEEK, userId, name, points, 0, { club: club.id });
}

/**
 * WHY on every join and leave: the weekly record keeps adding up, so a
 * player who moves clubs would otherwise bring last club's points along.
 * The club league keeps what they earned for the old club.
 */
function resetWeek(nk: nkruntime.Nakama, userId: string): void {
  try {
    nk.leaderboardRecordDelete(CLUB_WEEK, userId);
  } catch (e) {
    // No record yet.
  }
}

/**
 * Before hook for the client's CreateGroup, UpdateGroup, JoinGroup and
 * AddGroupUsers: clubs are only created, renamed and joined through the
 * RPCs above. One function for all four keeps main.ts small.
 */
export const beforeGroupChange: nkruntime.BeforeHookFunction<any> = () => reject('use the Clubs screen');

/**
 * WHY no chat channels (decision D4): the game has no free text, but every
 * club is also a Nakama chat room any client could join. Closing channel
 * joins keeps clubs (and direct messages) text-free for every age.
 */
export const beforeChannelJoin: nkruntime.RtBeforeHookFunction<nkruntime.EnvelopeChannelJoin> = () => {
  reject('chat is not available');
};
