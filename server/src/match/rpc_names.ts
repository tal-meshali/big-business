/**
 * The set_name RPC and the hooks that keep every other way of naming an
 * account under the same rules (names.ts holds the rules).
 *
 * WHY an RPC: Nakama lets a client pick its username when the account is
 * created and change it through UpdateAccount, with no check but length.
 * The name step at first launch and the profile's "Change name" both call
 * set_name instead; the hooks drop a bad name at sign-in and refuse the
 * direct update, so a modified client cannot get around the rules.
 */
import { parseBody, reject, requireUser } from './input';
import { cleanName, NAME_TAKEN, nameProblem } from './names';
import { checkRate } from './ratelimit';

/**
 * RPC set_name {name}: gives the caller the name other players see.
 * Answers {name}; a refusal carries the sentence to show the player.
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
  metadata['named'] = true;
  const unchanged = !!user && user.username === name;
  // WHY the lookup before the write: Nakama reports a taken name as a
  // plain database error, which cannot be told from an outage.
  if (!unchanged && nameHeldByAnother(nk, name, userId)) reject(NAME_TAKEN);
  try {
    nk.accountUpdateId(userId, unchanged ? null : name, null, null, null, null, null, metadata);
  } catch (e) {
    // Two players asked for the same free name at the same moment.
    logger.warn('set_name failed for %s: %s', userId, String(e));
    reject(NAME_TAKEN);
  }
  logger.info('name set for %s', userId);
  return JSON.stringify({ name });
};

const NOBODY = '00000000-0000-0000-0000-000000000000';

/**
 * True when an account other than `userId` has this name in any casing.
 * WHY not usersGetUsername: Nakama's usernames are unique to the letter
 * case, so "Tal" and "tal" would both pass and read as one player.
 */
function nameHeldByAnother(nk: nkruntime.Nakama, name: string, userId: string): boolean {
  const rows = nk.sqlQuery('SELECT id FROM users WHERE lower(username) = lower($1) AND id <> $2::uuid LIMIT 1', [name, userId]);
  return rows.length > 0;
}

/**
 * Indexes names without their letter case, so the lookup above stays quick
 * as accounts grow. Run once at start-up; without the index the lookup
 * still works, only slower.
 */
export function prepareNames(nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
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
 * Clients change their name through set_name only. Nothing else in the
 * account (display name, avatar URL, location) is used by the game, so the
 * direct update is refused outright rather than filtered field by field.
 */
export const beforeUpdateAccount: nkruntime.BeforeHookFunction<nkruntime.UserUpdateAccount> = (ctx, logger, nk, data) => {
  void logger; void nk; void data;
  if (ctx.userId) reject('use set_name');
  return data;
};
