import { describe, expect, it } from 'vitest';
import {
  ageAllowsUpload,
  answerAge,
  ART_MAX_BYTES,
  base64Length,
  base64Prefix,
  checkArt,
  deckHashes,
  deckManifest,
  emptyDeck,
  normalizeDeckRow,
  normalizeStanding,
  scanVerdict,
  setPart,
  uploadBlocker,
  webpSize,
} from './designer';
import { normalizeOwned, ownedFromSubscriber, unlockCatalog } from './store';

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

const H1 = 'a'.repeat(64);
const H2 = 'b'.repeat(64);

describe('age gate', () => {
  it('lets 13+ upload, 16+ in the EEA, and never under 13', () => {
    expect(ageAllowsUpload('13to15', 'US')).toBe(true);
    expect(ageAllowsUpload('13to15', 'DE')).toBe(false);
    expect(ageAllowsUpload('16plus', 'DE')).toBe(true);
    expect(ageAllowsUpload('under13', 'US')).toBe(false);
    expect(ageAllowsUpload('', 'US')).toBe(false);
  });

  it('stores the first answer and then only accepts a younger one', () => {
    const fresh = normalizeStanding(null);
    const first = answerAge(fresh, '16plus', 'us');
    expect(first).toEqual({ ageBracket: '16plus', region: 'US', strikes: 0 });
    expect(answerAge(first!, '13to15', 'FR')).toEqual({ ageBracket: '13to15', region: 'US', strikes: 0 });
    expect(answerAge({ ...first!, ageBracket: 'under13' }, '16plus', '')).toBeNull();
    expect(answerAge(fresh, 'adult', 'US')).toBeNull();
  });

  it('names what blocks an upload', () => {
    const ok = { ageBracket: '16plus', region: 'US', strikes: 0 };
    expect(uploadBlocker(false, ok)).toBe('not_owned');
    expect(uploadBlocker(true, { ...ok, ageBracket: '' })).toBe('age_unknown');
    expect(uploadBlocker(true, { ...ok, ageBracket: 'under13' })).toBe('too_young');
    expect(uploadBlocker(true, { ...ok, strikes: 3 })).toBe('banned');
    expect(uploadBlocker(true, ok)).toBe('');
  });
});

describe('art checks', () => {
  it('decodes base64 headers', () => {
    const s = toBase64([82, 73, 70, 70, 120, 121, 122]);
    expect(String.fromCharCode(...base64Prefix(s, 4))).toBe('RIFF');
    expect(base64Length(s)).toBe(7);
  });

  it('reads the size from lossy, lossless and extended WebP headers', () => {
    expect(webpSize(base64Prefix(fakeWebp(250, 350), 32))).toEqual({ width: 250, height: 350 });
    const l: number[] = new Array(40).fill(0);
    put(l, 0, 'RIFF'); put(l, 8, 'WEBPVP8L'); l[20] = 0x2f; putLE(l, 21, (351 - 1) * 16384 + (352 - 1), 4);
    expect(webpSize(l)).toEqual({ width: 352, height: 351 });
    const x: number[] = new Array(40).fill(0);
    put(x, 0, 'RIFF'); put(x, 8, 'WEBPVP8X'); putLE(x, 24, 249, 3); putLE(x, 27, 349, 3);
    expect(webpSize(x)).toEqual({ width: 250, height: 350 });
    const png: number[] = new Array(40).fill(48);
    put(png, 0, '\x89PNG\r\n\x1a\n');
    expect(webpSize(png)).toBeNull();
  });

  it('accepts only WebP at the exact template size within the budget', () => {
    expect(checkArt('back', fakeWebp(250, 350))).toBe('');
    expect(checkArt('c3', fakeWebp(352, 184))).toBe('');
    expect(checkArt('back', fakeWebp(352, 184))).toBe('image must be 250x350');
    expect(checkArt('c9', fakeWebp(352, 184))).toBe('bad part');
    expect(checkArt('back', fakeWebp(250, 350, ART_MAX_BYTES + 4))).toBe('image too large');
    const gif: number[] = new Array(60).fill(120);
    put(gif, 0, 'GIF89a');
    expect(checkArt('back', toBase64(gif))).toBe('image must be WebP');
    expect(checkArt('back', 'not base64 at all!!')).toBe('bad image');
    expect(checkArt('back', 42)).toBe('bad image');
    // A header that claims more bytes than were sent.
    const short = toBase64(webpBytes(250, 350).slice(0, 300));
    expect(checkArt('back', short)).toBe('bad image');
  });
});

describe('decks', () => {
  it('normalises stored rows to the slot count', () => {
    const row = normalizeDeckRow({ decks: [{ back: H1, art: [H2, 'junk', null] }, 'x'], active: 7 }, 3);
    expect(row.decks).toHaveLength(3);
    expect(row.decks[0]).toEqual({ back: H1, art: [H2, null, null, null, null, null] });
    expect(row.decks[1]).toEqual(emptyDeck());
    expect(row.active).toBe(-1);
  });

  it('sets and clears parts without touching the old row', () => {
    const row = normalizeDeckRow(null, 3);
    const next = setPart(setPart(row, 1, 'back', H1), 1, 'c5', H2);
    expect(next.decks[1]).toEqual({ back: H1, art: [null, null, null, null, null, H2] });
    expect(row.decks[1]).toEqual(emptyDeck());
    expect(setPart(next, 1, 'back', null).decks[1]!.back).toBeNull();
    expect(deckHashes(next.decks[1]!)).toEqual([H1, H2]);
  });

  it('shows approved art only, and nothing when none is approved', () => {
    const deck = { back: H1, art: [H2, null, null, null, null, H1] };
    expect(deckManifest(deck, (h) => h === H1)).toEqual({ back: H1, art: [null, null, null, null, null, H1] });
    expect(deckManifest(deck, () => false)).toBeNull();
  });
});

describe('scan verdict', () => {
  const ann = (a: string, v: string, r: string) => ({ responses: [{ safeSearchAnnotation: { adult: a, violence: v, racy: r, spoof: 'LIKELY', medical: 'POSSIBLE' } }] });
  it('approves clean pictures, refuses clear ones, queues the rest', () => {
    expect(scanVerdict(ann('VERY_UNLIKELY', 'UNLIKELY', 'POSSIBLE'))).toBe('approved');
    expect(scanVerdict(ann('LIKELY', 'VERY_UNLIKELY', 'VERY_UNLIKELY'))).toBe('rejected');
    expect(scanVerdict(ann('VERY_UNLIKELY', 'VERY_LIKELY', 'VERY_UNLIKELY'))).toBe('rejected');
    expect(scanVerdict(ann('POSSIBLE', 'VERY_UNLIKELY', 'VERY_UNLIKELY'))).toBe('pending');
    expect(scanVerdict(ann('VERY_UNLIKELY', 'VERY_UNLIKELY', 'LIKELY'))).toBe('pending');
    expect(scanVerdict(ann('UNKNOWN', 'VERY_UNLIKELY', 'VERY_UNLIKELY'))).toBe('pending');
    expect(scanVerdict({ responses: [{ error: { code: 3 } }] })).toBe('pending');
    expect(scanVerdict('junk')).toBe('pending');
  });
});

describe('Designer entitlement', () => {
  it('is read from RevenueCat like the skins and kept in the owned row', () => {
    const body = { subscriber: { entitlements: { designer: { expires_date: null }, skin_table_walnut: { expires_date: null } } } };
    expect(ownedFromSubscriber(body, Date.now())).toEqual(['table_walnut', 'designer']);
    expect(normalizeOwned({ owned: ['designer', 'designer', 'gold'] }).owned).toEqual(['designer']);
    expect(unlockCatalog(['designer'])[0]).toEqual({ id: 'designer', name: 'Designer', productId: 'bb_designer', owned: true });
  });
});
