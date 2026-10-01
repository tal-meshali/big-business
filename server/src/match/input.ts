/**
 * Input validation for everything a client can send: RPC payloads and match
 * messages. Pure functions (unit-tested in input.test.ts) plus the small
 * `guardRpc` wrapper that keeps internal errors out of client responses.
 *
 * WHY: the client is untrusted. A modified client can send any JSON (or no
 * JSON) in any field, so every handler goes through these helpers instead of
 * casting `JSON.parse(payload)` to the type it hopes for. Runs in goja
 * (ES2016 library only).
 */
import type { Action } from '../engine';

/** A plain JSON object parsed from a client payload; values are still unchecked. */
export type Body = { [key: string]: unknown };

/** Marker property on errors that carry a message meant for the client. */
const CLIENT_ERROR = '__bigBusinessClientError';

/** Throws an error whose message is safe to return to the client. */
export function reject(message: string): never {
  const e = new Error(message) as Error & { [key: string]: unknown };
  e[CLIENT_ERROR] = true;
  throw e;
}

export function isClientError(e: unknown): boolean {
  return typeof e === 'object' && e !== null && (e as { [key: string]: unknown })[CLIENT_ERROR] === true;
}

/** The caller's user id; RPCs are never served to unauthenticated callers. */
export function requireUser(ctx: nkruntime.Context): string {
  if (!ctx.userId) reject('unauthenticated');
  return ctx.userId;
}

/**
 * Parses an RPC payload into a plain object. Empty payloads are `{}`;
 * malformed JSON, arrays and primitives are rejected with a short message.
 */
export function parseBody(payload: string | null | undefined): Body {
  if (payload === undefined || payload === null || payload === '') return {};
  if (typeof payload !== 'string' || payload.length > 4096) reject('bad payload');
  let parsed: unknown;
  try {
    parsed = JSON.parse(payload);
  } catch (e) {
    reject('bad payload');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) reject('bad payload');
  return parsed as Body;
}

/** A trimmed string field of at most `maxLength` characters, or '' when absent or not a string. */
export function readString(body: Body, key: string, maxLength: number): string {
  const v = body[key];
  if (typeof v !== 'string') return '';
  const t = v.trim();
  return t.length > maxLength ? t.slice(0, maxLength) : t;
}

/** An integer field clamped to [min, max]; `fallback` when absent or not a finite number. */
export function readInt(body: Body, key: string, min: number, max: number, fallback: number): number {
  const v = body[key];
  if (typeof v !== 'number' || !isFinite(v)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(v)));
}

export function readBool(body: Body, key: string): boolean {
  return body[key] === true;
}

const USER_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Nakama user ids are lower-case UUIDs; anything else is rejected before it reaches storage. */
export function isUserId(v: unknown): v is string {
  return typeof v === 'string' && USER_ID_RE.test(v);
}

/** Room codes: 6 characters from the alphabet in main.ts (no 0/O/1/I). */
export const ROOM_CODE_RE = /^[A-HJ-NP-Z2-9]{6}$/;

/** Upper-cases and trims a room code; returns '' when it cannot be one. */
export function normalizeCode(code: unknown): string {
  if (typeof code !== 'string' || code.length > 16) return '';
  const c = code.trim().toUpperCase();
  return ROOM_CODE_RE.test(c) ? c : '';
}

/** Nakama usernames: 1-128 characters. Anything longer cannot match a user. */
export const USERNAME_MAX = 128;
/** Match ids are "<uuid>.<node>"; bound the length so junk never fills a report. */
export const MATCH_ID_MAX = 128;
export const REPORT_NOTE_MAX = 200;
/** Largest OP_ACTION / OP_EMOTE payload worth parsing; real ones are under 64 bytes. */
export const MAX_ACTION_BYTES = 256;
export const MAX_EMOTE_BYTES = 128;

/**
 * Parses an OP_ACTION payload into a well-typed Action, or null. Only the
 * four action types with an integer cardId where one is required pass; the
 * engine then decides legality. Never throws.
 */
export function parseAction(text: string): Action | null {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    return null;
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null;
  const obj = raw as Body;
  const type = obj['type'];
  if (type === 'take_supply') return { type: 'take_supply' };
  if (type !== 'take_market' && type !== 'play_portfolio' && type !== 'play_market') return null;
  const cardId = obj['cardId'];
  if (typeof cardId !== 'number' || !isFinite(cardId) || Math.floor(cardId) !== cardId || cardId < 0) return null;
  return { type, cardId };
}

/**
 * Wraps an RPC so that only messages raised with `reject` reach the client.
 * Anything else (storage failures, bugs) is logged and returned as
 * 'internal error', so stack traces and SQL never leave the server.
 */
export function guardRpc(fn: nkruntime.RpcFunction): nkruntime.RpcFunction {
  return (ctx, logger, nk, payload) => guarded(fn, ctx, logger, nk, payload);
}

/**
 * Runs one RPC under the guard. WHY: Nakama's JS runtime resolves each
 * `registerRpc` argument to a named function literal in the module source
 * ("javascript functions cannot be inlined"), so main.ts cannot register
 * `guardRpc(fn)` directly; it registers a named arrow that calls this.
 */
export function guarded(
  fn: nkruntime.RpcFunction,
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string,
): string | void {
  try {
    return fn(ctx, logger, nk, payload);
  } catch (e) {
    if (isClientError(e)) throw e;
    logger.error('rpc failed for %s: %s', ctx.userId || '-', String(e));
    throw new Error('internal error');
  }
}
