import { describe, expect, it } from 'vitest';
import { cleanName, fold, isNamed, NAME_BAD_CHARACTERS, NAME_NOT_ALLOWED, NAME_TOO_LONG, NAME_TOO_SHORT, nameLength, nameProblem } from './names';
import { ALICE, BOB } from './test_support';
import { beforeAuthenticateDevice, beforeUpdateAccount, rpcSetName } from './rpc_names';

describe('cleanName', () => {
  it('trims and collapses spaces', () => {
    expect(cleanName('  Tal   Meshali ')).toBe('Tal Meshali');
    expect(cleanName('Tal\t\nM')).toBe('Tal M');
  });

  it('answers an empty string for anything that is not text', () => {
    expect(cleanName(42)).toBe('');
    expect(cleanName(null)).toBe('');
    expect(cleanName({ name: 'x' })).toBe('');
  });
});

describe('nameProblem', () => {
  it('accepts ordinary names in any script', () => {
    for (const ok of ['Tal', 'Golden Broker 41', 'maya_k', 'J.R.', 'Noa-Lee', 'טל משעלי', 'Zoë', '山田太郎', 'Cassandra', 'Dickens', 'Analyst Amy', 'Grape Soda']) {
      expect(nameProblem(ok)).toBeNull();
    }
  });

  it('counts characters, not UTF-16 units', () => {
    expect(nameLength('🙂🙂🙂')).toBe(3);
    expect(nameProblem('🙂🙂🙂')).toBeNull();
    expect(nameProblem('ab')).toBe(NAME_TOO_SHORT);
    expect(nameProblem('')).toBe(NAME_TOO_SHORT);
    expect(nameProblem('a'.repeat(16))).toBeNull();
    expect(nameProblem('a'.repeat(17))).toBe(NAME_TOO_LONG);
  });

  it('refuses symbols, controls and invisible characters', () => {
    for (const bad of ['tal@home', 'a<b>c', 'x/y/z', 'semi;colon', 'quote"d', 'new\nline', 'zero​width', 'flip‮ped', 'nb sp', '...', '_-_']) {
      expect(nameProblem(bad)).toBe(NAME_BAD_CHARACTERS);
    }
  });

  it('refuses listed words however they are spaced or spelled', () => {
    expect(fold('F.u_c-K 5h1t')).toBe('fuckshit');
    for (const bad of ['fuck', 'FuCk you', 'f u c k', 'sh1t head', 'b1tch', 'xXn1ggerXx', 'H1tler']) {
      expect(nameProblem(bad)).toBe(NAME_NOT_ALLOWED);
    }
  });

  it('reserves the names of the game, its staff and its bots', () => {
    for (const bad of ['Admin', 'MODERATOR', 'Big Business', 'big_business', 'Intern Ivy', 'analyst avi', 'Bot', 'adm1n']) {
      expect(nameProblem(bad)).toBe(NAME_NOT_ALLOWED);
    }
    expect(nameProblem('Botanist')).toBeNull();
    expect(nameProblem('Administrator Al')).toBeNull();
  });
});

describe('isNamed', () => {
  it('is true only for the flag set_name writes', () => {
    expect(isNamed({ user: { metadata: { named: true } } })).toBe(true);
    expect(isNamed({ user: { metadata: { named: 1 } } })).toBe(false);
    expect(isNamed({ user: { metadata: null } })).toBe(false);
    expect(isNamed({ user: null })).toBe(false);
    expect(isNamed({})).toBe(false);
  });
});

/** A Nakama with accounts by user id, enough for set_name. */
function fakeAccounts(accounts: { [id: string]: { username: string; metadata: { [k: string]: unknown } } }) {
  const rate = new Map<string, { value: unknown; version: string }>();
  let serial = 0;
  const nk = {
    accountGetId: (id: string) => ({ user: { userId: id, ...accounts[id] } }),
    usersGetUsername: (names: string[]) =>
      Object.keys(accounts).filter((id) => names.indexOf(accounts[id]!.username) >= 0).map((id) => ({ userId: id, username: accounts[id]!.username })),
    // The one query set_name runs: who else has this name in any casing.
    sqlQuery: (_q: string, params: string[]) =>
      Object.keys(accounts).filter((id) => id !== params[1] && accounts[id]!.username.toLowerCase() === params[0]!.toLowerCase()).map((id) => ({ id })),
    accountUpdateId: (id: string, username: string | null, _d: unknown, _t: unknown, _l: unknown, _g: unknown, _a: unknown, metadata: { [k: string]: unknown }) => {
      if (username !== null) {
        for (const other of Object.keys(accounts)) if (other !== id && accounts[other]!.username === username) throw new Error('unique violation');
        accounts[id]!.username = username;
      }
      accounts[id]!.metadata = metadata;
    },
    storageRead: (reqs: { key: string; userId: string }[]) => reqs.map((r) => rate.get(r.key + r.userId)).filter((o) => !!o),
    storageWrite: (reqs: { key: string; userId: string; value: unknown }[]) => {
      for (const r of reqs) rate.set(r.key + r.userId, { value: r.value, version: String(++serial) });
    },
  };
  return nk as unknown as nkruntime.Nakama;
}

const logger = { info: () => undefined, warn: () => undefined, error: () => undefined } as unknown as nkruntime.Logger;
const as = (userId: string) => ({ userId }) as unknown as nkruntime.Context;

describe('set_name', () => {
  it('names the account, marks it named and keeps other metadata', () => {
    const accounts = { [ALICE]: { username: 'NmnqzZdeZg', metadata: { theme: 'x' } as { [k: string]: unknown } } };
    const out = JSON.parse(rpcSetName(as(ALICE), logger, fakeAccounts(accounts), JSON.stringify({ name: '  Tal  ' })) as string);
    expect(out).toEqual({ name: 'Tal' });
    expect(accounts[ALICE]).toEqual({ username: 'Tal', metadata: { theme: 'x', named: true } });
  });

  it('accepts the name the account already has, to confirm it', () => {
    const accounts = { [ALICE]: { username: 'Tal', metadata: {} as { [k: string]: unknown } } };
    rpcSetName(as(ALICE), logger, fakeAccounts(accounts), JSON.stringify({ name: 'Tal' }));
    expect(accounts[ALICE]).toEqual({ username: 'Tal', metadata: { named: true } });
  });

  it('refuses a taken name and a name the rules refuse, with the sentence to show', () => {
    const accounts = {
      [ALICE]: { username: 'NmnqzZdeZg', metadata: {} as { [k: string]: unknown } },
      [BOB]: { username: 'Tal', metadata: { named: true } as { [k: string]: unknown } },
    };
    const nk = fakeAccounts(accounts);
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'Tal' }))).toThrow('That name is taken. Try another.');
    // The same letters in another casing are the same name to a reader.
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'tAL' }))).toThrow('That name is taken. Try another.');
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'ab' }))).toThrow(NAME_TOO_SHORT);
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'sh1t' }))).toThrow(NAME_NOT_ALLOWED);
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 7 }))).toThrow(NAME_TOO_SHORT);
    expect(() => rpcSetName(as(ALICE), logger, nk, 'not json')).toThrow('bad payload');
    expect(accounts[ALICE]).toEqual({ username: 'NmnqzZdeZg', metadata: {} });
  });

  it('is rate limited', () => {
    const accounts = { [ALICE]: { username: 'NmnqzZdeZg', metadata: {} as { [k: string]: unknown } } };
    const nk = fakeAccounts(accounts);
    for (let i = 0; i < 6; i++) rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: `Tal ${i}` }));
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'Tal 7' }))).toThrow('too many requests');
  });

  it('needs a signed-in caller', () => {
    expect(() => rpcSetName(as(''), logger, fakeAccounts({}), JSON.stringify({ name: 'Tal' }))).toThrow('unauthenticated');
  });
});

describe('name hooks', () => {
  const nk = fakeAccounts({ [BOB]: { username: 'Dana', metadata: {} } });

  it('drop a refused username at sign-in and keep a good one', () => {
    expect(beforeAuthenticateDevice(as(''), logger, nk, { account: { id: 'd' }, create: true, username: 'sh1thead' })).toMatchObject({ username: '' });
    expect(beforeAuthenticateDevice(as(''), logger, nk, { account: { id: 'd' }, create: true, username: ' Tal ' })).toMatchObject({ username: 'Tal' });
    expect(beforeAuthenticateDevice(as(''), logger, nk, { account: { id: 'd' }, create: true })).toEqual({ account: { id: 'd' }, create: true });
  });

  it('drop a username another account holds in a different casing', () => {
    expect(beforeAuthenticateDevice(as(''), logger, nk, { account: { id: 'd' }, create: true, username: 'DANA' })).toMatchObject({ username: '' });
    // The holder signing in again with its own name is left alone.
    expect(beforeAuthenticateDevice(as(''), logger, nk, { account: { id: 'd' }, create: true, username: 'Dana' })).toMatchObject({ username: 'Dana' });
  });

  it('refuse a direct account update from a client but not from the server', () => {
    expect(() => beforeUpdateAccount(as(ALICE), logger, nk, { userId: ALICE, username: 'anything' })).toThrow('use set_name');
    expect(beforeUpdateAccount(as(''), logger, nk, { userId: ALICE, username: 'x' })).toEqual({ userId: ALICE, username: 'x' });
  });
});
