import { describe, expect, it } from 'vitest';
import { CLUB_LEAGUE, CLUB_WEEK, clubName, crestOf, mayKick, nextOwner, weekPoints } from './clubs';
import { creditClub, rpcClubCreate, rpcClubJoin, rpcClubKick, rpcClubLeave, rpcClubList, rpcClubState } from './rpc_clubs';
import { ALICE, BOB, call, fakeNk, userCtx } from './test_support';

const CAROL = '2f8fad5b-d9cb-469f-a165-70867728950e';

/** fakeNk plus enough of Nakama's groups, users and leaderboards for the club RPCs. */
function clubNk() {
  const { nk } = fakeNk();
  const groups = new Map<string, nkruntime.Group>();
  const members = new Map<string, Map<string, number>>();
  const boards = new Map<string, Map<string, { score: number; username: string; metadata: { [k: string]: unknown } }>>();
  let serial = 0;
  const names = new Set<string>();
  const ext = {
    usersGetId: (ids: string[]) => ids.map((id) => ({ userId: id, username: 'u' + id.slice(0, 2) })),
    groupCreate: (userId: string, name: string, _c: string, _l: string, _d: string, _a: string, open: boolean, metadata: { [k: string]: unknown }, limit: number) => {
      if (names.has(name)) throw new Error('name taken');
      names.add(name);
      const id = `9${('0000000' + ++serial).slice(-7)}-d9cb-469f-a165-70867728950e`;
      const g = { id, name, open, metadata, maxCount: limit, edgeCount: 1 } as unknown as nkruntime.Group;
      groups.set(id, g);
      members.set(id, new Map([[userId, 0]]));
      return g;
    },
    groupsGetId: (ids: string[]) => ids.map((id) => groups.get(id)).filter((g) => !!g),
    groupsList: () => ({ groups: [...groups.values()], cursor: '' }),
    groupUserJoin: (id: string, userId: string) => { members.get(id)!.set(userId, 2); groups.get(id)!.edgeCount++; },
    groupUserLeave: (id: string, userId: string) => {
      const m = members.get(id)!;
      if (m.get(userId) === 0 && [...m.values()].filter((s) => s === 0).length === 1 && m.size > 1) throw new Error('last superadmin');
      m.delete(userId); groups.get(id)!.edgeCount--;
    },
    groupUsersKick: (id: string, ids: string[]) => { for (const u of ids) { members.get(id)!.delete(u); groups.get(id)!.edgeCount--; } },
    groupUsersPromote: (id: string, ids: string[]) => { const m = members.get(id)!; for (const u of ids) m.set(u, Math.max(0, (m.get(u) ?? 2) - 1)); },
    groupDelete: (id: string) => { names.delete(groups.get(id)!.name); groups.delete(id); members.delete(id); },
    userGroupsList: (userId: string) => ({
      userGroups: [...members.entries()].filter(([, m]) => m.has(userId)).map(([id, m]) => ({ group: groups.get(id), state: m.get(userId) })),
    }),
    groupUsersList: (id: string) => ({ groupUsers: [...(members.get(id) || new Map()).entries()].map(([u, s]) => ({ user: { userId: u, username: 'u' + u.slice(0, 2) }, state: s })) }),
    leaderboardRecordWrite: (board: string, owner: string, username: string, score: number, _s: number, metadata: { [k: string]: unknown }) => {
      const b = boards.get(board) || new Map();
      boards.set(board, b);
      const prev = b.get(owner);
      b.set(owner, { score: (prev ? prev.score : 0) + score, username, metadata });
    },
    leaderboardRecordDelete: (board: string, owner: string) => { boards.get(board)?.delete(owner); },
    leaderboardRecordsList: (board: string, owners: string[]) => {
      const rows = [...(boards.get(board) || new Map()).entries()]
        .sort((a, b) => b[1].score - a[1].score)
        .map(([ownerId, r], i) => ({ ownerId, username: r.username, score: r.score, metadata: r.metadata, rank: i + 1 }));
      return { records: rows, ownerRecords: rows.filter((r) => owners.indexOf(r.ownerId) >= 0) };
    },
  };
  Object.assign(nk, ext);
  return { nk, members, boards };
}

describe('club rules', () => {
  it('names come from the word lists only', () => {
    expect(clubName(0, 0, 7)).toBe('Bold Ventures 7');
    expect(clubName(16, 0, 7)).toBe('');
    expect(clubName(0, 0, 1000)).toBe('');
    expect(crestOf({ crest: 5 })).toBe(5);
    expect(crestOf({ crest: 'x' })).toBe(0);
  });

  it('owners remove anyone else, admins only members', () => {
    expect(mayKick(0, 2)).toBe(true);
    expect(mayKick(0, 1)).toBe(true);
    expect(mayKick(1, 1)).toBe(false);
    expect(mayKick(1, 2)).toBe(true);
    expect(mayKick(2, 2)).toBe(false);
    expect(mayKick(0, 3)).toBe(false);
  });

  it('the club passes to an admin first, then the first member', () => {
    expect(nextOwner([{ userId: 'a', state: 0 }, { userId: 'b', state: 2 }, { userId: 'c', state: 1 }], 'a')).toBe('c');
    expect(nextOwner([{ userId: 'a', state: 0 }, { userId: 'b', state: 2 }], 'a')).toBe('b');
    expect(nextOwner([{ userId: 'a', state: 0 }], 'a')).toBe('');
  });

  it('week points count only for the club they were earned in', () => {
    expect(weekPoints({ score: 30, metadata: { club: 'x' } }, 'x')).toBe(30);
    expect(weekPoints({ score: 30, metadata: { club: 'y' } }, 'x')).toBe(0);
    expect(weekPoints(undefined, 'x')).toBe(0);
  });
});

describe('club RPCs', () => {
  it('create, join, credit games and show the league', () => {
    const { nk } = clubNk();
    const club = call(rpcClubCreate, userCtx(ALICE), nk, { adjective: 2, noun: 3, crest: 4 });
    expect(club.name).toMatch(/^Steady Traders \d+$/);
    expect(() => call(rpcClubCreate, userCtx(ALICE), nk, { adjective: 0, noun: 0, crest: 0 })).toThrow('leave your club first');
    expect(() => call(rpcClubCreate, userCtx(BOB), nk, { adjective: 0, noun: 0, crest: 9 })).toThrow('invalid crest');
    expect(call(rpcClubList, userCtx(BOB), nk, {}).clubs.map((c: { id: string }) => c.id)).toEqual([club.id]);
    call(rpcClubJoin, userCtx(BOB), nk, { clubId: club.id });
    creditClub(nk, ALICE, 'alice', 12);
    creditClub(nk, BOB, 'bob', 20);
    creditClub(nk, CAROL, 'carol', 50); // no club: nothing
    const state = call(rpcClubState, userCtx(BOB), nk, {});
    expect(state.club.score).toBe(32);
    expect(state.club.rank).toBe(1);
    expect(state.club.members.map((m: { week: number; role: string }) => [m.week, m.role])).toEqual([[20, 'member'], [12, 'owner']]);
    expect(state.league).toEqual([{ id: club.id, name: club.name, crest: 4, score: 32, rank: 1 }]);
  });

  it('a full club cannot be joined', () => {
    const { nk } = clubNk();
    const club = call(rpcClubCreate, userCtx(ALICE), nk, { adjective: 0, noun: 0, crest: 0 });
    (nk.groupsGetId([club.id])[0] as { edgeCount: number }).edgeCount = 30;
    expect(() => call(rpcClubJoin, userCtx(BOB), nk, { clubId: club.id })).toThrow('club is full');
  });

  it('moving clubs starts the weekly part from zero; the old club keeps its points', () => {
    const { nk, boards } = clubNk();
    const a = call(rpcClubCreate, userCtx(ALICE), nk, { adjective: 0, noun: 0, crest: 0 });
    const c = call(rpcClubCreate, userCtx(CAROL), nk, { adjective: 1, noun: 1, crest: 1 });
    call(rpcClubJoin, userCtx(BOB), nk, { clubId: a.id });
    creditClub(nk, BOB, 'bob', 20);
    call(rpcClubLeave, userCtx(BOB), nk, {});
    expect(boards.get(CLUB_WEEK)!.has(BOB)).toBe(false);
    call(rpcClubJoin, userCtx(BOB), nk, { clubId: c.id });
    creditClub(nk, BOB, 'bob', 5);
    expect(boards.get(CLUB_LEAGUE)!.get(a.id)!.score).toBe(20);
    expect(call(rpcClubState, userCtx(BOB), nk, {}).club.members.find((m: { userId: string }) => m.userId === BOB).week).toBe(5);
  });

  it('an owner who leaves hands the club on; the last one out closes it', () => {
    const { nk, members } = clubNk();
    const club = call(rpcClubCreate, userCtx(ALICE), nk, { adjective: 0, noun: 0, crest: 0 });
    call(rpcClubJoin, userCtx(BOB), nk, { clubId: club.id });
    call(rpcClubLeave, userCtx(ALICE), nk, {});
    expect(members.get(club.id)!.get(BOB)).toBe(0);
    call(rpcClubLeave, userCtx(BOB), nk, {});
    expect(members.has(club.id)).toBe(false);
  });

  it('only owners and admins remove members', () => {
    const { nk, members } = clubNk();
    const club = call(rpcClubCreate, userCtx(ALICE), nk, { adjective: 0, noun: 0, crest: 0 });
    call(rpcClubJoin, userCtx(BOB), nk, { clubId: club.id });
    call(rpcClubJoin, userCtx(CAROL), nk, { clubId: club.id });
    expect(() => call(rpcClubKick, userCtx(BOB), nk, { userId: CAROL })).toThrow('not allowed');
    call(rpcClubKick, userCtx(ALICE), nk, { userId: CAROL });
    expect(members.get(club.id)!.has(CAROL)).toBe(false);
  });
});
