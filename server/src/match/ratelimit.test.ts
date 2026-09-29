import { describe, expect, it } from 'vitest';
import { advanceBucket, checkRate, RATE_LIMITS } from './ratelimit';
import { isClientError } from './input';

describe('advanceBucket', () => {
  it('starts a window on the first call and counts up to the limit', () => {
    let b = advanceBucket(null, 3, 1000, 5000);
    expect(b).toEqual({ start: 5000, count: 1 });
    b = advanceBucket(b, 3, 1000, 5100);
    expect(b).toEqual({ start: 5000, count: 2 });
    b = advanceBucket(b, 3, 1000, 5200);
    expect(b).toEqual({ start: 5000, count: 3 });
    expect(advanceBucket(b, 3, 1000, 5300)).toBeNull();
  });

  it('opens a fresh window once the old one has passed', () => {
    const full = { start: 5000, count: 3 };
    expect(advanceBucket(full, 3, 1000, 6000)).toEqual({ start: 6000, count: 1 });
  });

  it('treats malformed rows and clocks in the future as empty', () => {
    expect(advanceBucket({ start: 'x' as unknown as number, count: 99 }, 3, 1000, 5000)).toEqual({ start: 5000, count: 1 });
    expect(advanceBucket({ start: 9000, count: 99 }, 3, 1000, 5000)).toEqual({ start: 5000, count: 1 });
    expect(advanceBucket({}, 3, 1000, 5000)).toEqual({ start: 5000, count: 1 });
  });
});

describe('checkRate', () => {
  function fakeNk(conflictOn: number = -1) {
    const rows: { [key: string]: { value: unknown; version: string } } = {};
    let writes = 0;
    const nk = {
      storageRead: (reqs: nkruntime.StorageReadRequest[]) => {
        const req = reqs[0]!;
        const row = rows[`${req.userId}/${req.key}`];
        return row ? [{ key: req.key, collection: req.collection, userId: req.userId, value: row.value, version: row.version }] : [];
      },
      storageWrite: (reqs: nkruntime.StorageWriteRequest[]) => {
        const req = reqs[0]!;
        writes++;
        if (writes === conflictOn) throw new Error('storage write rejected');
        const id = `${req.userId}/${req.key}`;
        const current = rows[id];
        if (req.version === '*' && current) throw new Error('exists');
        if (req.version && req.version !== '*' && (!current || current.version !== req.version)) throw new Error('version mismatch');
        expect(req.permissionRead).toBe(0);
        expect(req.permissionWrite).toBe(0);
        rows[id] = { value: req.value, version: `v${writes}` };
        return [];
      },
    } as unknown as nkruntime.Nakama;
    return nk;
  }

  it('allows the limit and rejects the call after it with a client error', () => {
    const nk = fakeNk();
    const limit = RATE_LIMITS.report_player;
    for (let i = 0; i < limit; i++) checkRate(nk, 'u1', 'report_player', 1000 + i);
    let err: unknown = null;
    try {
      checkRate(nk, 'u1', 'report_player', 2000);
    } catch (e) {
      err = e;
    }
    expect(isClientError(err)).toBe(true);
    expect((err as Error).message).toBe('too many requests');
    // Other users and other buckets are unaffected.
    checkRate(nk, 'u2', 'report_player', 2000);
    checkRate(nk, 'u1', 'find_player', 2000);
  });

  it('treats a write conflict as limited', () => {
    const nk = fakeNk(1);
    expect(() => checkRate(nk, 'u1', 'create_room', 1000)).toThrow('too many requests');
  });
});
