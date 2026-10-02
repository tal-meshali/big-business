/**
 * "Your turn" push notifications through Firebase Cloud Messaging (HTTP v1).
 * Pure: the device-token row, when a push is due, and the request bodies.
 * Storage and HTTP are in push_sender.ts; token registration in rpc_push.ts.
 *
 * Config (Nakama runtime env, docs/deploy.md): FCM_PROJECT_ID,
 * FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY from a Firebase service account with
 * the "Firebase Cloud Messaging API Admin" role. Without them nothing is sent.
 */

export const PUSH_COLLECTION = 'push';
export const PUSH_TOKENS_KEY = 'tokens';
/** Cached OAuth access token for FCM, owned by the system user. */
export const PUSH_OAUTH_KEY = 'oauth';
/** Devices kept per player: a phone and a tablet, plus one stale entry. */
export const MAX_TOKENS = 3;
/** Timed games with shorter steps auto-play before anyone could come back. */
export const PUSH_MIN_STEP_SECONDS = 30;
/** After this many failed sends a match stops trying (FCM down or misconfigured). */
export const PUSH_MAX_FAILURES = 3;

export const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
export const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

export type PushPlatform = 'android' | 'ios';

export interface DeviceToken {
  token: string;
  platform: PushPlatform;
  /** Epoch ms of the last registration. */
  at: number;
}

const TOKEN_RE = /^[A-Za-z0-9_:.\-]{20,512}$/;

/** FCM registration tokens are long URL-safe strings; anything else is refused. */
export function isPushToken(v: unknown): v is string {
  return typeof v === 'string' && TOKEN_RE.test(v);
}

export function normalizeTokens(raw: unknown): DeviceToken[] {
  const list = typeof raw === 'object' && raw !== null ? (raw as { tokens?: unknown }).tokens : null;
  const out: DeviceToken[] = [];
  if (!Array.isArray(list)) return out;
  for (const t of list) {
    if (typeof t !== 'object' || t === null) continue;
    const e = t as { token?: unknown; platform?: unknown; at?: unknown };
    if (!isPushToken(e.token) || (e.platform !== 'android' && e.platform !== 'ios')) continue;
    out.push({ token: e.token, platform: e.platform, at: typeof e.at === 'number' && isFinite(e.at) ? e.at : 0 });
    if (out.length >= MAX_TOKENS) break;
  }
  return out;
}

/** Newest first, each token once, at most MAX_TOKENS (the oldest drops off). */
export function addToken(list: ReadonlyArray<DeviceToken>, token: string, platform: PushPlatform, nowMs: number): DeviceToken[] {
  const rest = list.filter((t) => t.token !== token);
  return [{ token, platform, at: nowMs }].concat(rest).slice(0, MAX_TOKENS);
}

export function removeToken(list: ReadonlyArray<DeviceToken>, token: string): DeviceToken[] {
  return list.filter((t) => t.token !== token);
}

export interface PushCheck {
  /** The seat is played by a person (not a bot, not taken over after timeouts). */
  human: boolean;
  /** The player's socket is in the match. */
  connected: boolean;
  forfeited: boolean;
  tutorial: boolean;
  stepSeconds: number;
  /** Epoch ms of this player's last push in this match; 0 when none. */
  lastSentAt: number;
  nowMs: number;
  cooldownMs: number;
  failures: number;
}

/**
 * A push is due when a turn starts for a person who is not looking: away
 * from the match, in a game slow enough to come back to, and not pushed
 * within the cooldown (research section 6: behaviour-triggered and capped).
 */
export function shouldPush(c: PushCheck): boolean {
  if (!c.human || c.connected || c.forfeited || c.tutorial) return false;
  if (c.stepSeconds > 0 && c.stepSeconds < PUSH_MIN_STEP_SECONDS) return false;
  if (c.failures >= PUSH_MAX_FAILURES) return false;
  return c.lastSentAt === 0 || c.nowMs - c.lastSentAt >= c.cooldownMs;
}

export interface FcmConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

/** The service-account settings from the runtime env, or null when any is missing. */
export function fcmConfig(env: { [key: string]: string } | undefined): FcmConfig | null {
  if (!env) return null;
  const projectId = (env['FCM_PROJECT_ID'] || '').trim();
  const clientEmail = (env['FCM_CLIENT_EMAIL'] || '').trim();
  // WHY: a PEM key passed through .env and a command-line flag keeps its
  // line breaks as the two characters "\n"; turn them back into newlines.
  const privateKey = (env['FCM_PRIVATE_KEY'] || '').replace(/\\n/g, '\n').trim();
  if (!projectId || !clientEmail || privateKey.indexOf('PRIVATE KEY') < 0) return null;
  return { projectId, clientEmail, privateKey };
}

/** Claims of the service-account JWT exchanged for an access token (valid one hour). */
export function oauthClaims(clientEmail: string, nowSec: number): { [k: string]: string | number } {
  return { iss: clientEmail, scope: FCM_SCOPE, aud: OAUTH_TOKEN_URL, iat: nowSec, exp: nowSec + 3600 };
}

export function fcmSendUrl(projectId: string): string {
  return 'https://fcm.googleapis.com/v1/projects/' + encodeURIComponent(projectId) + '/messages:send';
}

/**
 * The FCM v1 body for one device. The push expires with the turn: a stale
 * "your turn" is worse than none. Untimed games keep it for a day.
 */
export function yourTurnMessage(token: string, matchId: string, stepSeconds: number, nowMs: number): object {
  const ttl = stepSeconds > 0 ? stepSeconds : 86400;
  return {
    message: {
      token,
      notification: { title: 'Your move', body: "It's your turn in Big Business." },
      data: { type: 'your_turn', matchId },
      android: { priority: 'high', ttl: ttl + 's', collapse_key: 'your_turn' },
      apns: {
        headers: { 'apns-priority': '10', 'apns-expiration': String(Math.floor(nowMs / 1000) + ttl), 'apns-collapse-id': 'your_turn' },
      },
    },
  };
}

/** FCM answers that mean the token is dead and should be forgotten. */
export function isDeadToken(code: number, body: string): boolean {
  if (code === 404) return true;
  return code === 400 && /UNREGISTERED|registration token is not a valid/i.test(body);
}
