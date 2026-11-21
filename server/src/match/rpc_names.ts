/**
 * The set_name RPC and the hooks that keep every other way of naming an
 * account under the same rules (names.ts holds the rules).
 *
 * WHY an RPC: Nakama lets a client pick its username when the account is
 * created and change it through UpdateAccount, with no check but length.
 * The name step at first launch and the profile's "Change name" both call
 * set_name instead; the hooks drop a bad name at sign-in, refuse the
 * sign-in methods the game does not offer and refuse the direct update, so
 * a modified client cannot get around the rules.
 */
import { parseBody, reject, requireUser } from './input';
import { cleanName, NAME_LOCKED, NAME_TAKEN, nameProblem } from './names';
import { checkRate } from './ratelimit';

const NOBODY = '00000000-0000-0000-0000-000000000000';

/**
 * RPC set_name {name}: gives the caller the name other players see.
 * Answers {name}; a refusal carries the sentence to show the player.
 *
 * An operator who renames a player after a report (Nakama console) adds
 * `nameLocked: true` to the account's metadata to keep the name in place.
 */
export const rpcSetName: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const name = cleanName(parseBody(payload)['name']);
  const problem = nameProblem(name);
  if (problem) reject(problem);
  checkRate(nk, userId, 'set_name', Date.now());
  const account = nk.accountGetId(userId);
  const user = account.user;
  const metadata: { [key: string]: unknown } = {};
  const old = (user && user.metadata) || {};
  for (const k of Object.keys(old)) metadata[k] = old[k];
  if (metadata['nameLocked'] === true) reject(NAME_LOCKED);
  metadata['named'] = true;
  const unchanged = !!user && user.username === name;
  // WHY the lookup before the write: Nakama reports a taken name as a
  // plain database error, which cannot be told from an outage.
  if (!unchanged && nameHeldByAnother(nk, name, userId)) reject(NAME_TAKEN);
  try {
    nk.accountUpdateId(userId, unchanged ? null : name, null, null, null, null, null, metadata);
  } catch (e) {
    logger.warn('set_name failed for %s: %s', userId, String(e));
    // Two players asked for the same free name at the same moment; anything
    // else is an outage and must not read as a problem with the name.
    if (!unchanged && nameHeldByAnother(nk, name, userId)) reject(NAME_TAKEN);
    throw e;
  }
  logger.info('name set for %s', userId);
  return JSON.stringify({ name });
};

/**
 * True when an account other than `userId` has this name in any casing.
 * WHY not usersGetUsername: Nakama's usernames are unique to the letter
 * case, so "Tal" and "tal" would both pass and read as one player.
 * Letters outside ASCII fold only as far as the database's locale allows.
 */
export function nameHeldByAnother(nk: nkruntime.Nakama, name: string, userId: string): boolean {
  return nk.sqlQuery('SELECT id FROM users WHERE lower(username) = lower($1) AND id <> $2::uuid LIMIT 1', [name, userId]).length > 0;
}

/**
 * The account with this name in any casing, the exact spelling first;
 * null when there is none. For find_player, so "tal" finds "Tal".
 */
export function userByName(nk: nkruntime.Nakama, name: string): { userId: string; username: string } | null {
  const rows = nk.sqlQuery('SELECT id, username FROM users WHERE lower(username) = lower($1) AND id <> $2::uuid ORDER BY (username = $1) DESC LIMIT 1', [name, NOBODY]);
  const row = rows[0];
  return row ? { userId: String(row['id']), username: String(row['username']) } : null;
}

/**
 * Indexes names without their letter case, so the lookups above stay quick
 * and two players cannot take "Tal" and "tal" in the same instant. Run
 * once at start-up. A database that already holds two such names (from
 * before the name rules) gets a plain index instead; without any index the
 * lookups still work, only slower.
 */
export function prepareNames(nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  try {
    nk.sqlExec('CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key ON users (lower(username))', []);
    return;
  } catch (e) {
    logger.warn('names are not unique without their case yet: %s', String(e));
  }
  try {
    nk.sqlExec('CREATE INDEX IF NOT EXISTS users_username_lower_idx ON users (lower(username))', []);
  } catch (e) {
    logger.warn('could not index names: %s', String(e));
  }
}

/**
 * Drops a username from a sign-in request when the rules refuse it or
 * another account holds it in any casing, so a new account gets Nakama's
 * random one and is asked for a name. The game's own client sends none.
 */
function withCheckedUsername<T extends { username?: string }>(nk: nkruntime.Nakama, data: T): T {
  if (!data.username) return data;
  const name = cleanName(data.username);
  // WHY an exact holder passes: a sign-in to an existing account may carry
  // its own name, which Nakama then ignores.
  const exact = nk.usersGetUsername([name]).length > 0;
  data.username = nameProblem(name) !== null || (!exact && nameHeldByAnother(nk, name, NOBODY)) ? '' : name;
  return data;
}

export const beforeAuthenticateDevice: nkruntime.BeforeHookFunction<nkruntime.AuthenticateDeviceRequest> = (ctx, logger, nk, data) => {
  void ctx; void logger;
  return withCheckedUsername(nk, data);
};

export const beforeAuthenticateApple: nkruntime.BeforeHookFunction<nkruntime.AuthenticateAppleRequest> = (ctx, logger, nk, data) => {
  void ctx; void logger;
  return withCheckedUsername(nk, data);
};

export const beforeAuthenticateGoogle: nkruntime.BeforeHookFunction<nkruntime.AuthenticateGoogleRequest> = (ctx, logger, nk, data) => {
  void ctx; void logger;
  return withCheckedUsername(nk, data);
};

/**
 * Refuses a sign-in method the game does not offer (custom id, email,
 * Facebook, Game Center, Steam).
 * WHY: Nakama serves them all by default, and each would create an account
 * under any username with nothing but the key every client ships with.
 */
export const refuseSignIn = (): never => reject('sign-in method not available');

/**
 * Clients change their name through set_name only. Nothing else in the
 * account (display name, avatar URL, location) is used by the game, so the
 * direct update is refused outright rather than filtered field by field.
 */
export const beforeUpdateAccount: nkruntime.BeforeHookFunction<nkruntime.UserUpdateAccount> = (ctx, logger, nk, data) => {
  void logger; void nk; void data;
  if (ctx.userId) reject('use set_name');
  return data;
};
