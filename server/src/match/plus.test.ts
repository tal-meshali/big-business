import { describe, expect, it } from 'vitest';
import type { DividendResult } from '../engine';
import { availableCosmetics, dropUnavailable, plusCosmetics } from './cosmetics';
import { deckSlotsFor } from './designer';
import { rpcGetStats, recordStats } from './rpc_stats';
import { applyGame, emptyStats, normalizeStats, statsView } from './stats';
import { activeOwned, entitlementsFromSubscriber, normalizeOwned, PURCHASE_COLLECTION, PURCHASE_KEY } from './store';
import { ALICE, call, fakeNk, userCtx } from './test_support';

const OCT = Date.parse('2026-10-15T12:00:00Z');

function grant(nk: nkruntime.Nakama, userId: string, owned: string[], expires: { [id: string]: number } = {}) {
  nk.storageWrite([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId, value: { owned, syncedAt: 1, expires }, permissionRead: 1, permissionWrite: 0 }]);
}

const FUTURE = Date.now() + 30 * 86_400_000;

describe('Plus entitlement', () => {
  it('keeps the subscription expiry and drops it once passed', () => {
    const body = { subscriber: { entitlements: { plus: { expires_date: '2026-11-15T12:00:00Z' }, designer: { expires_date: null } } } };
    const ents = entitlementsFromSubscriber(body, OCT);
    expect(ents).toEqual({ owned: ['designer', 'plus'], expires: { plus: Date.parse('2026-11-15T12:00:00Z') } });
    const row = normalizeOwned({ ...ents, syncedAt: OCT });
    expect(activeOwned(row, OCT)).toEqual(['designer', 'plus']);
    expect(activeOwned(row, Date.parse('2026-11-16T00:00:00Z'))).toEqual(['designer']);
  });

  it('gives ten deck slots, Designer three', () => {
    expect(deckSlotsFor(false, false)).toBe(0);
    expect(deckSlotsFor(true, false)).toBe(3);
    expect(deckSlotsFor(true, true)).toBe(10);
  });

  it('opens each month\'s Plus skin from its month, only while Plus is active', () => {
    expect(plusCosmetics(OCT)).toEqual(['back_ticker']);
    expect(plusCosmetics(Date.parse('2026-11-01T00:00:00Z'))).toEqual(['back_ticker', 'table_slate']);
    expect(availableCosmetics(0, ['plus'], OCT)).toContain('back_ticker');
    expect(availableCosmetics(0, [], OCT)).not.toContain('back_ticker');
    const lapsed = dropUnavailable({ cardBack: 'back_ticker', table: 'table_green' }, availableCosmetics(0, [], OCT));
    expect(lapsed.cardBack).toBe('back_classic');
  });
});

describe('stats', () => {
  const result: DividendResult = {
    companies: [{ company: 2, majority: 0, payments: [] }, { company: 5, majority: 1, payments: [] }, { company: 4, majority: 0, payments: [] }],
    scores: [{ seat: 0, bronze: 9, gold: 2, score: 15, rank: 1 }, { seat: 1, bronze: 8, gold: 0, score: 8, rank: 2 }],
  };

  it('adds a game, majorities by company and the recent form', () => {
    const one = applyGame(emptyStats(), result, 0, 3, 2, OCT)!;
    expect(one).toMatchObject({ games: 1, wins: 1, podiums: 1, totalScore: 15, bestScore: 15, peopleGames: 1, majorities: [0, 0, 1, 0, 1, 0] });
    const two = applyGame(one, { ...result, scores: [{ seat: 0, bronze: 3, gold: 0, score: 3, rank: 4 }] }, 0, 5, 1, OCT + 1)!;
    expect(two).toMatchObject({ games: 2, wins: 1, podiums: 1, bestScore: 15, peopleGames: 1 });
    expect(two.recent.map((g) => g.rank)).toEqual([4, 1]);
    expect(applyGame(one, result, 6, 3, 2, OCT)).toBeNull();
  });

  it('shows the breakdown to Plus only and cleans stored junk', () => {
    const row = applyGame(emptyStats(), result, 0, 3, 2, OCT)!;
    expect(statsView(row, false)).toEqual({ plus: false, games: 1, wins: 1 });
    expect(statsView(row, true)).toMatchObject({ plus: true, averageScore: 15, winRate: 100, majorities: [0, 0, 1, 0, 1, 0] });
    expect(normalizeStats({ games: -2, majorities: [1, 'x'], recent: [{ rank: 0 }, { rank: 2, score: 5 }] })).toMatchObject({ games: 0, majorities: [1, 0, 0, 0, 0, 0], recent: [{ rank: 2, score: 5 }] });
  });

  it('records games server-side and serves them through get_stats', () => {
    const { nk } = fakeNk();
    recordStats(nk, ALICE, result, 0, 3, 2, OCT);
    recordStats(nk, ALICE, result, 0, 3, 2, OCT + 1);
    expect(call(rpcGetStats, userCtx(ALICE), nk, {})).toEqual({ plus: false, games: 2, wins: 2 });
    grant(nk, ALICE, ['plus'], { plus: FUTURE });
    expect(call(rpcGetStats, userCtx(ALICE), nk, {})).toMatchObject({ plus: true, games: 2, bestScore: 15 });
  });
});

