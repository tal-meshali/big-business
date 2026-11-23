import { describe, expect, it } from 'vitest';
import { rpcModerateCardArt } from './rpc_moderation';
import { rpcSetAgeBracket } from './rpc_designer';
import { rpcFounderState, rpcReportCompanies, rpcSaveCompany, rpcSetCompaniesActive, rpcUploadCompanyLogo } from './rpc_founder';
import { rpcCompanyQueue, rpcModerateCompanies } from './rpc_founder_moderation';
import { rpcSetRemoteConfig } from './rpc_config';
import { rpcStoreCatalog } from './rpc_store';
import { chooseRoomDeck } from './room_deck';
import { COMPANIES_COLLECTION, COMPANIES_KEY } from './founder_store';
import { touchesServerCollection } from './reports';
import type { MatchState } from './state';
import { PURCHASE_COLLECTION, PURCHASE_KEY } from './store';
import { ALICE, BOB, call, fakeNk, fakeWebp, logger, serverCtx, userCtx } from './test_support';

function grant(nk: nkruntime.Nakama, userId: string, owned: string[], expires: { [id: string]: number } = {}) {
  nk.storageWrite([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId, value: { owned, syncedAt: 1, expires }, permissionRead: 1, permissionWrite: 0 }]);
}

function room(hostId: string, isPrivate = true): MatchState {
  const seats = [ALICE, BOB];
  const presences: { [id: string]: nkruntime.Presence } = {};
  for (const id of seats) presences[id] = { userId: id, sessionId: 's' + id, username: id, node: 'n' } as nkruntime.Presence;
  const seatByUser: { [id: string]: number } = {};
  seats.forEach((id, i) => (seatByUser[id] = i));
  return {
    params: { isPrivate, minSeats: 3, maxSeats: 5, stepSeconds: 30, lobbyWaitSeconds: 20, tutorial: false, solo: false, seed: 0, hostId },
    presences, seatByUser, game: { seats: seats.map((id) => ({ id })) }, customDeck: null,
  } as unknown as MatchState;
}

const ROCKET = { company: 2, name: 'Rocket Mail', color: 'teal', logo: 'rocket' };

describe('Founder RPCs', () => {
  it('is sold in the shop and needs the unlock (or Plus)', () => {
    const { nk } = fakeNk();
    const cat = call(rpcStoreCatalog, userCtx(ALICE), nk, {});
    expect(cat.unlocks.map((u: { id: string }) => u.id)).toContain('founder');
    expect(call(rpcFounderState, userCtx(ALICE), nk, {})).toMatchObject({ owned: false, productId: 'bb_founder', active: false });
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET)).toThrow('Founder is not unlocked');
    grant(nk, BOB, ['plus'], { plus: Date.now() + 86_400_000 });
    expect(call(rpcSaveCompany, userCtx(BOB), nk, ROCKET).company).toMatchObject({ name: 'Rocket Mail' });
  });

  it('saves, checks and resets companies', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    expect(call(rpcSaveCompany, userCtx(ALICE), nk, { ...ROCKET, name: '  Rocket Mail ' }).company).toEqual({ name: 'Rocket Mail', color: 'teal', logo: 'rocket', picture: null });
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, { company: 3, name: 'Gear Up', color: 'teal', logo: 'gear' })).toThrow('colour');
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, { company: 3, name: 'Gear Up', color: 'violet', logo: 'gear' })).toThrow('invalid company');
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, { company: 6, name: 'Gear Up', color: 'pink', logo: 'gear' })).toThrow('invalid company');
    expect(() => call(rpcSaveCompany, userCtx(ALICE), nk, { company: 3, name: 'Shit Co', color: 'pink', logo: 'gear' })).toThrow('Pick a different');
    const st = call(rpcFounderState, userCtx(ALICE), nk, {});
    expect(st.companies[2]).toMatchObject({ name: 'Rocket Mail', pictureStatus: null });
    expect(st.colors).toContain('teal');
    call(rpcSaveCompany, userCtx(ALICE), nk, { company: 2, reset: true });
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies[2]).toBeNull();
  });

  it('keeps the row out of clients\' hands', () => {
    expect(touchesServerCollection([{ collection: COMPANIES_COLLECTION }])).toBe(true);
  });

  it('shows the host\'s companies in private rooms only, while switched on', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    const s = room(ALICE);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
    call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true });
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toMatchObject({ owner: ALICE, back: null });
    expect(s.customDeck!.companies![2]).toEqual({ name: 'Rocket Mail', color: 'teal', logo: 'rocket', picture: null });
    expect(s.customDeck!.companies![0]).toBeNull();
    // Not in quick play, not for a guest's companies, not once switched off by the operator.
    const pub = room(ALICE, false);
    chooseRoomDeck(pub, nk, logger);
    expect(pub.customDeck).toBeNull();
    const guest = room(BOB);
    chooseRoomDeck(guest, nk, logger);
    expect(guest.customDeck).toBeNull();
    call(rpcSetRemoteConfig, serverCtx, nk, { companiesEnabled: false });
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
    call(rpcSetRemoteConfig, serverCtx, nk, { companiesEnabled: true });
    // A refund hides them.
    grant(nk, ALICE, []);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
  });

  it('uploads a logo picture that shows once approved, for 13 and older', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true });
    const image = fakeWebp(192, 192, 777);
    expect(() => call(rpcUploadCompanyLogo, userCtx(ALICE), nk, { company: 2, image })).toThrow('age not set');
    call(rpcSetAgeBracket, userCtx(ALICE), nk, { bracket: '13to15', region: 'US' });
    expect(() => call(rpcUploadCompanyLogo, userCtx(ALICE), nk, { company: 1, image })).toThrow('save the company first');
    expect(() => call(rpcUploadCompanyLogo, userCtx(ALICE), nk, { company: 2, image: fakeWebp(250, 350, 601) })).toThrow('192x192');
    const { hash, status } = call(rpcUploadCompanyLogo, userCtx(ALICE), nk, { company: 2, image });
    expect(status).toBe('pending');
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies[2]).toMatchObject({ picture: hash, pictureStatus: 'pending' });
    const s = room(ALICE);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck!.companies![2]!.picture).toBeNull();
    call(rpcModerateCardArt, serverCtx, nk, { hash, verdict: 'approve' });
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck!.companies![2]!.picture).toBe(hash);
    // Editing the company keeps the picture unless asked to drop it.
    call(rpcSaveCompany, userCtx(ALICE), nk, { ...ROCKET, name: 'Rocket Post' });
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies[2].picture).toBe(hash);
    call(rpcSaveCompany, userCtx(ALICE), nk, { ...ROCKET, picture: null });
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies[2].picture).toBeNull();
    // Under 13: drawn logos only.
    grant(nk, BOB, ['founder']);
    call(rpcSaveCompany, userCtx(BOB), nk, ROCKET);
    call(rpcSetAgeBracket, userCtx(BOB), nk, { bracket: 'under13', region: 'US' });
    expect(() => call(rpcUploadCompanyLogo, userCtx(BOB), nk, { company: 2, image })).toThrow('not available at your age');
  });

  it('queues reported names and lets the operator reset them with a strike', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    call(rpcSetCompaniesActive, userCtx(ALICE), nk, { on: true });
    expect(() => call(rpcReportCompanies, userCtx(ALICE), nk, { userId: ALICE })).toThrow('invalid user');
    call(rpcReportCompanies, userCtx(BOB), nk, { userId: ALICE, matchId: 'm' });
    const q = call(rpcCompanyQueue, serverCtx, nk, {});
    expect(q.items[0]).toMatchObject({ userId: ALICE, names: ['Rocket Mail'], reports: 1 });
    expect(() => call(rpcCompanyQueue, userCtx(BOB), nk, {})).toThrow();
    expect(call(rpcModerateCompanies, serverCtx, nk, { userId: ALICE, verdict: 'reset' })).toMatchObject({ strikes: 1, banned: false });
    expect(call(rpcFounderState, userCtx(ALICE), nk, {}).companies.every((c: unknown) => c === null)).toBe(true);
    expect(call(rpcCompanyQueue, serverCtx, nk, {}).items).toEqual([]);
    const s = room(ALICE);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
  });

  it('stores the row server-only', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['founder']);
    call(rpcSaveCompany, userCtx(ALICE), nk, ROCKET);
    const r = nk.storageRead([{ collection: COMPANIES_COLLECTION, key: COMPANIES_KEY, userId: ALICE }])[0]!;
    expect(r.permissionWrite).toBe(0);
  });
});
