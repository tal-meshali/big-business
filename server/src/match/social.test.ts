import { describe, expect, it } from 'vitest';
import { FRIEND_STATE_BLOCKED, FRIEND_STATE_INVITE_SENT, FRIEND_STATE_MUTUAL, inviteError, normalizeCode, type InviteCheck } from './social';

function check(over: Partial<InviteCheck> = {}): InviteCheck {
  return {
    callerId: 'a',
    targetId: 'b',
    code: 'ABC234',
    callerFriends: { b: FRIEND_STATE_MUTUAL },
    targetFriends: {},
    roomExists: true,
    ...over,
  };
}

describe('normalizeCode', () => {
  it('upper-cases, trims and rejects wrong lengths', () => {
    expect(normalizeCode(' abc234 ')).toBe('ABC234');
    expect(normalizeCode('abc')).toBe('');
    expect(normalizeCode(undefined)).toBe('');
  });
});

describe('inviteError', () => {
  it('allows a mutual friend into an existing room', () => {
    expect(inviteError(check())).toBeNull();
  });

  it('refuses self, missing users and bad codes', () => {
    expect(inviteError(check({ targetId: 'a' }))).toBe('invalid user');
    expect(inviteError(check({ targetId: '' }))).toBe('invalid user');
    expect(inviteError(check({ code: '' }))).toBe('invalid code');
  });

  it('refuses strangers and pending friend requests', () => {
    expect(inviteError(check({ callerFriends: {} }))).toBe('not friends');
    expect(inviteError(check({ callerFriends: { b: FRIEND_STATE_INVITE_SENT } }))).toBe('not friends');
  });

  it('refuses when the target has blocked the caller', () => {
    expect(inviteError(check({ targetFriends: { a: FRIEND_STATE_BLOCKED } }))).toBe('not friends');
  });

  it('refuses unknown rooms', () => {
    expect(inviteError(check({ roomExists: false }))).toBe('room not found');
  });
});
