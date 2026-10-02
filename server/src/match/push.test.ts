import { describe, expect, it } from 'vitest';
import { addToken, fcmConfig, isDeadToken, isPushToken, MAX_TOKENS, normalizeTokens, oauthClaims, removeToken, shouldPush, yourTurnMessage, type PushCheck } from './push';

const TOKEN = 'dQw4w9WgXcQ:APA91bHPRgkF3JUikC4ENAHEeMrd41Zxv3hVZjC9KtT8';
const NOW = 1_800_000_000_000;

function check(over: Partial<PushCheck>): PushCheck {
  return { human: true, connected: false, forfeited: false, tutorial: false, stepSeconds: 0, lastSentAt: 0, nowMs: NOW, cooldownMs: 600_000, failures: 0, ...over };
}

describe('device tokens', () => {
  it('accepts FCM-shaped tokens only', () => {
    expect(isPushToken(TOKEN)).toBe(true);
    expect(isPushToken('short')).toBe(false);
    expect(isPushToken('bad token with spaces and enough length')).toBe(false);
    expect(isPushToken(42)).toBe(false);
  });

  it('keeps the newest tokens, each once', () => {
    let list = addToken([], TOKEN, 'android', 1);
    list = addToken(list, TOKEN, 'android', 2);
    expect(list).toEqual([{ token: TOKEN, platform: 'android', at: 2 }]);
    for (let i = 0; i < 5; i++) list = addToken(list, TOKEN + i, 'ios', 10 + i);
    expect(list.length).toBe(MAX_TOKENS);
    expect(list[0]?.token).toBe(TOKEN + '4');
    expect(removeToken(list, TOKEN + '4').length).toBe(MAX_TOKENS - 1);
  });

  it('normalises stored rows', () => {
    expect(normalizeTokens({ tokens: [{ token: TOKEN, platform: 'ios', at: 3 }, { token: 'x', platform: 'ios' }, { token: TOKEN, platform: 'web' }] })).toEqual([
      { token: TOKEN, platform: 'ios', at: 3 },
    ]);
    expect(normalizeTokens(null)).toEqual([]);
  });
});

describe('shouldPush', () => {
  it('pushes a person who is away at the start of their turn', () => {
    expect(shouldPush(check({}))).toBe(true);
    expect(shouldPush(check({ stepSeconds: 60 }))).toBe(true);
  });

  it('never pushes a bot, a connected or forfeited player, or the tutorial', () => {
    expect(shouldPush(check({ human: false }))).toBe(false);
    expect(shouldPush(check({ connected: true }))).toBe(false);
    expect(shouldPush(check({ forfeited: true }))).toBe(false);
    expect(shouldPush(check({ tutorial: true }))).toBe(false);
  });

  it('skips fast timers, the cooldown and a failing sender', () => {
    expect(shouldPush(check({ stepSeconds: 10 }))).toBe(false);
    expect(shouldPush(check({ lastSentAt: NOW - 60_000 }))).toBe(false);
    expect(shouldPush(check({ lastSentAt: NOW - 600_000 }))).toBe(true);
    expect(shouldPush(check({ failures: 3 }))).toBe(false);
  });
});

describe('FCM requests', () => {
  it('reads the service account from env and restores key line breaks', () => {
    expect(fcmConfig(undefined)).toBeNull();
    expect(fcmConfig({ FCM_PROJECT_ID: 'p', FCM_CLIENT_EMAIL: '', FCM_PRIVATE_KEY: '' })).toBeNull();
    const cfg = fcmConfig({ FCM_PROJECT_ID: 'bigbiz', FCM_CLIENT_EMAIL: 'svc@bigbiz.iam.gserviceaccount.com', FCM_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----\\n' });
    expect(cfg?.privateKey).toBe('-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----');
  });

  it('asks for the messaging scope for one hour', () => {
    expect(oauthClaims('svc@x', 100)).toEqual({ iss: 'svc@x', scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: 100, exp: 3700 });
  });

  it('expires the push with the turn', () => {
    const m = yourTurnMessage(TOKEN, 'match.node', 60, NOW) as { message: { token: string; data: { [k: string]: string }; android: { ttl: string }; apns: { headers: { [k: string]: string } } } };
    expect(m.message.token).toBe(TOKEN);
    expect(m.message.data).toEqual({ type: 'your_turn', matchId: 'match.node' });
    expect(m.message.android.ttl).toBe('60s');
    expect(m.message.apns.headers['apns-expiration']).toBe(String(NOW / 1000 + 60));
    const untimed = yourTurnMessage(TOKEN, 'm', 0, NOW) as { message: { android: { ttl: string } } };
    expect(untimed.message.android.ttl).toBe('86400s');
  });

  it('recognises dead tokens', () => {
    expect(isDeadToken(404, '')).toBe(true);
    expect(isDeadToken(400, '{"error":{"details":[{"errorCode":"UNREGISTERED"}]}}')).toBe(true);
    expect(isDeadToken(400, '{"error":{"message":"bad json"}}')).toBe(false);
    expect(isDeadToken(500, 'UNREGISTERED')).toBe(false);
  });
});
