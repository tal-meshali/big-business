import { describe, expect, it } from 'vitest';
import { matchInit, soloSeats } from './handler';
import { rpcQuickPlay } from './rooms';
import { ALICE, call, fakeNk, logger, userCtx } from './test_support';

/** quick_play with {"bots": true}: the params it hands to matchCreate. */
function botGameParams(body: Record<string, unknown>): { [k: string]: unknown } {
  const { nk } = fakeNk();
  let created: { [k: string]: unknown } = {};
  (nk as unknown as { matchCreate: unknown }).matchCreate = (_module: string, params: { [k: string]: unknown }) => {
    created = params;
    return 'match-1';
  };
  expect(call(rpcQuickPlay, userCtx(ALICE), nk, body)).toEqual({ matchId: 'match-1', bots: true });
  return created;
}

function initSeats(params: { [k: string]: unknown }): { minSeats: number; maxSeats: number } {
  const { nk } = fakeNk();
  const r = matchInit({} as nkruntime.Context, logger, nk, params);
  return { minSeats: r.state.params.minSeats, maxSeats: r.state.params.maxSeats };
}

describe('bot game size', () => {
  it('seats the player with the chosen number of bots', () => {
    for (const bots of [2, 3, 4]) {
      const params = botGameParams({ bots: true, botCount: bots });
      expect(params).toMatchObject({ solo: true, hostId: ALICE, minSeats: bots + 1 });
      expect(initSeats(params)).toEqual({ minSeats: bots + 1, maxSeats: 1 });
    }
  });

  it('gives an older client that sends no count two bots', () => {
    const params = botGameParams({ bots: true });
    expect(params.minSeats).toBe(3);
    // A match created by an older server (no minSeats) also gets two.
    expect(initSeats({ solo: true, hostId: ALICE })).toEqual({ minSeats: 3, maxSeats: 1 });
  });

  it('keeps the count between 2 and 4 bots', () => {
    expect(botGameParams({ bots: true, botCount: 1 }).minSeats).toBe(3);
    expect(botGameParams({ bots: true, botCount: 9 }).minSeats).toBe(5);
    expect(botGameParams({ bots: true, botCount: 'four' }).minSeats).toBe(3);
    expect(soloSeats(0)).toBe(3);
    expect(soloSeats(99)).toBe(5);
    expect(soloSeats('4')).toBe(4);
    expect(soloSeats(undefined)).toBe(3);
  });

  it('leaves the tutorial at two bots', () => {
    expect(initSeats({ tutorial: true, solo: true, minSeats: 5 })).toEqual({ minSeats: 3, maxSeats: 1 });
  });
});
