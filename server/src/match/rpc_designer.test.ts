import { describe, expect, it } from 'vitest';
import { PURCHASE_COLLECTION, PURCHASE_KEY } from './store';
import { rpcClearDeckPart, rpcDesignerState, rpcGetCardArt, rpcReportCardArt, rpcSelectDeck, rpcSetAgeBracket, rpcUploadCardArt } from './rpc_designer';
import { rpcModerateCardArt, rpcModerationQueue } from './rpc_moderation';
import { hostDeck } from './room_deck';
import { touchesServerCollection } from './reports';
import { ALICE, BOB, call, fakeNk, fakeWebp, serverCtx, userCtx } from './test_support';

function grantDesigner(nk: nkruntime.Nakama, userId: string) {
  nk.storageWrite([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId, value: { owned: ['designer'], syncedAt: 1 }, permissionRead: 1, permissionWrite: 0 }]);
}

describe('Designer RPCs', () => {
  it('refuses uploads until unlocked and old enough', () => {
    const { nk } = fakeNk();
    const back = fakeWebp(250, 350);
    expect(call(rpcDesignerState, userCtx(ALICE), nk, {})).toMatchObject({ owned: false, slots: 0, blocker: 'not_owned', enabled: true });
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'back', image: back })).toThrow('Designer is not unlocked');
    grantDesigner(nk, ALICE);
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'back', image: back })).toThrow('age not set');
    expect(call(rpcSetAgeBracket, userCtx(ALICE), nk, { bracket: '13to15', region: 'DE' })).toEqual({ ageBracket: '13to15', blocker: 'too_young' });
    expect(() => call(rpcSetAgeBracket, userCtx(ALICE), nk, { bracket: '16plus', region: 'DE' })).toThrow('invalid age');
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'back', image: back })).toThrow('not available at your age');
  });

  it('queues unscanned art, shows it only to its owner until approved, then in the host deck', () => {
    const { nk } = fakeNk();
    grantDesigner(nk, ALICE);
    call(rpcSetAgeBracket, userCtx(ALICE), nk, { bracket: '16plus', region: 'US' });
    const back = fakeWebp(250, 350);
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 3, part: 'back', image: back })).toThrow('invalid slot');
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'c0', image: back })).toThrow('image must be 324x228');
    const up = call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'back', image: back });
    expect(up.status).toBe('pending');
    const hash = up.hash;
    expect(call(rpcGetCardArt, userCtx(ALICE), nk, { hashes: [hash] }).art[hash]).toBe(back);
    expect(call(rpcGetCardArt, userCtx(BOB), nk, { hashes: [hash] }).art).toEqual({});
    call(rpcSelectDeck, userCtx(ALICE), nk, { slot: 0 });
    expect(hostDeck(nk, ALICE)).toBeNull();

    expect(() => call(rpcModerationQueue, userCtx(ALICE), nk, {})).toThrow('forbidden');
    const queue = call(rpcModerationQueue, serverCtx, nk, {});
    expect(queue.items).toHaveLength(1);
    expect(queue.items[0]).toMatchObject({ hash, reason: 'unscanned', owner: ALICE, part: 'back', status: 'pending', data: back });
    expect(call(rpcModerateCardArt, serverCtx, nk, { hash, verdict: 'approve' })).toMatchObject({ status: 'approved', strikes: 0 });
    expect(call(rpcModerationQueue, serverCtx, nk, {}).items).toHaveLength(0);
    expect(call(rpcGetCardArt, userCtx(BOB), nk, { hashes: [hash] }).art[hash]).toBe(back);
    expect(hostDeck(nk, ALICE)).toEqual({ owner: ALICE, back: hash, art: [null, null, null, null, null, null] });

    const state = call(rpcDesignerState, userCtx(ALICE), nk, {});
    expect(state).toMatchObject({ owned: true, slots: 3, active: 0, blocker: '' });
    expect(state.decks[0]).toMatchObject({ back: hash, backStatus: 'approved' });

    call(rpcClearDeckPart, userCtx(ALICE), nk, { slot: 0, part: 'back' });
    expect(hostDeck(nk, ALICE)).toBeNull();
  });

  it('hides reported art after three reports and strikes the uploader on refusal', () => {
    const { nk } = fakeNk();
    grantDesigner(nk, ALICE);
    call(rpcSetAgeBracket, userCtx(ALICE), nk, { bracket: '16plus', region: 'US' });
    const window = fakeWebp(324, 228);
    const { hash } = call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 1, part: 'c2', image: window });
    call(rpcModerateCardArt, serverCtx, nk, { hash, verdict: 'approve' });
    call(rpcSelectDeck, userCtx(ALICE), nk, { slot: 1 });
    expect(hostDeck(nk, ALICE)?.art[2]).toBe(hash);
    for (let i = 0; i < 3; i++) call(rpcReportCardArt, userCtx(BOB), nk, { hash, matchId: 'm' });
    expect(hostDeck(nk, ALICE)).toBeNull();
    expect(call(rpcModerationQueue, serverCtx, nk, {}).items[0]).toMatchObject({ reason: 'report', reports: 3 });
    expect(call(rpcModerateCardArt, serverCtx, nk, { hash, verdict: 'reject', note: 'logo' })).toMatchObject({ status: 'rejected', strikes: 1, banned: false });
    expect(call(rpcGetCardArt, userCtx(ALICE), nk, { hashes: [hash] }).art).toEqual({});
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'c2', image: window })).toThrow('cannot be used');
    expect(call(rpcDesignerState, userCtx(ALICE), nk, {}).decks[1].artStatus[2]).toBe('rejected');
  });

  it('uses the Vision verdict when a key is set', () => {
    const clean = { responses: [{ safeSearchAnnotation: { adult: 'VERY_UNLIKELY', violence: 'VERY_UNLIKELY', racy: 'UNLIKELY' } }] };
    const env = { GOOGLE_VISION_API_KEY: 'k' };
    const ok = fakeNk(clean);
    grantDesigner(ok.nk, ALICE);
    call(rpcSetAgeBracket, userCtx(ALICE), ok.nk, { bracket: '16plus', region: 'US' });
    expect(call(rpcUploadCardArt, userCtx(ALICE, env), ok.nk, { slot: 0, part: 'back', image: fakeWebp(250, 350) }).status).toBe('approved');
    expect(call(rpcModerationQueue, serverCtx, ok.nk, {}).items).toHaveLength(0);

    const bad = fakeNk({ responses: [{ safeSearchAnnotation: { adult: 'VERY_LIKELY', violence: 'VERY_UNLIKELY', racy: 'VERY_LIKELY' } }] });
    grantDesigner(bad.nk, ALICE);
    call(rpcSetAgeBracket, userCtx(ALICE), bad.nk, { bracket: '16plus', region: 'US' });
    expect(() => call(rpcUploadCardArt, userCtx(ALICE, env), bad.nk, { slot: 0, part: 'back', image: fakeWebp(250, 350) })).toThrow('cannot be used');
  });

  it('keeps every Designer collection server-only', () => {
    for (const collection of ['designer', 'standing', 'card_art', 'art_queue']) expect(touchesServerCollection([{ collection }])).toBe(true);
  });
});
