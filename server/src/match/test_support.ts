/**
 * Test support shared by the RPC tests: an in-memory Nakama storage with
 * versions, contexts, and minimal WebP headers. Not imported by the runtime.
 */
/** Standard base64 of raw bytes (no Node Buffer: tests are typed for goja's ES2016 library). */
export function toBase64(bytes: number[]): string {
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
export function webpBytes(width: number, height: number, totalBytes = 600): number[] {
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

export function fakeWebp(width: number, height: number, totalBytes = 600): string {
  return toBase64(webpBytes(width, height, totalBytes));
}

export const ALICE = '0f8fad5b-d9cb-469f-a165-70867728950e';
export const BOB = '1f8fad5b-d9cb-469f-a165-70867728950e';

/** In-memory Nakama storage with versions, enough for the Designer RPCs. */
export function fakeNk(visionAnswer: unknown = null) {
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

export const logger = { info: () => {}, warn: () => {}, error: () => {}, debug: () => {} } as unknown as nkruntime.Logger;
export const userCtx = (userId: string, env: { [k: string]: string } = {}) => ({ userId, env } as unknown as nkruntime.Context);
export const serverCtx = { userId: '', env: {} } as unknown as nkruntime.Context;

export function call(fn: nkruntime.RpcFunction, ctx: nkruntime.Context, nk: nkruntime.Nakama, body: unknown): any {
  return JSON.parse(fn(ctx, logger, nk, JSON.stringify(body)) as string);
}

