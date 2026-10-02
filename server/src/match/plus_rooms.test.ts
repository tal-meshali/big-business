import { describe, expect, it } from 'vitest';
import { emptyProgress, PROFILE_COLLECTION, PROFILE_KEY } from './progression';
import { rpcDesignerState, rpcSelectDeck, rpcSetAgeBracket, rpcSetPublicDeck, rpcUploadCardArt } from './rpc_designer';
import { rpcModerateCardArt } from './rpc_moderation';
import { rpcSetRemoteConfig } from './rpc_config';
import { rpcStoreCatalog } from './rpc_store';
import { chooseRoomDeck, sendDeck } from './room_deck';
import type { MatchState } from './state';
import { PURCHASE_COLLECTION, PURCHASE_KEY } from './store';
import { ALICE, BOB, call, fakeNk, fakeWebp, logger, serverCtx, userCtx } from './test_support';

const CAROL = '2f8fad5b-d9cb-469f-a165-70867728950e';

function grant(nk: nkruntime.Nakama, userId: string, owned: string[], expires: { [id: string]: number } = {}) {
  nk.storageWrite([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId, value: { owned, syncedAt: 1, expires }, permissionRead: 1, permissionWrite: 0 }]);
}

const FUTURE = Date.now() + 30 * 86_400_000;

describe('Plus in rooms', () => {
  function state(isPrivate: boolean, seats: string[], hostId?: string): MatchState {
    const presences: { [id: string]: nkruntime.Presence } = {};
    for (const id of seats) presences[id] = { userId: id, sessionId: 's' + id, username: id, node: 'n' } as nkruntime.Presence;
    const seatByUser: { [id: string]: number } = {};
    seats.forEach((id, i) => (seatByUser[id] = i));
    return {
      params: { isPrivate, minSeats: 3, maxSeats: 5, stepSeconds: 30, lobbyWaitSeconds: 20, tutorial: false, seed: 0, hostId },
      presences, seatByUser, game: { seats: seats.map((id) => ({ id })) }, customDeck: null,
    } as unknown as MatchState;
  }
  function dispatcher() {
    const sent: Array<{ data: unknown; to: string[] }> = [];
    return { sent, d: { broadcastMessage: (_op: number, data: string, to: nkruntime.Presence[]) => sent.push({ data: JSON.parse(data), to: (to || []).map((p) => p.userId) }) } as unknown as nkruntime.MatchDispatcher };
  }
  function approvedDeck(nk: nkruntime.Nakama, userId: string, owned: string[]): string {
    grant(nk, userId, owned, owned.indexOf('plus') >= 0 ? { plus: FUTURE } : {});
    call(rpcSetAgeBracket, userCtx(userId), nk, { bracket: '16plus', region: 'US' });
    const { hash } = call(rpcUploadCardArt, userCtx(userId), nk, { slot: 0, part: 'back', image: fakeWebp(250, 350, 600 + userId.charCodeAt(0)) });
    call(rpcModerateCardArt, serverCtx, nk, { hash, verdict: 'approve' });
    call(rpcSelectDeck, userCtx(userId), nk, { slot: 0 });
    return hash;
  }

  it('lets Plus members use ten slots and opt into quick play', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['plus'], { plus: FUTURE });
    expect(call(rpcDesignerState, userCtx(ALICE), nk, {})).toMatchObject({ owned: true, plus: true, slots: 10, publicDeck: false });
    grant(nk, BOB, ['designer']);
    expect(() => call(rpcSetPublicDeck, userCtx(BOB), nk, { on: true })).toThrow('Plus is needed');
    expect(call(rpcSetPublicDeck, userCtx(ALICE), nk, { on: true })).toEqual({ publicDeck: true });
    expect(call(rpcDesignerState, userCtx(ALICE), nk, {}).publicDeck).toBe(true);
  });

  it('shows a Plus host\'s skins to every seat of a private room', () => {
    const { nk } = fakeNk();
    grant(nk, ALICE, ['plus', 'table_walnut'], { plus: FUTURE });
    nk.storageWrite([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: ALICE, value: { ...emptyProgress(), equipped: { cardBack: 'back_ticker', table: 'table_walnut' } }, permissionRead: 1, permissionWrite: 0 }]);
    const s = state(true, [ALICE, BOB], ALICE);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toMatchObject({ owner: ALICE, back: null, cardBack: 'back_ticker', table: 'table_walnut' });
    const { sent, d } = dispatcher();
    sendDeck(s, nk, d);
    expect(sent[0]!.to.sort()).toEqual([ALICE, BOB].sort());
    // Without Plus the host's skins stay the host's own.
    grant(nk, ALICE, ['table_walnut']);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
  });

  it('puts an opted-in Plus deck on quick play, only for players 13 or older', () => {
    const { nk } = fakeNk();
    const hash = approvedDeck(nk, BOB, ['plus']);
    approvedDeck(nk, ALICE, ['designer']);
    const s = state(false, ['bot:0', ALICE, BOB, CAROL]);
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toBeNull();
    call(rpcSetPublicDeck, userCtx(BOB), nk, { on: true });
    chooseRoomDeck(s, nk, logger);
    expect(s.customDeck).toMatchObject({ owner: BOB, back: hash, public: true });
    call(rpcSetAgeBracket, userCtx(CAROL), nk, { bracket: 'under13', region: 'US' });
    const { sent, d } = dispatcher();
    sendDeck(s, nk, d);
    expect(sent[0]!.to.sort()).toEqual([ALICE, BOB].sort());
  });

  it('lists Plus in the shop only while it is offered', () => {
    const { nk } = fakeNk();
    const ids = () => call(rpcStoreCatalog, userCtx(ALICE), nk, {}).unlocks.map((u: { id: string }) => u.id);
    expect(ids()).toEqual(['designer']);
    call(rpcSetRemoteConfig, serverCtx, nk, { plusEnabled: true });
    expect(ids()).toEqual(['designer', 'plus']);
  });
});
