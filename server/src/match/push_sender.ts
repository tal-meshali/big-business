/**
 * Sends "your turn" pushes: device tokens from storage, an OAuth access
 * token for FCM (cached in storage for its hour), and one HTTP call per
 * device. push.ts holds the pure parts.
 */
import { SYSTEM_USER } from './protocol';
import {
  fcmConfig,
  fcmSendUrl,
  isDeadToken,
  normalizeTokens,
  OAUTH_TOKEN_URL,
  oauthClaims,
  PUSH_COLLECTION,
  PUSH_OAUTH_KEY,
  PUSH_TOKENS_KEY,
  removeToken,
  yourTurnMessage,
  type DeviceToken,
  type FcmConfig,
} from './push';

/**
 * WHY short: pushes are sent from the match loop, and nk.httpRequest blocks
 * that match's tick until it returns. Two seconds bounds the stall; a match
 * gives up on pushes after a few failures (PUSH_MAX_FAILURES).
 */
const HTTP_TIMEOUT_MS = 2000;
/** Refresh the access token this long before Google says it expires. */
const OAUTH_MARGIN_MS = 120_000;

export function readTokens(nk: nkruntime.Nakama, userId: string): DeviceToken[] {
  const row = nk.storageRead([{ collection: PUSH_COLLECTION, key: PUSH_TOKENS_KEY, userId }])[0];
  if (!row || row.permissionWrite !== 0) return [];
  return normalizeTokens(row.value);
}

export function writeTokens(nk: nkruntime.Nakama, userId: string, tokens: DeviceToken[]): void {
  nk.storageWrite([{ collection: PUSH_COLLECTION, key: PUSH_TOKENS_KEY, userId, value: { tokens }, permissionRead: 0, permissionWrite: 0 }]);
}

function accessToken(nk: nkruntime.Nakama, cfg: FcmConfig, nowMs: number, fresh: boolean): string {
  if (!fresh) {
    const row = nk.storageRead([{ collection: PUSH_COLLECTION, key: PUSH_OAUTH_KEY, userId: SYSTEM_USER }])[0];
    const v = row ? (row.value as { token?: unknown; expiresAt?: unknown; email?: unknown }) : null;
    if (v && typeof v.token === 'string' && typeof v.expiresAt === 'number' && v.email === cfg.clientEmail && v.expiresAt - OAUTH_MARGIN_MS > nowMs) {
      return v.token;
    }
  }
  const assertion = nk.jwtGenerate('RS256', cfg.privateKey, oauthClaims(cfg.clientEmail, Math.floor(nowMs / 1000)));
  const body = 'grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') + '&assertion=' + encodeURIComponent(assertion);
  const res = nk.httpRequest(OAUTH_TOKEN_URL, 'post', { 'Content-Type': 'application/x-www-form-urlencoded' }, body, HTTP_TIMEOUT_MS);
  if (res.code !== 200) throw new Error('fcm oauth answered ' + res.code);
  const parsed = JSON.parse(res.body) as { access_token?: unknown; expires_in?: unknown };
  if (typeof parsed.access_token !== 'string') throw new Error('fcm oauth: no access_token');
  const expiresAt = nowMs + (typeof parsed.expires_in === 'number' ? parsed.expires_in : 3600) * 1000;
  nk.storageWrite([
    { collection: PUSH_COLLECTION, key: PUSH_OAUTH_KEY, userId: SYSTEM_USER, value: { token: parsed.access_token, expiresAt, email: cfg.clientEmail }, permissionRead: 0, permissionWrite: 0 },
  ]);
  return parsed.access_token;
}

export type SendOutcome = 'sent' | 'no-tokens' | 'unconfigured' | 'failed';

/**
 * Sends "your turn" to every device of `userId`. Dead tokens are removed;
 * a 401 retries once with a fresh access token. Never throws.
 */
export function sendYourTurn(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  env: { [key: string]: string } | undefined,
  userId: string,
  matchId: string,
  stepSeconds: number,
): SendOutcome {
  const cfg = fcmConfig(env);
  if (!cfg) return 'unconfigured';
  try {
    let tokens = readTokens(nk, userId);
    if (tokens.length === 0) return 'no-tokens';
    const now = Date.now();
    let bearer = accessToken(nk, cfg, now, false);
    let sent = 0;
    let dead = false;
    for (const t of tokens) {
      const body = JSON.stringify(yourTurnMessage(t.token, matchId, stepSeconds, now));
      const send = (): nkruntime.HttpResponse =>
        nk.httpRequest(fcmSendUrl(cfg.projectId), 'post', { Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' }, body, HTTP_TIMEOUT_MS);
      let res = send();
      if (res.code === 401) {
        bearer = accessToken(nk, cfg, now, true);
        res = send();
      }
      if (res.code === 200) sent++;
      else if (isDeadToken(res.code, res.body)) {
        tokens = removeToken(tokens, t.token);
        dead = true;
      } else logger.warn('fcm send for %s answered %d', userId, res.code);
    }
    if (dead) writeTokens(nk, userId, tokens);
    return sent > 0 ? 'sent' : dead ? 'no-tokens' : 'failed';
  } catch (e) {
    logger.warn('push to %s failed: %s', userId, String(e));
    return 'failed';
  }
}
