import { describe, expect, it } from 'vitest';
import { cleanName, fold, isNamed, NAME_BAD_CHARACTERS, NAME_DIGITS, NAME_LOCKED, NAME_MIXED, NAME_NOT_ALLOWED, NAME_TAKEN, NAME_TOO_LONG, NAME_TOO_SHORT, nameLength, nameProblem } from './names';
import { ALICE, BOB } from './test_support';
import { beforeAuthenticateDevice, beforeUpdateAccount, refuseSignIn, rpcSetName, userByName } from './rpc_names';

describe('cleanName', () => {
  it('trims and collapses spaces', () => {
    expect(cleanName('  Tal   Meshali ')).toBe('Tal Meshali');
    expect(cleanName('Tal\t\nM')).toBe('Tal M');
  });

  it('folds compatibility forms to the plain ones', () => {
    expect(cleanName('\uff34\uff41\uff4c')).toBe('Tal');
    expect(cleanName('Tal\u00a0\u3000M')).toBe('Tal M');
    expect(cleanName('Zoe\u0308')).toBe('Zo\u00eb');
  });

  it('answers an empty string for anything that is not text', () => {
    expect(cleanName(42)).toBe('');
    expect(cleanName(null)).toBe('');
    expect(cleanName({ name: 'x' })).toBe('');
  });
});

describe('nameProblem', () => {
  it('accepts ordinary names in the listed alphabets', () => {
    const ok = ['Tal', 'Bo', 'Golden Broker 41', 'maya_k', 'Noa-Lee', 'Zo\u00eb', 'Nguy\u1ec5n', '\u05d8\u05dc', '\u05d8\u05dc \u05de\u05e9\u05e2\u05dc\u05d9', 'Tal \u05d8\u05dc',
      '\u592a\u90ce', '\u5c71\u7530\u592a\u90ce', '\uc9c0\ubbfc', '\u0418\u0432\u0430\u043d', '\u039d\u03af\u03ba\u03bf\u03c2', '\u0639\u0644\u064a', 'Player 7'];
    for (const name of ok) expect(nameProblem(name)).toBeNull();
  });

  it('counts characters, not UTF-16 units', () => {
    expect(nameLength('\ud83d\ude42\ud83d\ude42\ud83d\ude42')).toBe(3);
    expect(nameProblem('a')).toBe(NAME_TOO_SHORT);
    expect(nameProblem('')).toBe(NAME_TOO_SHORT);
    expect(nameProblem('a'.repeat(16))).toBeNull();
    expect(nameProblem('a'.repeat(17))).toBe(NAME_TOO_LONG);
  });

  it('refuses symbols, emoji, controls and anything invisible', () => {
    const bad = ['tal@home', 'a<b>c', 'x/y/z', 'semi;colon', 'quote"d', 'new\nline', 't.me.kiddo', 'J.R.', '...', '_-_', '\ud83d\ude42\ud83d\ude42\ud83d\ude42',
      // Zero width space, right-to-left override, no-break space (when not cleaned), Hangul filler,
      // braille blank, variation selector, Arabic letter mark, a lone surrogate, a tag character, a combining mark left over.
      'zero\u200bwidth', 'flip\u202eped', 'nb\u00a0sp', '\u3164\u3164\u3164', '\u2800\u2800\u2800', 'Tal\ufe0f', 'Tal\u061c', 'Tal\ud800', 'Tal\udb40\udc41', 'Ta\u0336l'];
    for (const name of bad) expect(nameProblem(name)).toBe(NAME_BAD_CHARACTERS);
  });

  it('refuses a name that borrows look-alike letters from another alphabet', () => {
    // Cyrillic A in "Admin", Cyrillic es in a listed word, Greek omicron in "Tom".
    for (const name of ['\u0410dmin', 'fu\u0441k', 'T\u03bfm']) expect(nameProblem(name)).toBe(NAME_MIXED);
  });

  it('refuses listed words however they are spaced or spelled', () => {
    expect(fold('F-u_c K 5h1t')).toBe('fuckshit');
    for (const bad of ['fuck', 'FuCk you', 'f u c k', 'sh1t head', 'Sh1tHead', 's h i t', 'shit99', 'b1tch', 'xXn1ggerXx', 'H1tler', 'f\u00fcck', 'NaziKing', 'nazis', 'Porn Hub', 'porn4u', 'nazi4life']) {
      expect(nameProblem(cleanName(bad))).toBe(NAME_NOT_ALLOWED);
    }
    expect(nameProblem(cleanName('\uff46\uff55\uff43\uff4b'))).toBe(NAME_NOT_ALLOWED);
  });

  it('reads look-alike letters as the Latin ones they copy', () => {
    // Dotless i, o with a stroke; then whole words in Greek and in Cyrillic capitals.
    const bad = ['Adm\u0131n', 'Offic\u0131al', 'Moderat\u00f8r', 'sh\u0131t', 'h\u0131tler', '\u039d\u0391\u0396\u0399', '\u0392\u039f\u03a4', '\u0412\u041e\u0422', '\u0405\u041d\u0406\u0422', '\u0412\u0406\u0422\u0421\u041d'];
    for (const name of bad) expect(nameProblem(name)).toBe(NAME_NOT_ALLOWED);
    // Ordinary names in those alphabets and with those letters still pass.
    for (const ok of ['Y\u0131ld\u0131z', 'S\u00f8ren', '\u0412\u0435\u0440\u0430', '\u041c\u0430\u043a\u0441', '\u0395\u03bb\u03ad\u03bd\u03b7']) expect(nameProblem(ok)).toBeNull();
  });

  it('needs letters, and refuses a phone number', () => {
    for (const name of ['0544123456', '054-412-3456', 'call 0544123456', '12', '7 7']) expect(nameProblem(name)).toBe(NAME_DIGITS);
    for (const ok of ['Player 123456', 'R2D2', 'Tal 7']) expect(nameProblem(ok)).toBeNull();
  });

  it('allows marks on a letter but not a stack of them', () => {
    // Singh in Devanagari and a Thai word with a vowel and a tone mark on one letter.
    for (const ok of ['\u0938\u093f\u0902\u0939', '\u0905\u0902\u0915\u093f\u0924', '\u0e17\u0e35\u0e48']) expect(nameProblem(ok)).toBeNull();
    // Fifteen marks on one Thai letter, the same in Devanagari, marks alone, a mark first.
    const bad = ['\u0e01' + '\u0e47'.repeat(15), '\u0915' + '\u0941'.repeat(15), '\u0e34\u0e34', '\u0e34\u0e01\u0e01', 'a \u0e34b'];
    for (const name of bad) expect(nameProblem(name)).toBe(NAME_BAD_CHARACTERS);
  });

  it('allows one separator between words and none at the ends', () => {
    for (const name of ['a---b', '_a_', '- a -', 'ab-', '-ab', 'a - b', 'a__b']) expect(nameProblem(name)).toBe(NAME_BAD_CHARACTERS);
    for (const ok of ['Noa-Lee', 'maya_k', 'a b c d']) expect(nameProblem(ok)).toBeNull();
  });

  it('lets ordinary names through that only contain a listed word', () => {
    for (const ok of ['Yamashita', 'Nazir', 'Benazir', 'Therapist', 'Swank', 'Pornchai', 'Push It', 'Mass Hit', 'Cassandra', 'Dickens', 'Analyst Amy', 'Grape Soda', 'Badminton', 'Botanist', 'Modesty', 'Devon', 'Systematic', 'Dev', 'Dev Patel', 'Stafford', 'Staffan']) {
      expect(nameProblem(ok)).toBeNull();
    }
  });

  it('reserves the names of the game, its staff and its bots', () => {
    const bad = ['Admin', 'Admin1', 'Admin 2', 'adm1n', 'Administrator Al', 'MODERATOR', 'Moderator 7', 'Support Team', 'Official Mod', 'Tal Mod', 'Staff', 'System', 'Owner', 'theadmin', 'RealAdmin', 'xadmin', 'IAdmin', 'unofficial',
      'Big Business', 'big_business', 'Big Business HQ', 'Intern Ivy', 'analyst avi', 'CEO Cal', 'Bot', 'Tal Bot'];
    for (const name of bad) expect(nameProblem(name)).toBe(NAME_NOT_ALLOWED);
  });

  it('never says " at ", where the client cuts a server error', () => {
    for (const sentence of [NAME_TOO_SHORT, NAME_TOO_LONG, NAME_BAD_CHARACTERS, NAME_DIGITS, NAME_MIXED, NAME_NOT_ALLOWED, NAME_TAKEN, NAME_LOCKED]) {
      expect(sentence).not.toContain(' at ');
      expect(sentence.endsWith('.')).toBe(true);
      expect(sentence.length).toBeLessThan(80);
    }
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
    // The name lookups: who else has this name in any casing, the exact spelling first.
    sqlQuery: (_q: string, params: string[]) =>
      Object.keys(accounts).filter((id) => id !== params[1] && accounts[id]!.username.toLowerCase() === params[0]!.toLowerCase())
        .sort((a, b) => Number(accounts[b]!.username === params[0]) - Number(accounts[a]!.username === params[0]))
        .map((id) => ({ id, username: accounts[id]!.username })),
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
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'a' }))).toThrow(NAME_TOO_SHORT);
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'sh1t' }))).toThrow(NAME_NOT_ALLOWED);
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 7 }))).toThrow(NAME_TOO_SHORT);
    expect(() => rpcSetName(as(ALICE), logger, nk, 'not json')).toThrow('bad payload');
    expect(accounts[ALICE]).toEqual({ username: 'NmnqzZdeZg', metadata: {} });
  });

  it('is rate limited', () => {
    const accounts = { [ALICE]: { username: 'NmnqzZdeZg', metadata: {} as { [k: string]: unknown } } };
    const nk = fakeAccounts(accounts);
    for (let i = 0; i < 10; i++) rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: `Tal ${i}` }));
    expect(() => rpcSetName(as(ALICE), logger, nk, JSON.stringify({ name: 'Tal 11' }))).toThrow('too many requests');
  });

  it('keeps a name a moderator locked', () => {
    const accounts = { [ALICE]: { username: 'Player 4821', metadata: { named: true, nameLocked: true } as { [k: string]: unknown } } };
    expect(() => rpcSetName(as(ALICE), logger, fakeAccounts(accounts), JSON.stringify({ name: 'Tal' }))).toThrow(NAME_LOCKED);
    expect(accounts[ALICE]!.username).toBe('Player 4821');
  });

  it('reports an outage as an outage, not as a taken name', () => {
    const accounts = { [ALICE]: { username: 'NmnqzZdeZg', metadata: {} as { [k: string]: unknown } } };
    const nk = fakeAccounts(accounts) as unknown as { accountUpdateId: () => void };
    nk.accountUpdateId = () => { throw new Error('connection refused'); };
    expect(() => rpcSetName(as(ALICE), logger, nk as unknown as nkruntime.Nakama, JSON.stringify({ name: 'Tal' }))).toThrow('connection refused');
  });

  it('says taken when another player won the name between the lookup and the write', () => {
    const accounts: { [id: string]: { username: string; metadata: { [k: string]: unknown } } } = { [ALICE]: { username: 'NmnqzZdeZg', metadata: {} } };
    const nk = fakeAccounts(accounts) as unknown as { accountUpdateId: () => void };
    nk.accountUpdateId = () => {
      accounts[BOB] = { username: 'tal', metadata: { named: true } };
      throw new Error('unique violation');
    };
    expect(() => rpcSetName(as(ALICE), logger, nk as unknown as nkruntime.Nakama, JSON.stringify({ name: 'Tal' }))).toThrow(NAME_TAKEN);
  });

  it('needs a signed-in caller', () => {
    expect(() => rpcSetName(as(''), logger, fakeAccounts({}), JSON.stringify({ name: 'Tal' }))).toThrow('unauthenticated');
  });
});

describe('userByName', () => {
  it('finds a player in any letter case, the exact spelling first', () => {
    const nk = fakeAccounts({ [ALICE]: { username: 'tal', metadata: {} }, [BOB]: { username: 'Tal', metadata: {} } });
    expect(userByName(nk, 'Tal', '')).toEqual({ userId: BOB, username: 'Tal' });
    expect(userByName(nk, 'TAL', '')).not.toBeNull();
    expect(userByName(nk, 'Dana', '')).toBeNull();
    // Never the caller: "tal" looking for "TAL" finds the other account.
    expect(userByName(nk, 'TAL', ALICE)).toEqual({ userId: BOB, username: 'Tal' });
    expect(userByName(nk, 'tal', BOB)).toEqual({ userId: ALICE, username: 'tal' });
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

  it('refuse the sign-in methods the game does not offer', () => {
    expect(() => refuseSignIn()).toThrow('sign-in method not available');
  });

  it('refuse a direct account update from a client but not from the server', () => {
    expect(() => beforeUpdateAccount(as(ALICE), logger, nk, { userId: ALICE, username: 'anything' })).toThrow('use set_name');
    expect(beforeUpdateAccount(as(''), logger, nk, { userId: ALICE, username: 'x' })).toEqual({ userId: ALICE, username: 'x' });
  });
});
