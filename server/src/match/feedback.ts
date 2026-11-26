/**
 * Player feedback: a bug report, an idea or anything else a player wants to
 * tell the team, sent from More > Send feedback. Each message is one
 * server-only row in the `feedback` collection (owner SYSTEM_USER), never
 * shown to other players. The operator reads them with `feedback_list`
 * (server-to-server, runtime http_key; home\feedback.ps1 on the server PC)
 * or in the console (Storage, collection `feedback`), and clears handled
 * ones with `feedback_done`.
 *
 * WHY free text is fine here although D4/D13 keep it away from players:
 * the text only reaches the team, like the support address D4 asks for, so
 * no player under 13 ever sees another player's words. What is stored is
 * kept small: the account id and name (to read it next to reports and to
 * spot abuse), the category, the text, and device details only when the
 * player left them switched on.
 */
import { parseBody, readInt, readString, reject, requireServer, requireUser, type Body } from './input';
import { advanceBucket, checkRate, RATE_COLLECTION, type Bucket } from './ratelimit';
import { SYSTEM_USER } from './protocol';

export const FEEDBACK_COLLECTION = 'feedback';
export const FEEDBACK_CATEGORIES = ['bug', 'idea', 'other'];
export const FEEDBACK_TEXT_MIN = 3;
export const FEEDBACK_TEXT_MAX = 1000;
/** Messages one account may send in 24 hours (from its first), on top of the per-minute limit. */
export const FEEDBACK_PER_DAY = 20;
const DAY_MS = 86_400_000;
/** Device detail fields the client may send, each a short string. */
export const DEVICE_FIELDS = ['app', 'os', 'model', 'screen'];
const DEVICE_FIELD_MAX = 64;

export interface FeedbackRow {
  userId: string;
  name: string;
  category: string;
  text: string;
  device: { [field: string]: string } | null;
  at: number;
}

/**
 * The text as stored: control characters other than line breaks removed,
 * Windows line breaks made plain, at most two empty lines in a row, trimmed.
 */
export function cleanFeedbackText(raw: string): string {
  let out = raw.replace(/\r\n?/g, '\n');
  // eslint-disable-next-line no-control-regex
  out = out.replace(/[\u0000-\u0009\u000b-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g, '');
  out = out.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
  return out.trim();
}

/** Device details the player chose to send, or null; unknown fields are dropped. */
export function readDevice(body: Body): { [field: string]: string } | null {
  const raw = body['device'];
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null;
  const out: { [field: string]: string } = {};
  let any = false;
  for (const f of DEVICE_FIELDS) {
    const v = cleanFeedbackText(readString(raw as Body, f, DEVICE_FIELD_MAX)).replace(/\n/g, ' ');
    if (v) {
      out[f] = v;
      any = true;
    }
  }
  return any ? out : null;
}

/**
 * Storage key that lists newest first: Nakama lists a collection in key
 * order, so the key starts with the time counted down from a far date.
 * The user id part keeps two messages in the same millisecond apart.
 */
export function feedbackKey(now: number, userId: string): string {
  const countdown = String(9_999_999_999_999 - now);
  return `${'0000000000000'.slice(countdown.length)}${countdown}-${userId}`;
}

/** The send time a key was made from (for listing without reading the value). */
export function feedbackKeyTime(key: string): number {
  const n = Number(key.split('-')[0]);
  return isFinite(n) ? 9_999_999_999_999 - n : 0;
}

/**
 * Charges one message to the account's daily allowance: '' when it fits,
 * otherwise the refusal ('daily limit', or 'too many requests' when a
 * second call raced this one).
 */
function chargeDaily(nk: nkruntime.Nakama, userId: string, now: number): string {
  const key = 'send_feedback_day';
  const row = nk.storageRead([{ collection: RATE_COLLECTION, key, userId }])[0];
  const next = advanceBucket(row ? (row.value as Partial<Bucket>) : null, FEEDBACK_PER_DAY, DAY_MS, now);
  if (!next) return 'daily limit';
  try {
    nk.storageWrite([{ collection: RATE_COLLECTION, key, userId, value: next, version: row ? row.version : '*', permissionRead: 0, permissionWrite: 0 }]);
  } catch (e) {
    return 'too many requests';
  }
  return '';
}

/** Why this text cannot be stored, as a sentence for the player; '' when it can. */
export function feedbackTextProblem(text: string): string {
  // WHY code points: the client (Godot) counts an emoji as one character,
  // while JS `.length` counts it as two.
  const length = Array.from(text).length;
  if (length < FEEDBACK_TEXT_MIN) return 'Write a few words first.';
  if (length > FEEDBACK_TEXT_MAX) return `Keep it under ${FEEDBACK_TEXT_MAX} characters.`;
  return '';
}

/** Stores the row under a fresh key and returns it; '' when every try collided. */
function storeFeedback(nk: nkruntime.Nakama, row: FeedbackRow): string {
  // WHY a few tries: two messages from one account in the same millisecond
  // would share a key; the next millisecond's key keeps both.
  for (let attempt = 0; attempt < 5; attempt++) {
    const key = feedbackKey(row.at + attempt, row.userId);
    try {
      nk.storageWrite([{ collection: FEEDBACK_COLLECTION, key, userId: SYSTEM_USER, value: row, version: '*', permissionRead: 0, permissionWrite: 0 }]);
      return key;
    } catch (e) {
      // Taken: try the next millisecond.
    }
  }
  return '';
}

/** RPC send_feedback {category, text, device?}: stores one message for the team. */
export const rpcSendFeedback: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const req = parseBody(payload, 8192);
  const categoryRaw = readString(req, 'category', 16);
  const category = FEEDBACK_CATEGORIES.indexOf(categoryRaw) >= 0 ? categoryRaw : 'other';
  const text = cleanFeedbackText(typeof req['text'] === 'string' ? req['text'] : '');
  const device = readDevice(req);
  const now = Date.now();
  // WHY one refusal point: input.ts's reject() is near the graph's
  // god-node limit (docs/conventions.md), so the checks return sentences.
  let problem = feedbackTextProblem(text);
  // The day's allowance is charged before the store; a failed store (rare)
  // still uses one of the 20.
  if (!problem) {
    checkRate(nk, userId, 'send_feedback', now);
    problem = chargeDaily(nk, userId, now);
  }
  const row: FeedbackRow = { userId, name: String(ctx.username || ''), category, text, device, at: now };
  const key = problem ? '' : storeFeedback(nk, row);
  if (!key) reject(problem || 'try again');
  logger.info('feedback %s from %s (%s, %d chars)', key, userId, category, text.length);
  return JSON.stringify({ ok: true });
};

/**
 * RPC feedback_list {limit?, cursor?} (operator only): messages newest
 * first, each with the `key` that `feedback_done` takes.
 */
export const rpcFeedbackList: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  requireServer(ctx);
  const req = parseBody(payload);
  const limit = readInt(req, 'limit', 1, 100, 20);
  const cursor = readString(req, 'cursor', 512);
  const page = nk.storageList(SYSTEM_USER, FEEDBACK_COLLECTION, limit, cursor || undefined);
  const items = (page.objects || []).map((o) => ({ key: o.key, ...(o.value as object) }));
  return JSON.stringify({ items, cursor: page.cursor || '' });
};

/** Messages older than this are deleted by `feedback_done {olderThanDays}` (D29). */
export const FEEDBACK_KEEP_DAYS = 90;
const FEEDBACK_KEY_RE = /^\d{13}-[0-9a-f-]{36}$/;

/** Every stored message's key and value, newest first (the operator's purges). */
function allFeedback(nk: nkruntime.Nakama): nkruntime.StorageObject[] {
  const out: nkruntime.StorageObject[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < 1000; page++) {
    const res = nk.storageList(SYSTEM_USER, FEEDBACK_COLLECTION, 100, cursor);
    for (const o of res.objects || []) out.push(o);
    cursor = res.cursor || undefined;
    if (!cursor) break;
  }
  return out;
}

/**
 * RPC feedback_done (operator only) deletes messages, by one of:
 * {key} or {keys: [...]} (handled ones), {userId} (everything one player
 * sent, for a deletion request), or {olderThanDays} (at least 30; the
 * retention purge home\feedback.ps1 runs with FEEDBACK_KEEP_DAYS).
 * Answers {deleted, skipped}; skipped counts keys that were not feedback keys.
 */
export const rpcFeedbackDone: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  requireServer(ctx);
  const req = parseBody(payload);
  let keys: string[] = [];
  let skipped = 0;
  const userId = req['userId'];
  const days = req['olderThanDays'];
  if (typeof userId === 'string' && userId) {
    keys = allFeedback(nk).filter((o) => (o.value as { userId?: unknown }).userId === userId).map((o) => o.key);
  } else if (typeof days === 'number' && isFinite(days) && days >= 30) {
    const cutoff = Date.now() - days * DAY_MS;
    keys = allFeedback(nk).filter((o) => feedbackKeyTime(o.key) < cutoff).map((o) => o.key);
  } else {
    const raw = Array.isArray(req['keys']) ? (req['keys'] as unknown[]) : [req['key']];
    keys = raw.filter((k): k is string => typeof k === 'string' && FEEDBACK_KEY_RE.test(k)).slice(0, 100);
    skipped = raw.length - keys.length;
  }
  for (let i = 0; i < keys.length; i += 100) {
    nk.storageDelete(keys.slice(i, i + 100).map((key) => ({ collection: FEEDBACK_COLLECTION, key, userId: SYSTEM_USER })));
  }
  if (keys.length) logger.info('feedback done: %d message(s)', keys.length);
  return JSON.stringify({ deleted: keys.length, skipped });
};
