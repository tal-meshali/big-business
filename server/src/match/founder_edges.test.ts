import { describe, expect, it } from 'vitest';
import { rpcSetAgeBracket } from './rpc_designer';
import { rpcFounderState, rpcReportCompanies, rpcSaveCompany, rpcSetCompaniesActive, rpcUploadCompanyLogo } from './rpc_founder';
import { rpcCompanyQueue, rpcModerateCompanies } from './rpc_founder_moderation';
import { rpcSetRemoteConfig } from './rpc_config';
import { chooseRoomDeck } from './room_deck';
import { writeStanding, readStanding } from './designer_store';
import { STRIKES_TO_BAN } from './designer';
import { clashWith, emptyRow, nameProblem, setCompany, shortName } from './founder';
import type { MatchState } from './state';
import { PURCHASE_COLLECTION, PURCHASE_KEY } from './store';
import { ALICE, BOB, call, fakeNk, fakeWebp, logger, serverCtx, userCtx } from './test_support';

/** Edge cases probed by the tester on top of rpc_founder.test.ts. */

function grant(nk: nkruntime.Nakama, userId: string, owned: string[], expires: { [id: string]: number } = {}) {
  nk.storageWrite([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId, value: { owned, syncedAt: 1, expires }, permissionRead: 1, permissionWrite: 0 }]);
}

function room(hostId: string): MatchState {
  const seats = [ALICE, BOB];
  const presences: { [id: string]: nkruntime.Presence } = {};
  for (const id of seats) presences[id] = { userId: id, sessionId: 's' + id, username: id, node: 'n' } as nkruntime.Presence;
  const seatByUser: { [id: string]: number } = {};
  seats.forEach((id, i) => (seatByUser[id] = i));
  return {
    params: { isPrivate: true, minSeats: 3, maxSeats: 5, stepSeconds: 30, lobbyWaitSeconds: 20, tutorial: false, solo: false, seed: 0, hostId },
    presences, seatByUser, game: { seats: seats.map((id) => ({ id })) }, customDeck: null,
  } as unknown as MatchState;
}

const ROCKET = { company: 2, name: 'Rocket Mail', color: 'teal', logo: 'rocket' };

describe('Founder edge cases', () => {
  it('a lapsed Plus hides the companies, keeps the row, and an unlock brings them back', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['plus'], { plus: Date.now() + 86_400_000 });
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true });
    const s = room(ALICE);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck!.companies![2]).toMatchObject({ name: 'Rocket Mail' });
    grant(nk, ALICE, ['plus'], { plus: Date.now() - 1000 });
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
    const st = call(rpcFounderState, userCtx(ALICE), nk, {});
    expect(st).toMatchObject({ owned: false, active: false });
    expect(st.companies.every((c: unknown) => c === null)).toBe(true);
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET)).toThrow('Founder is not unlocked');
    // Switching off still works without the unlock; on does not.
    expect(call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: false })).toEqual({ active: false });
    expect(() => call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true })).toThrow('Founder is not unlocked');
    // A lapsed owner's names are not reportable (nobody sees them).
    call(rpcReportCompanies, userCtx(BOB), nk, { userId: ALICE });
    expect(call(rpcCompanyQueue, serverCtx, nk, {}).items).toEqual([]);
    // Buying Founder later brings the saved row back.
    grant(nk, ALICE, ['founder']);
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies[2]).toMatchObject({ name: 'Rocket Mail' });
  });

  it('a banned host keeps editing but nobody sees the companies or new pictures', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSetAgeBracket, userCtx(ALICE), nk, { bracket: '16plus', region: 'US' });
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true });
    const cur = readStanding(nk, ALICE);
    writeStanding(nk, ALICE, { ...cur.standing, strikes: STRIKES_TO_BAN }, cur.version);
    const st = call(rpcFounderState, userCtx(ALICE), nk, {});
    expect(st).toMatchObject({ banned: true, uploadBlocker: 'banned' });
    const s = room(ALICE);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
    expect(() => call(rpcUploadCompanyLogo, userCtx(ALICE), nk, { company: 2, image: fakeWebp(192, 192, 700) })).toThrow();
    // Editing names is still allowed (they are not shown anyway).
    expect(call(rpcSaveCompany, userCtx(ALICE), nk, { ...ROCKET, name: 'Rocket Post' }).company.name).toBe('Rocket Post');
  });

  it('the kill switch stops every edit but switching off', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    call(rpcSetRemoteConfig, serverCtx, nk, { companiesEnabled: false });
    expect(call(rpcFounderState, userCtx(ALICE), nk, {})).toMatchObject({ enabled: false, owned: true });
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET)).toThrow('switched off');
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, { company: 2, reset: true })).toThrow('switched off');
    expect(() => call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true })).toThrow('switched off');
    expect(() => call(rpcUploadCompanyLogo, userCtx(ALICE), nk, { company: 2, image: fakeWebp(192, 192, 700) })).toThrow('switched off');
    expect(call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: false })).toEqual({ active: false });
  });

  it('moderation: keep leaves the names, bad verdicts and users are refused', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true });
    call(rpcReportCompanies, userCtx(BOB), nk, { userId: ALICE });
    call(rpcReportCompanies, userCtx(BOB), nk, { userId: ALICE });
    expect(call(rpcCompanyQueue, serverCtx, nk, {}).items[0]).toMatchObject({ reports: 2, current: [null, null, 'Rocket Mail', null, null, null] });
    expect(() => call(rpcModerateCompanies, serverCtx, nk, { userId: ALICE, verdict: 'ban' })).toThrow('invalid verdict');
    expect(() => call(rpcModerateCompanies, serverCtx, nk, { userId: 'x', verdict: 'keep' })).toThrow('invalid user');
    expect(() => call(rpcModerateCompanies, userCtx(BOB), nk, { userId: ALICE, verdict: 'reset' })).toThrow();
    expect(call(rpcModerateCompanies, serverCtx, nk, { userId: ALICE, verdict: 'keep' })).toMatchObject({ strikes: 0 });
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies[2]).toMatchObject({ name: 'Rocket Mail' });
    expect(call(rpcCompanyQueue, serverCtx, nk, {}).items).toEqual([]);
    // Reset without a strike.
    expect(call(rpcModerateCompanies, serverCtx, nk, { userId: ALICE, verdict: 'reset', strike: false })).toMatchObject({ strikes: 0 });
  });

  it('names: worst cases', () => {
    for (const ok of ['WWWWWWWWWWWWWWWWWW', 'שמש וירח', 'Smith & Co.', "O'Neil Bros", 'Ελλάδα Ναυτιλία', 'Москва Трейд', 'Classic Cars', 'Grape Assets', 'Scunthorpe Steel', 'Essex Analytics']) {
      expect([ok, nameProblem(ok)]).toEqual([ok, null]);
    }
    for (const bad of ['Sh1t Co', 'Sh It Co', 'Admin Team', 'Off1cial Store', 'Big Business Inc', '​Zero Width', 'Tab\tName', 'Emoji 🚀 Co']) {
      expect([bad, nameProblem(bad)]).not.toEqual([bad, null]);
    }
  });

  it('refuses a blocked word spelled out in single letters', () => {
    for (const bad of ['S h i t Co', 'F.U.C.K Co', 'F-U-C-K']) expect([bad, nameProblem(bad)]).not.toEqual([bad, null]);
    for (const ok of ['A B C Foods', 'J & K Bakery', 'U S Air']) expect([ok, nameProblem(ok)]).toEqual([ok, null]);
  });

  it('band names: stop words and the standard band names', () => {
    expect(shortName('The Rocket Shop', 2)).toBe('Rocket');
    expect(shortName('Sunny Side Solar', 0)).toBe('Solar');
    // A custom company named like another slot's standard full name.
    let row = setCompany(emptyRow(), 1, { name: 'Leafline Grocers', color: 'teal', logo: 'leaf', picture: null });
    expect(clashWith(row, 0, { name: 'Pinecone Foods', color: 'slate', logo: 'star', picture: null })).toBe('');
    row = setCompany(row, 0, { name: 'Pinecone Foods', color: 'slate', logo: 'star', picture: null });
    // Slot 0's band reads 'Pinecone' while standard slot 1 would read 'Foods'.
    expect(shortName('Pinecone Foods', 0)).toBe('Pinecone');
  });
});
