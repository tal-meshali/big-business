import { describe, expect, it } from 'vitest';
import { guardRpc, isClientError, isUserId, normalizeCode, parseAction, parseBody, readInt, readString, reject } from './input';

describe('parseBody', () => {
  it('accepts empty and object payloads', () => {
    expect(parseBody(undefined)).toEqual({});
    expect(parseBody('')).toEqual({});
    expect(parseBody('{"a":1}')).toEqual({ a: 1 });
  });

  it('rejects malformed JSON, arrays, primitives and huge payloads with a short client error', () => {
    for (const bad of ['{', 'null', '5', '"x"', '[]', '[1,2]', 'true', '{'.repeat(5000)]) {
      let err: unknown = null;
      try {
        parseBody(bad);
      } catch (e) {
        err = e;
      }
      expect(err, bad).not.toBeNull();
      expect(isClientError(err)).toBe(true);
      expect((err as Error).message).toBe('bad payload');
    }
  });
});

describe('readString / readInt', () => {
  it('reads only strings, trimmed and bounded', () => {
    expect(readString({ name: '  bob ' }, 'name', 10)).toBe('bob');
    expect(readString({ name: 'x'.repeat(20) }, 'name', 5)).toBe('xxxxx');
    expect(readString({ name: 5 }, 'name', 10)).toBe('');
    expect(readString({ name: { a: 1 } }, 'name', 10)).toBe('');
    expect(readString({}, 'name', 10)).toBe('');
  });

  it('clamps numbers and falls back on junk', () => {
    expect(readInt({ n: 30 }, 'n', 5, 120, 30)).toBe(30);
    expect(readInt({ n: 3.7 }, 'n', 5, 120, 30)).toBe(5);
    expect(readInt({ n: -1 }, 'n', 5, 120, 30)).toBe(5);
    expect(readInt({ n: 1e12 }, 'n', 5, 120, 30)).toBe(120);
    expect(readInt({ n: NaN }, 'n', 5, 120, 30)).toBe(30);
    expect(readInt({ n: Infinity }, 'n', 5, 120, 30)).toBe(30);
    expect(readInt({ n: '7' }, 'n', 5, 120, 30)).toBe(30);
    expect(readInt({ n: null }, 'n', 5, 120, 30)).toBe(30);
    expect(readInt({}, 'n', 5, 120, 30)).toBe(30);
  });
});

describe('isUserId', () => {
  it('accepts lower-case UUIDs only', () => {
    expect(isUserId('2c0c8a9e-3f7a-4a1e-9c0d-1f2e3d4c5b6a')).toBe(true);
    expect(isUserId('2C0C8A9E-3F7A-4A1E-9C0D-1F2E3D4C5B6A')).toBe(false);
    expect(isUserId('not-a-uuid')).toBe(false);
    expect(isUserId(123)).toBe(false);
    expect(isUserId({ userId: 'x' })).toBe(false);
    expect(isUserId('')).toBe(false);
  });
});

describe('normalizeCode', () => {
  it('upper-cases, trims and rejects wrong lengths, characters and types', () => {
    expect(normalizeCode(' abc234 ')).toBe('ABC234');
    expect(normalizeCode('abc')).toBe('');
    expect(normalizeCode('ABC10O')).toBe(''); // 1, 0 and O are not in the alphabet
    expect(normalizeCode('AB C34')).toBe('');
    expect(normalizeCode(123456)).toBe('');
    expect(normalizeCode(['ABC234'])).toBe('');
    expect(normalizeCode(undefined)).toBe('');
    expect(normalizeCode('x'.repeat(100))).toBe('');
  });
});

describe('parseAction', () => {
  it('accepts the four action shapes with integer card ids', () => {
    expect(parseAction('{"type":"take_supply"}')).toEqual({ type: 'take_supply' });
    expect(parseAction('{"type":"take_supply","cardId":"junk"}')).toEqual({ type: 'take_supply' });
    expect(parseAction('{"type":"take_market","cardId":12}')).toEqual({ type: 'take_market', cardId: 12 });
    expect(parseAction('{"type":"play_portfolio","cardId":0}')).toEqual({ type: 'play_portfolio', cardId: 0 });
    expect(parseAction('{"type":"play_market","cardId":3,"extra":true}')).toEqual({ type: 'play_market', cardId: 3 });
  });

  it('returns null (never throws) for anything else', () => {
    for (const bad of ['', 'null', '5', '[]', '{', '{"type":"cheat"}', '{"cardId":1}', '{"type":"take_market"}',
      '{"type":"take_market","cardId":"1"}', '{"type":"take_market","cardId":1.5}', '{"type":"take_market","cardId":-1}',
      '{"type":"take_market","cardId":null}', '{"type":["take_supply"]}', 'ÿþ']) {
      expect(parseAction(bad), bad).toBeNull();
    }
  });
});

describe('guardRpc', () => {
  const logs: string[] = [];
  const logger = { error: (f: string, ...a: unknown[]) => { logs.push(f + a.join(',')); } } as unknown as nkruntime.Logger;
  const ctx = { userId: 'u' } as nkruntime.Context;
  const nk = {} as nkruntime.Nakama;

  it('passes client rejections through unchanged', () => {
    const fn = guardRpc(() => reject('invalid code'));
    expect(() => fn(ctx, logger, nk, '')).toThrow('invalid code');
  });

  it('hides internal errors behind a generic message and logs them', () => {
    logs.length = 0;
    const fn = guardRpc(() => { throw new Error('pq: relation "storage" does not exist'); });
    expect(() => fn(ctx, logger, nk, '')).toThrow('internal error');
    expect(logs.length).toBe(1);
    expect(logs[0]).toContain('does not exist');
  });

  it('returns the handler result when nothing throws', () => {
    const fn = guardRpc(() => '{"ok":true}');
    expect(fn(ctx, logger, nk, '')).toBe('{"ok":true}');
  });
});
