import { describe, expect, it } from 'vitest';
import { DEFAULT_PARAMS } from './protocol';
import { label, lobbyJoinError, mayStartNow, PENDING_JOIN_MS, type MatchState } from './state';

function lobbyState(isPrivate: boolean, maxSeats: number): MatchState {
  return {
    params: { ...DEFAULT_PARAMS, isPrivate, roomCode: isPrivate ? 'ABC234' : undefined, maxSeats },
    presences: {},
    pendingJoins: {},
    lobby: [],
    seatByUser: {},
    game: null,
    playStartsAt: 0,
    forfeited: {},
    lastActivity: 0,
    startsAt: 0,
    endedAt: 0,
    botActAt: 0,
    awarded: false,
    lastEmoteAt: {},
    log: [],
    pushTurnKey: '',
    pushSentAt: {},
    pushFailures: 0,
    customDeck: null,
    watchers: {},
  };
}

describe('lobbyJoinError', () => {
  it('lets a private room be joined only with its code', () => {
    const s = lobbyState(true, 4);
    expect(lobbyJoinError(s, 'u1', undefined, 1000)).toBe('invalid code');
    expect(lobbyJoinError(s, 'u1', 'ZZZ999', 1000)).toBe('invalid code');
    expect(lobbyJoinError(s, 'u1', 'abc234', 1000)).toBeNull();
    expect(lobbyJoinError(lobbyState(false, 4), 'u1', undefined, 1000)).toBeNull();
  });

  it('lets a user already in the lobby come back without the code', () => {
    const s = lobbyState(true, 2);
    s.lobby.push({ userId: 'u1', name: 'A', ready: false }, { userId: 'u2', name: 'B', ready: false });
    expect(lobbyJoinError(s, 'u1', undefined, 1000)).toBeNull();
    expect(lobbyJoinError(s, 'u3', 'ABC234', 1000)).toBe('room full');
  });

  it("counts other users' pending joins until they expire, never the caller's own", () => {
    const s = lobbyState(true, 2);
    s.lobby.push({ userId: 'host', name: 'H', ready: false });
    s.pendingJoins['guest'] = 1000;
    expect(lobbyJoinError(s, 'other', 'ABC234', 2000)).toBe('room full');
    expect(lobbyJoinError(s, 'guest', 'ABC234', 2000)).toBeNull();
    expect(lobbyJoinError(s, 'other', 'ABC234', 1000 + PENDING_JOIN_MS)).toBeNull();
  });

  it('keeps a bot game to the player who asked for it', () => {
    const s = lobbyState(false, 1);
    s.params.solo = true;
    s.params.hostId = 'me';
    expect(lobbyJoinError(s, 'stranger', undefined, 1000)).toBe('solo game');
    expect(lobbyJoinError(s, 'me', undefined, 1000)).toBeNull();
  });
});

describe('mayStartNow', () => {
  it('lets anyone waiting in a public lobby start it, nobody outside it', () => {
    const s = lobbyState(false, 5);
    s.lobby.push({ userId: 'u1', name: 'A', ready: false });
    expect(mayStartNow(s, 'u1')).toBe(true);
    expect(mayStartNow(s, 'u2')).toBe(false);
  });

  it('lets only the host start a private room early', () => {
    const s = lobbyState(true, 5);
    s.params.hostId = 'host';
    s.lobby.push({ userId: 'host', name: 'H', ready: false }, { userId: 'guest', name: 'G', ready: false });
    expect(mayStartNow(s, 'host')).toBe(true);
    expect(mayStartNow(s, 'guest')).toBe(false);
  });
});

describe('label', () => {
  it('never publishes the room code', () => {
    expect(label(lobbyState(true, 4))).not.toContain('ABC234');
  });

  it('keeps bot games out of the public listing', () => {
    const s = lobbyState(false, 1);
    s.params.solo = true;
    expect(JSON.parse(label(s)).mode).toBe('solo');
  });
});
