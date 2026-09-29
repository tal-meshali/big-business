import { describe, expect, it } from 'vitest';
import { applyForfeit, applyGameResult, claimDaily, emptyProgress, levelForXp, seasonPointsForGame, xpForGame, xpForLevel } from './progression';

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
  it('reward placement and wins, halved against bots only', () => {
    expect(xpForGame(1, 5, 3)).toBe(20 + 40 + 30);
    expect(xpForGame(5, 5, 3)).toBe(20);
    expect(xpForGame(1, 3, 1)).toBe(Math.round((20 + 20 + 30) / 2));
    expect(seasonPointsForGame(1, 5, 3)).toBe(12 + 5);
    expect(seasonPointsForGame(1, 3, 1)).toBe(0);
  });

  it('count a forfeit as a game played with nothing earned', () => {
    const before = applyGameResult(emptyProgress(), 1, 4, 4);
    const after = applyForfeit(before);
    expect(after.gamesPlayed).toBe(2);
    expect(after.xp).toBe(before.xp);
    expect(after.level).toBe(before.level);
    expect(after.wins).toBe(1);
    expect(after.bestRank).toBe(1);
  });

  it('accumulate into progress', () => {
    let p = emptyProgress();
    p = applyGameResult(p, 2, 4, 4);
    expect(p.gamesPlayed).toBe(1);
    expect(p.wins).toBe(0);
    expect(p.bestRank).toBe(2);
    p = applyGameResult(p, 1, 4, 4);
    expect(p.wins).toBe(1);
    expect(p.bestRank).toBe(1);
    expect(p.xp).toBe(40 + 80);
    expect(p.level).toBe(levelForXp(120));
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
