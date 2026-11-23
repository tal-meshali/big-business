import { describe, expect, it } from 'vitest';
import { settleGame, type SeatResult } from './awards';
import { DEFAULT_XP_RATES, emptyProgress, levelForXp, xpForLevel, type Progress } from './progression';
import { dailyQuests, questView, type GameStats } from './quests';

const t0 = Date.UTC(2026, 8, 28, 12); // Monday 2026-09-28

function stats(over: Partial<GameStats> = {}): GameStats {
  return { games: 1, wins: 0, marketTakes: 0, marketCoins: 0, tokensEnd: 0, goldEnd: 0, majorities: 0, withPeople: 1, humans: 3, rank: 2, ...over };
}

function seat(over: Partial<SeatResult> = {}): SeatResult {
  return { rank: 1, seats: 4, capital: 21, humans: 3, ...over };
}

describe('the earnings receipt', () => {
  it('pays capital times the rate plus the finishing XP, and says so line by line', () => {
    const { progress, earnings } = settleGame(emptyProgress(), seat(), null, DEFAULT_XP_RATES, t0);
    expect(earnings.lines).toEqual([
      { kind: 'capital', xp: 42 },
      { kind: 'finish', xp: 20 },
    ]);
    expect([earnings.capital, earnings.rate, earnings.botsOnly]).toEqual([21, 2, false]);
    expect(earnings.xp).toBe(62);
    expect([earnings.xpBefore, earnings.xpAfter]).toEqual([0, 62]);
    expect([earnings.levelBefore, earnings.levelAfter]).toEqual([1, 2]);
    expect(progress.xp).toBe(62);
    expect(progress.trackXp).toBe(62);
    expect([progress.gamesPlayed, progress.wins, progress.bestRank]).toEqual([1, 1, 1]);
    // Beat three players and won: 3 x 3 + 5.
    expect(earnings.seasonPoints).toBe(14);
  });

  it('adds up: the lines sum to the XP gained, whatever happens', () => {
    for (const capital of [0, 1, 7, 15, 30, 44]) {
      for (const humans of [1, 2, 5]) {
        const before = { ...emptyProgress(), xp: 690, level: levelForXp(690), trackXp: 300 };
        const { progress, earnings } = settleGame(before, seat({ capital, humans, rank: 2 }), stats({ wins: 1, marketTakes: 9, marketCoins: 9, tokensEnd: 2, goldEnd: 9, majorities: 3 }), DEFAULT_XP_RATES, t0);
        const sum = earnings.lines.reduce((n, l) => n + l.xp, 0);
        expect(sum).toBe(earnings.xp);
        expect(progress.xp - before.xp).toBe(earnings.xp);
        expect(progress.trackXp - before.trackXp).toBe(earnings.xp);
        expect(earnings.xpAfter).toBe(progress.xp);
        expect(earnings.levelAfter).toBe(progress.level);
      }
    }
  });

  it('pays half against only bots and earns no season points', () => {
    const { earnings } = settleGame(emptyProgress(), seat({ humans: 1 }), null, DEFAULT_XP_RATES, t0);
    expect(earnings.botsOnly).toBe(true);
    expect(earnings.rate).toBe(1);
    expect(earnings.lines).toEqual([
      { kind: 'capital', xp: 21 },
      { kind: 'finish', xp: 10 },
    ]);
    expect(earnings.seasonPoints).toBe(0);
  });

  it('collects the quests this game finished and lists them after the game lines', () => {
    const today = dailyQuests('2026-09-28');
    const big = stats({ wins: 1, marketTakes: 20, marketCoins: 30, tokensEnd: 3, goldEnd: 9, majorities: 3, rank: 1 });
    const { progress, earnings } = settleGame(emptyProgress(), seat(), big, DEFAULT_XP_RATES, t0);
    const questLines = earnings.lines.filter((l) => l.kind === 'quest');
    expect(questLines.length).toBeGreaterThan(0);
    expect(earnings.lines.slice(0, 2).map((l) => l.kind)).toEqual(['capital', 'finish']);
    for (const line of questLines) expect(typeof line.text).toBe('string');
    // Each finished daily is on the receipt with its own XP, and is now marked collected.
    const view = questView(progress.quests, t0);
    for (const row of view.daily) {
      const def = today.find((d) => d.id === row.id)!;
      if (row.claimed) expect(questLines.some((l) => l.text === def.text && l.xp === def.xp)).toBe(true);
      expect(row.claimable).toBe(false);
    }
    // Nothing left to collect when the next game ends.
    const second = settleGame(progress, seat(), stats(), DEFAULT_XP_RATES, t0 + 60_000);
    expect(second.earnings.lines.filter((l) => l.kind === 'quest').map((l) => l.text)).not.toContain(questLines[0]!.text);
  });

  it('gives no quest credit without game stats (tutorial, or a seat a bot finished)', () => {
    const { progress, earnings } = settleGame(emptyProgress(), seat(), null, DEFAULT_XP_RATES, t0);
    expect(earnings.quests).toEqual([]);
    expect(progress.quests.day).toBe('');
  });

  it('shows at most two open quests, each unfinished', () => {
    const { earnings } = settleGame(emptyProgress(), seat({ rank: 3 }), stats({ marketTakes: 1 }), DEFAULT_XP_RATES, t0);
    expect(earnings.quests.length).toBeLessThanOrEqual(2);
    for (const q of earnings.quests) expect(q.progress).toBeLessThan(q.target);
  });

  it('reports a level-up and a track cosmetic the game unlocked', () => {
    const before: Progress = { ...emptyProgress(), xp: xpForLevel(5) - 10, level: 4, trackXp: 350 };
    const { earnings } = settleGame(before, seat(), null, DEFAULT_XP_RATES, t0);
    expect([earnings.levelBefore, earnings.levelAfter]).toEqual([4, 5]);
    expect(earnings.unlocked).toEqual(['back_midnight']);
    const calm = settleGame({ ...before, trackXp: 400 }, seat({ capital: 0 }), null, DEFAULT_XP_RATES, t0);
    expect(calm.earnings.unlocked).toEqual([]);
  });

  it('follows the operator rates', () => {
    const { earnings } = settleGame(emptyProgress(), seat({ capital: 10 }), null, { base: 5, perCoin: 4 }, t0);
    expect(earnings.lines).toEqual([
      { kind: 'capital', xp: 40 },
      { kind: 'finish', xp: 5 },
    ]);
  });
});
