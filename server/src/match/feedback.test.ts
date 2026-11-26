import { describe, expect, it } from 'vitest';
import {
  cleanFeedbackText,
  FEEDBACK_COLLECTION,
  FEEDBACK_PER_DAY,
  FEEDBACK_TEXT_MAX,
  feedbackKey,
  feedbackKeyTime,
  readDevice,
  rpcFeedbackDone,
  rpcFeedbackList,
  rpcSendFeedback,
} from './feedback';
import { SERVER_COLLECTIONS } from './reports';
import { RATE_COLLECTION } from './ratelimit';
import { ALICE, BOB, call, fakeNk, serverCtx, userCtx } from './test_support';

const named = (userId: string, username: string) => ({ ...(userCtx(userId) as object), username }) as unknown as nkruntime.Context;

describe('cleanFeedbackText', () => {
  it('keeps line breaks but drops control and direction characters', () => {
    expect(cleanFeedbackText('  hi\r\nthere\u0007‮  ')).toBe('hi\nthere');
  });

  it('allows at most one empty line in a row', () => {
    expect(cleanFeedbackText('a\n\n\n\n\nb')).toBe('a\n\nb');
  });

  it('keeps non-Latin text and emoji', () => {
    expect(cleanFeedbackText('שלום 👋')).toBe('שלום 👋');
  });
});

describe('readDevice', () => {
  it('keeps only known short fields', () => {
    const d = readDevice({ device: { app: '0.1.0', os: 'iOS 18', secret: 'x', model: 'm'.repeat(200) } });
    expect(d).toEqual({ app: '0.1.0', os: 'iOS 18', model: 'm'.repeat(64) });
  });

  it('is null when absent, empty or not an object', () => {
    expect(readDevice({})).toBeNull();
    expect(readDevice({ device: {} })).toBeNull();
    expect(readDevice({ device: ['a'] })).toBeNull();
    expect(readDevice({ device: 'iOS' })).toBeNull();
  });
});

describe('feedbackKey', () => {
  it('sorts newer messages first and gives the time back', () => {
    const older = feedbackKey(1_700_000_000_000, ALICE);
    const newer = feedbackKey(1_800_000_000_000, ALICE);
    expect(newer < older).toBe(true);
    expect(feedbackKeyTime(newer)).toBe(1_800_000_000_000);
    expect(older).toMatch(/^\d{13}-/);
  });
});

describe('send_feedback', () => {
  it('stores a server-only row with the name, category, text and device', () => {
    const { nk, rows } = fakeNk();
    expect(call(rpcSendFeedback, named(ALICE, 'Tal'), nk, { category: 'bug', text: 'Cards froze', device: { app: '0.1.0', where: 'table' } })).toEqual({ ok: true });
    const stored = [...rows.values()].filter((r) => r.collection === FEEDBACK_COLLECTION);
    expect(stored).toHaveLength(1);
    expect(stored[0]!.permissionRead).toBe(0);
    expect(stored[0]!.permissionWrite).toBe(0);
    expect(stored[0]!.value).toMatchObject({ userId: ALICE, name: 'Tal', category: 'bug', text: 'Cards froze', device: { app: '0.1.0', where: 'table' } });
  });

  it('files unknown categories as other and keeps no device when none is sent', () => {
    const { nk, rows } = fakeNk();
    call(rpcSendFeedback, userCtx(ALICE), nk, { category: 'rant', text: 'Love it' });
    const row = [...rows.values()].find((r) => r.collection === FEEDBACK_COLLECTION)!;
    expect(row.value).toMatchObject({ category: 'other', device: null });
  });

  it('refuses empty, too short and too long text with a sentence', () => {
    const { nk } = fakeNk();
    expect(() => call(rpcSendFeedback, userCtx(ALICE), nk, { category: 'idea' })).toThrow('Write a few words first.');
    expect(() => call(rpcSendFeedback, userCtx(ALICE), nk, { category: 'idea', text: ' \n a ' })).toThrow('Write a few words first.');
    expect(() => call(rpcSendFeedback, userCtx(ALICE), nk, { category: 'idea', text: 'x'.repeat(FEEDBACK_TEXT_MAX + 1) })).toThrow('under');
  });

  it('refuses callers without a session', () => {
    const { nk } = fakeNk();
    expect(() => call(rpcSendFeedback, serverCtx, nk, { text: 'hello' })).toThrow('unauthenticated');
  });

  it('limits messages per minute', () => {
    const { nk } = fakeNk();
    for (let i = 0; i < 3; i++) call(rpcSendFeedback, userCtx(ALICE), nk, { text: `message ${i}` });
    expect(() => call(rpcSendFeedback, userCtx(ALICE), nk, { text: 'one more' })).toThrow('too many requests');
    // Another player is not affected.
    expect(call(rpcSendFeedback, userCtx(BOB), nk, { text: 'hello' })).toEqual({ ok: true });
  });

  it('limits messages per day', () => {
    const { nk, rows } = fakeNk();
    rows.set(`${RATE_COLLECTION}/send_feedback_day/${ALICE}`, {
      collection: RATE_COLLECTION, key: 'send_feedback_day', userId: ALICE, value: { start: Date.now() - 1000, count: FEEDBACK_PER_DAY },
      version: 'v1', permissionRead: 0, permissionWrite: 0, createTime: 0, updateTime: 0,
    } as nkruntime.StorageObject);
    expect(() => call(rpcSendFeedback, userCtx(ALICE), nk, { text: 'hello there' })).toThrow('daily limit');
  });

  it('is a collection clients can never write', () => {
    expect(SERVER_COLLECTIONS).toContain(FEEDBACK_COLLECTION);
  });
});

describe('feedback_list and feedback_done', () => {
  it('are refused to players', () => {
    const { nk } = fakeNk();
    expect(() => call(rpcFeedbackList, userCtx(ALICE), nk, {})).toThrow('forbidden');
    expect(() => call(rpcFeedbackDone, userCtx(ALICE), nk, { key: 'x' })).toThrow('forbidden');
  });

  it('lists messages with their keys and deletes handled ones', () => {
    const { nk } = fakeNk();
    call(rpcSendFeedback, userCtx(ALICE), nk, { category: 'idea', text: 'More bots' });
    const listed = call(rpcFeedbackList, serverCtx, nk, { limit: 10 });
    expect(listed.items).toHaveLength(1);
    expect(listed.items[0]).toMatchObject({ category: 'idea', text: 'More bots', userId: ALICE });
    expect(call(rpcFeedbackDone, serverCtx, nk, { key: listed.items[0].key })).toEqual({ deleted: 1 });
    expect(call(rpcFeedbackList, serverCtx, nk, {}).items).toHaveLength(0);
  });

  it('refuses keys that are not feedback keys', () => {
    const { nk } = fakeNk();
    expect(call(rpcFeedbackDone, serverCtx, nk, { key: '../profile' })).toEqual({ deleted: 0, error: 'invalid key' });
  });
});
