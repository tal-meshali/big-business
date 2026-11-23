import { describe, expect, it } from 'vitest';
import { addXp, applyForfeit, applyGameResult, claimDaily, emptyProgress, levelForXp, normalizeProgress, seasonPointsForGame, TRACK_XP_PER_POINT, xpForGame, xpForLevel } from './progression';

describe('levels', () => {
  it('start at 1 and grow with the square root of xp', () => {
    expect(levelForXp(0)).toBe(1);
    expect(levelForXp(49)).toBe(1);
    expect(levelForXp(50)).toBe(2);
    expect(levelForXp(200)).toBe(3);
    expect(xpForLevel(3)).toBe(200);
  });
});

describe('game rewards', () => {
  it('pay a fixed part plus a part linear in final capital, halved against bots only', () => {
    expect(xpForGame(21, 3)).toEqual({ finish: 20, capital: 42, rate: 2 });
    expect(xpForGame(0, 3)).toEqual({ finish: 20, capital: 0, rate: 2 });
    expect(xpForGame(21, 1)).toEqual({ finish: 10, capital: 21, rate: 1 });
    // Linear: one more coin is always worth the same.
    expect(xpForGame(31, 4).capital - xpForGame(30, 4).capital).toBe(xpForGame(1, 4).capital);
    expect(seasonPointsForGame(1, 5, 3)).toBe(12 + 5);
    expect(seasonPointsForGame(1, 3, 1)).toBe(0);
  });

  it('follow the operator rates, and never go negative', () => {
    expect(xpForGame(10, 2, { base: 30, perCoin: 3 })).toEqual({ finish: 30, capital: 30, rate: 3 });
    expect(xpForGame(7, 1, { base: 25, perCoin: 3 })).toEqual({ finish: 13, capital: 11, rate: 1.5 });
    expect(xpForGame(-4, 2).capital).toBe(0);
    expect(xpForGame(10, 2, { base: 0, perCoin: 0 })).toEqual({ finish: 0, capital: 0, rate: 0 });
  });

  it('have no win bonus: equal capital pays equal XP whatever the place', () => {
    const first = applyGameResult(emptyProgress(), 1, 15, 4);
    const last = applyGameResult(emptyProgress(), 4, 15, 4);
    expect(first.xp).toBe(last.xp);
    expect(first.wins).toBe(1);
    expect(last.wins).toBe(0);
  });

  it('count a forfeit as a game played with nothing earned', () => {
    const before = applyGameResult(emptyProgress(), 1, 12, 4);
    const after = applyForfeit(before);
    expect(after.gamesPlayed).toBe(2);
    expect(after.xp).toBe(before.xp);
    expect(after.level).toBe(before.level);
    expect(after.wins).toBe(1);
    expect(after.bestRank).toBe(1);
  });

  it('accumulate into progress', () => {
    let p = emptyProgress();
    p = applyGameResult(p, 2, 10, 4);
    expect(p.gamesPlayed).toBe(1);
    expect(p.wins).toBe(0);
    expect(p.bestRank).toBe(2);
    p = applyGameResult(p, 1, 30, 4);
    expect(p.wins).toBe(1);
    expect(p.bestRank).toBe(1);
    expect(p.xp).toBe(40 + 80);
    expect(p.level).toBe(levelForXp(120));
    // Game XP also fills the cosmetic track.
    expect(p.trackXp).toBe(120);
  });
});

describe('one XP number', () => {
  it('adds to the career total and the track together and recomputes the level', () => {
    const p = addXp({ ...emptyProgress(), xp: 40, trackXp: 5 }, 10.9);
    expect([p.xp, p.trackXp, p.level]).toEqual([50, 15, 2]);
    expect(addXp(p, -20)).toEqual(p);
  });

  it('converts stored track points to track XP once, keeping every unlock', () => {
    const old = normalizeProgress({ xp: 100, trackPoints: 70 } as never);
    expect(old.trackXp).toBe(70 * TRACK_XP_PER_POINT);
    expect('trackPoints' in old).toBe(false);
    // A row already in XP is left alone, even if a stale points field is still there.
    expect(normalizeProgress({ trackXp: 500, trackPoints: 70 } as never).trackXp).toBe(500);
    expect(normalizeProgress({ trackXp: 0, trackPoints: 70 } as never).trackXp).toBe(0);
  });
});

describe('daily streak', () => {
  const day = 86_400_000;
  const t0 = Date.UTC(2026, 8, 28, 12);
  it('claims once per UTC day and grows the streak on consecutive days', () => {
    let p = emptyProgress();
    let c = claimDaily(p, t0);
    expect(c.claimed).toBe(true);
    expect(c.progress.streak).toBe(1);
    expect(c.xpAwarded).toBe(15);
    expect(c.progress.trackXp).toBe(15);
    p = c.progress;
    expect(claimDaily(p, t0 + 3600_000).claimed).toBe(false);
    c = claimDaily(p, t0 + day);
    expect(c.progress.streak).toBe(2);
    expect(c.xpAwarded).toBe(20);
    c = claimDaily(c.progress, t0 + 3 * day); // skipped a day
    expect(c.progress.streak).toBe(1);
  });

  it('caps the streak bonus at 7 days', () => {
    let p = emptyProgress();
    for (let i = 0; i < 10; i++) p = claimDaily(p, t0 + i * day).progress;
    expect(p.streak).toBe(10);
    expect(claimDaily(p, t0 + 10 * day).xpAwarded).toBe(10 + 35);
  });
});
