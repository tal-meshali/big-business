import { describe, expect, it } from 'vitest';
import { isClientError } from './input';
import { loadProfile, saveProfile } from './profile';
import { emptyProgress } from './progression';

function fakeNk(row: Partial<nkruntime.StorageObject> | null, failWrite = false) {
  const writes: nkruntime.StorageWriteRequest[] = [];
  const nk = {
    storageRead: () => (row ? [row] : []),
    storageWrite: (reqs: nkruntime.StorageWriteRequest[]) => {
      if (failWrite) throw new Error('storage write rejected');
      writes.push(...reqs);
      return [];
    },
  } as unknown as nkruntime.Nakama;
  return { nk, writes };
}

describe('loadProfile', () => {
  it('returns an empty profile with no version when the row does not exist', () => {
    const { nk } = fakeNk(null);
    expect(loadProfile(nk, 'u')).toEqual({ progress: emptyProgress(), version: null });
  });

  it('trusts a server-owned row', () => {
    const { nk } = fakeNk({ value: { xp: 500, trackPoints: 300 }, version: 'v1', permissionWrite: 0 });
    const row = loadProfile(nk, 'u');
    expect(row.progress.xp).toBe(500);
    expect(row.progress.trackPoints).toBe(300);
    expect(row.version).toBe('v1');
  });

  it('ignores a row the client created itself (permissionWrite 1) but keeps its version for the replacing write', () => {
    const { nk } = fakeNk({ value: { xp: 999999, trackPoints: 999999, level: 99 }, version: 'v7', permissionWrite: 1 });
    const row = loadProfile(nk, 'u');
    expect(row.progress).toEqual(emptyProgress());
    expect(row.version).toBe('v7');
  });

  it('clamps junk numbers in a server-owned row', () => {
    const { nk } = fakeNk({ value: { xp: -5, level: 0, wins: NaN, trackPoints: 12.9 }, version: 'v1', permissionWrite: 0 });
    const p = loadProfile(nk, 'u').progress;
    expect(p.xp).toBe(0);
    expect(p.level).toBe(1);
    expect(p.wins).toBe(0);
    expect(p.trackPoints).toBe(12);
  });
});

describe('saveProfile', () => {
  it('always writes the row as server-owned and owner-readable', () => {
    const { nk, writes } = fakeNk(null);
    saveProfile(nk, 'u', emptyProgress());
    expect(writes[0]!.permissionWrite).toBe(0);
    expect(writes[0]!.permissionRead).toBe(1);
    expect('version' in writes[0]!).toBe(false);
  });

  it('passes the version through, using "*" for a row that must not exist yet', () => {
    const { nk, writes } = fakeNk(null);
    saveProfile(nk, 'u', emptyProgress(), null);
    saveProfile(nk, 'u', emptyProgress(), 'v3');
    expect(writes[0]!.version).toBe('*');
    expect(writes[1]!.version).toBe('v3');
  });

  it('turns a conditional-write conflict into a client "try again"', () => {
    const { nk } = fakeNk(null, true);
    let err: unknown = null;
    try {
      saveProfile(nk, 'u', emptyProgress(), 'v3');
    } catch (e) {
      err = e;
    }
    expect(isClientError(err)).toBe(true);
    expect((err as Error).message).toBe('try again');
    // An unconditional write failure is not a client error.
    expect(() => saveProfile(nk, 'u', emptyProgress())).toThrow('storage write rejected');
  });
});
