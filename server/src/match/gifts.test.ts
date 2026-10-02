import { describe, expect, it } from 'vitest';
import { addGift, claimGifts, GIFT_POINTS, GIFTS_CLAIM_PER_DAY, GIFTS_SEND_PER_DAY, INBOX_MAX, normalizeInbox, normalizeSent, sendBlocker } from './gifts';
import { rpcClaimGifts, rpcGiftState, rpcSendGift } from './rpc_gifts';
import { ALICE, BOB, call, fakeNk, userCtx } from './test_support';

const DAY = 86_400_000;
const NOON = Date.UTC(2026, 9, 2, 12);
const CAROL = '2f8fad5b-d9cb-469f-a165-70867728950e';

describe('gift rules', () => {
  it('one gift per friend per day, ten a day', () => {
    const sent = normalizeSent({ day: '2026-10-02', to: [BOB] }, NOON);
    expect(sendBlocker(sent, BOB)).toBe('already sent today');
    expect(sendBlocker(sent, CAROL)).toBe('');
    expect(sendBlocker(normalizeSent({ day: '2026-10-01', to: [BOB] }, NOON), BOB)).toBe('');
    const full = { day: '2026-10-02', to: new Array(GIFTS_SEND_PER_DAY).fill('x') };
    expect(sendBlocker(full, CAROL)).toBe('no gifts left today');
  });

  it('one waiting gift per sender; old ones expire; the inbox is capped', () => {
    let inbox = normalizeInbox(null);
    inbox = addGift(inbox, { from: BOB, name: 'bob', at: NOON - 8 * DAY }, NOON - 8 * DAY);
    inbox = addGift(inbox, { from: CAROL, name: 'carol', at: NOON }, NOON);
    expect(inbox.pending.map((g) => g.from)).toEqual([CAROL]);
    inbox = addGift(inbox, { from: CAROL, name: 'carol', at: NOON + 1 }, NOON + 1);
    expect(inbox.pending.length).toBe(1);
    for (let i = 0; i < INBOX_MAX + 5; i++) inbox = addGift(inbox, { from: 'u' + i, name: '', at: NOON }, NOON);
    expect(inbox.pending.length).toBe(INBOX_MAX);
  });

  it('collects at most five a day, the rest wait for tomorrow', () => {
    let inbox = normalizeInbox(null);
    for (let i = 0; i < 7; i++) inbox = addGift(inbox, { from: 'u' + i, name: '', at: NOON }, NOON);
    const first = claimGifts(inbox, NOON);
    expect([first.count, first.points, first.inbox.pending.length]).toEqual([GIFTS_CLAIM_PER_DAY, GIFTS_CLAIM_PER_DAY * GIFT_POINTS, 2]);
    expect(claimGifts(first.inbox, NOON + 1000).count).toBe(0);
    expect(claimGifts(first.inbox, NOON + DAY).count).toBe(2);
  });
});

/** fakeNk plus a friend graph: `friends` pairs are mutual, `blocks` maps blocker to blocked. */
function giftNk(friends: Array<[string, string]>, blocks: Array<[string, string]> = []) {
  const { nk, rows } = fakeNk();
  Object.assign(nk, {
    usersGetId: (ids: string[]) => ids.map((id) => ({ userId: id, username: 'u' + id.slice(0, 2) })),
    friendsList: (userId: string, _limit: number, state: number) => {
      const out: Array<{ user: { userId: string }; state: number }> = [];
      if (state === 0) for (const [a, b] of friends) { if (a === userId) out.push({ user: { userId: b }, state: 0 }); if (b === userId) out.push({ user: { userId: a }, state: 0 }); }
      if (state === 3) for (const [a, b] of blocks) if (a === userId) out.push({ user: { userId: b }, state: 3 });
      return { friends: out, cursor: '' };
    },
  });
  return { nk, rows };
}

describe('gift RPCs', () => {
  it('a mutual friend sends, the other collects track points', () => {
    const { nk } = giftNk([[ALICE, BOB]]);
    call(rpcSendGift, userCtx(ALICE), nk, { userId: BOB });
    expect(() => call(rpcSendGift, userCtx(ALICE), nk, { userId: BOB })).toThrow('already sent today');
    expect(() => call(rpcSendGift, userCtx(ALICE), nk, { userId: CAROL })).toThrow('not friends');
    const state = call(rpcGiftState, userCtx(BOB), nk, {});
    expect([state.waiting, state.names, state.claimLeft]).toEqual([1, ['u0f'], GIFTS_CLAIM_PER_DAY]);
    expect(call(rpcGiftState, userCtx(ALICE), nk, {}).sentToday).toEqual([BOB]);
    const claim = call(rpcClaimGifts, userCtx(BOB), nk, {});
    expect([claim.claimed, claim.trackPoints, claim.waiting]).toEqual([1, GIFT_POINTS, 0]);
    expect(call(rpcClaimGifts, userCtx(BOB), nk, {}).claimed).toBe(0);
  });

  it('nobody sends to a friend who blocked them', () => {
    const { nk } = giftNk([[ALICE, BOB]], [[BOB, ALICE]]);
    expect(() => call(rpcSendGift, userCtx(ALICE), nk, { userId: BOB })).toThrow('not friends');
  });

  it('a client-made inbox row is ignored', () => {
    const { nk } = giftNk([[ALICE, BOB]]);
    nk.storageWrite([{ collection: 'gifts', key: 'inbox', userId: BOB, value: { pending: [{ from: CAROL, name: 'x', at: Date.now() }] }, permissionRead: 1, permissionWrite: 1 }]);
    expect(call(rpcGiftState, userCtx(BOB), nk, {}).waiting).toBe(0);
    call(rpcSendGift, userCtx(ALICE), nk, { userId: BOB });
    expect(call(rpcClaimGifts, userCtx(BOB), nk, {}).claimed).toBe(1);
  });
});
