import { describe, expect, it } from 'vitest';
import { DEFAULT_PARAMS } from './protocol';
import { rpcFriendsPlaying, rpcWatchFriend } from './rpc_watch';
import type { MatchState } from './state';
import { ALICE, BOB, call, fakeNk, userCtx } from './test_support';
import { answerSignal, MAX_WATCHERS, mayWatch, PLAYING_MAX_MS, readPlaying, recordPlaying, WATCH_PASS_MS } from './watch';

const CAROL = '2f8fad5b-d9cb-469f-a165-70867728950e';
const NOW = 1_800_000_000_000;

function playingState(tutorial = false): MatchState {
  return {
    params: { ...DEFAULT_PARAMS, tutorial },
    presences: { [ALICE]: { userId: ALICE } as nkruntime.Presence },
    pendingJoins: {},
    lobby: [],
    seatByUser: { [ALICE]: 0 },
    game: { phase: 'take' } as unknown as MatchState['game'],
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

const ask = (s: MatchState, watch: string, friend: string, now = NOW) => JSON.parse(answerSignal(s, JSON.stringify({ watch, friend }), now));

describe('watch passes', () => {
  it('a running game lets a watcher in for a short while', () => {
    const s = playingState();
    expect(ask(s, BOB, ALICE)).toEqual({ ok: true });
    expect(mayWatch(s, BOB, NOW + 1000)).toBe(true);
    expect(mayWatch(s, BOB, NOW + WATCH_PASS_MS)).toBe(false);
    expect(mayWatch(s, CAROL, NOW)).toBe(false);
    s.presences[BOB] = { userId: BOB } as nkruntime.Presence;
    expect(mayWatch(s, BOB, NOW + WATCH_PASS_MS)).toBe(true);
  });

  it('refuses the tutorial, a finished game, a friend without a seat, and a full gallery', () => {
    expect(ask(playingState(true), BOB, ALICE).error).toBe('not playing');
    const ended = playingState();
    (ended.game as { phase: string }).phase = 'ended';
    expect(ask(ended, BOB, ALICE).error).toBe('not playing');
    expect(ask(playingState(), BOB, CAROL).error).toBe('not playing');
    expect(ask(playingState(), ALICE, ALICE).error).toBe('you are playing');
    const full = playingState();
    for (let i = 0; i < MAX_WATCHERS; i++) {
      full.watchers['w' + i] = NOW;
      full.presences['w' + i] = { userId: 'w' + i } as nkruntime.Presence;
    }
    expect(ask(full, BOB, ALICE).error).toBe('too many watching');
    expect(JSON.parse(answerSignal(full, 'nonsense', NOW)).error).toBe('unknown signal');
  });
});

describe('watch RPCs', () => {
  function watchNk(signal: string) {
    const { nk } = fakeNk();
    Object.assign(nk, {
      friendsList: (userId: string, _l: number, state: number) => ({
        friends: state === 0 && (userId === ALICE || userId === BOB) ? [{ user: { userId: userId === ALICE ? BOB : ALICE }, state: 0 }] : [],
        cursor: '',
      }),
      matchGet: (id: string) => (id === 'm1' ? { matchId: 'm1' } : null),
      matchSignal: () => signal,
    });
    return nk;
  }

  it('lists friends in a running game and lets a friend watch', () => {
    const nk = watchNk('{"ok":true}');
    const log = { warn: () => {} } as unknown as nkruntime.Logger;
    recordPlaying(nk, log, 'm1', [ALICE], Date.now());
    expect(call(rpcFriendsPlaying, userCtx(BOB), nk, {}).playing).toEqual([ALICE]);
    expect(call(rpcWatchFriend, userCtx(BOB), nk, { userId: ALICE })).toEqual({ matchId: 'm1' });
    expect(() => call(rpcWatchFriend, userCtx(CAROL), nk, { userId: ALICE })).toThrow('not friends');
    recordPlaying(nk, log, 'm2', [ALICE], Date.now());
    expect(call(rpcFriendsPlaying, userCtx(BOB), nk, {}).playing).toEqual([]);
    expect(() => call(rpcWatchFriend, userCtx(BOB), nk, { userId: ALICE })).toThrow('not playing');
  });

  it("passes on the match's refusal; old rows are ignored", () => {
    const nk = watchNk('{"error":"too many watching"}');
    recordPlaying(nk, { warn: () => {} } as unknown as nkruntime.Logger, 'm1', [ALICE], Date.now());
    expect(() => call(rpcWatchFriend, userCtx(BOB), nk, { userId: ALICE })).toThrow('too many watching');
    expect(readPlaying(nk, [ALICE], Date.now() + PLAYING_MAX_MS)).toEqual({});
  });
});
