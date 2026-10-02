import { describe, expect, it } from 'vitest';
import { PURCHASE_COLLECTION, PURCHASE_KEY } from './store';
import { rpcClearDeckPart, rpcDesignerState, rpcGetCardArt, rpcReportCardArt, rpcSelectDeck, rpcSetAgeBracket, rpcUploadCardArt } from './rpc_designer';
import { rpcModerateCardArt, rpcModerationQueue } from './rpc_moderation';
import { hostDeck } from './room_deck';
import { touchesServerCollection } from './reports';

/** Standard base64 of raw bytes (no Node Buffer: tests are typed for goja's ES2016 library). */
function toBase64(bytes: number[]): string {
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const n = ((bytes[i] || 0) << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
    out += A.charAt((n >> 18) & 63) + A.charAt((n >> 12) & 63);
    out += i + 1 < bytes.length ? A.charAt((n >> 6) & 63) : '=';
    out += i + 2 < bytes.length ? A.charAt(n & 63) : '=';
  }
  return out;
}

function put(b: number[], at: number, text: string): void {
  for (let i = 0; i < text.length; i++) b[at + i] = text.charCodeAt(i);
}

function putLE(b: number[], at: number, value: number, len: number): void {
  for (let i = 0; i < len; i++) b[at + i] = Math.floor(value / Math.pow(256, i)) & 255;
}

/** Bytes of a minimal lossy WebP: RIFF header, a VP8 chunk header with the size, then padding. */
function webpBytes(width: number, height: number, totalBytes = 600): number[] {
  const b: number[] = new Array(totalBytes).fill(0);
  put(b, 0, 'RIFF');
  putLE(b, 4, totalBytes - 8, 4);
  put(b, 8, 'WEBPVP8 ');
  putLE(b, 16, totalBytes - 20, 4);
  b[23] = 0x9d; b[24] = 0x01; b[25] = 0x2a;
  putLE(b, 26, width, 2);
  putLE(b, 28, height, 2);
  return b;
}

function fakeWebp(width: number, height: number, totalBytes = 600): string {
  return toBase64(webpBytes(width, height, totalBytes));
}

const ALICE = '0f8fad5b-d9cb-469f-a165-70867728950e';
const BOB = '1f8fad5b-d9cb-469f-a165-70867728950e';

/** In-memory Nakama storage with versions, enough for the Designer RPCs. */
function fakeNk(visionAnswer: unknown = null) {
  const rows = new Map<string, nkruntime.StorageObject>();
  let serial = 0;
  const id = (c: string, k: string, u: string) => `${c}/${k}/${u}`;
  const nk = {
    storageRead: (reqs: nkruntime.StorageReadRequest[]) => reqs.map((r) => rows.get(id(r.collection, r.key, r.userId || ''))).filter((o): o is nkruntime.StorageObject => !!o),
    storageWrite: (reqs: nkruntime.StorageWriteRequest[]) => {
      for (const r of reqs) {
        const prev = rows.get(id(r.collection, r.key, r.userId || ''));
        if (r.version === '*' && prev) throw new Error('version conflict');
        if (r.version && r.version !== '*' && (!prev || prev.version !== r.version)) throw new Error('version conflict');
        rows.set(id(r.collection, r.key, r.userId || ''), {
          collection: r.collection, key: r.key, userId: r.userId || '', value: JSON.parse(JSON.stringify(r.value)), version: String(++serial),
          permissionRead: r.permissionRead ?? 1, permissionWrite: r.permissionWrite ?? 1, createTime: 0, updateTime: 0,
        });
      }
      return [];
    },
    storageDelete: (reqs: nkruntime.StorageDeleteRequest[]) => { for (const r of reqs) rows.delete(id(r.collection, r.key, r.userId || '')); },
    storageList: (userId: string, collection: string) => ({ objects: [...rows.values()].filter((o) => o.userId === userId && o.collection === collection), cursor: '' }),
    // Not SHA-256, but a stable 64-hex-digit name per input, which is all the RPCs need.
    sha256Hash: (s: string) => {
      let h = '';
      for (let round = 0; round < 8; round++) {
        let x = 2166136261 ^ round;
        for (let i = 0; i < s.length; i++) x = Math.imul(x ^ s.charCodeAt(i), 16777619) >>> 0;
        h += ('0000000' + x.toString(16)).slice(-8);
      }
      return h;
    },
    httpRequest: () => ({ code: 200, body: JSON.stringify(visionAnswer), headers: {} }),
  };
  return { nk: nk as unknown as nkruntime.Nakama, rows };
}

const logger = { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} } as unknown as nkruntime.Logger;
const userCtx = (userId: string, env: { [k: string]: string } = {}) => ({ userId, env } as unknown as nkruntime.Context);
const serverCtx = { userId: '', env: {} } as unknown as nkruntime.Context;

function call(fn: nkruntime.RpcFunction, ctx: nkruntime.Context, nk: nkruntime.Nakama, body: unknown): any {
  return JSON.parse(fn(ctx, logger, nk, JSON.stringify(body)) as string);
}

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
    expect(() => call(rpcUploadCardArt, userCtx(ALICE), nk, { slot: 0, part: 'c0', image: back })).toThrow('image must be 352x184');
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
    const window = fakeWebp(352, 184);
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
