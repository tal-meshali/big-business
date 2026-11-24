import { describe, expect, it } from 'vitest';
import { createGame, applyAction, type GameState } from '../engine';
import { equipCosmetic, nextUnlock, TRACK, unlockedCosmetics } from './cosmetics';
import { emptyProgress, normalizeProgress, type Progress } from './progression';
import {
  applyGameToQuests,
  claimQuest,
  collectQuests,
  DAILY_POOL,
  dailyQuests,
  gameStats,
  openQuests,
  questView,
  rolloverQuests,
  utcWeek,
  WEEKLY_POOL,
  weeklyQuests,
  type GameStats,
  type LogEntry,
  type QuestDef,
} from './quests';

const day = 86_400_000;
const t0 = Date.UTC(2026, 8, 28, 12); // Monday 2026-09-28

function stats(over: Partial<GameStats> = {}): GameStats {
  return { games: 1, wins: 0, marketTakes: 0, marketCoins: 0, tokensEnd: 0, goldEnd: 0, majorities: 0, withPeople: 0, humans: 1, rank: 3, ...over };
}

describe('calendar', () => {
  it('computes ISO weeks in UTC', () => {
    expect(utcWeek(Date.UTC(2026, 8, 28))).toBe('2026-W40');
    expect(utcWeek(Date.UTC(2026, 8, 27, 23, 59))).toBe('2026-W39'); // Sunday before
    expect(utcWeek(Date.UTC(2027, 0, 1))).toBe('2026-W53'); // Jan 1 2027 is a Friday in ISO week 53 of 2026
    expect(utcWeek(Date.UTC(2024, 11, 30))).toBe('2025-W01');
  });
});

describe('quest picks', () => {
  it('are deterministic per day and week, distinct, and from the right pool', () => {
    const a = dailyQuests('2026-09-28');
    const b = dailyQuests('2026-09-28');
    expect(a.map((q) => q.id)).toEqual(b.map((q) => q.id));
    expect(a.length).toBe(3);
    expect(new Set(a.map((q) => q.id)).size).toBe(3);
    for (const q of a) expect(DAILY_POOL.indexOf(q)).toBeGreaterThanOrEqual(0);
    const w = weeklyQuests('2026-W40');
    expect(w.length).toBe(2);
    expect(new Set(w.map((q) => q.id)).size).toBe(2);
    for (const q of w) expect(WEEKLY_POOL.indexOf(q)).toBeGreaterThanOrEqual(0);
  });

  it('vary across days', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 30; i++) seen.add(dailyQuests(new Date(t0 + i * day).toISOString().slice(0, 10)).map((q) => q.id).join(','));
    expect(seen.size).toBeGreaterThan(5);
  });
});

describe('progress and claims', () => {
  it('advances sum and best quests, then pays a claim once', () => {
    let p: Progress = emptyProgress();
    const wide = stats({ wins: 1, marketTakes: 20, marketCoins: 30, tokensEnd: 3, goldEnd: 9, majorities: 3, withPeople: 1, rank: 1 });
    p = { ...p, quests: applyGameToQuests(p.quests, wide, t0) };
    const view = questView(p.quests, t0);
    expect(view.daily.length).toBe(3);
    expect(view.weekly.length).toBe(2);
    // Every daily quest except "play 3 games" completes in one big game.
    for (const row of view.daily) {
      if (row.id === 'd_play_3') expect(row.progress).toBe(1);
      else expect(row.claimable).toBe(true);
    }
    const target = view.daily.find((r) => r.claimable);
    expect(target).toBeDefined();
    const first = claimQuest(p, (target as { id: string }).id, t0);
    expect(first.ok).toBe(true);
    expect(first.progress.xp).toBe((target as { xp: number }).xp);
    expect(first.progress.trackXp).toBe((target as { xp: number }).xp);
    const again = claimQuest(first.progress, (target as { id: string }).id, t0);
    expect(again.ok).toBe(false);
    expect(again.progress.xp).toBe(first.progress.xp);
    expect(questView(first.progress.quests, t0).daily.find((r) => r.id === (target as { id: string }).id)?.claimed).toBe(true);
  });

  it('refuses incomplete and unknown quests', () => {
    let p: Progress = emptyProgress();
    p = { ...p, quests: applyGameToQuests(p.quests, stats(), t0) };
    expect(claimQuest(p, 'd_play_3', t0).ok).toBe(false);
    expect(claimQuest(p, 'nope', t0).ok).toBe(false);
    // A quest from the pool that is not on today's list cannot be claimed either.
    const today = dailyQuests('2026-09-28').map((q) => q.id);
    const absent = DAILY_POOL.find((q) => today.indexOf(q.id) < 0) as { id: string };
    expect(claimQuest(p, absent.id, t0).ok).toBe(false);
  });

  it('caps sum progress at the target', () => {
    let p: Progress = emptyProgress();
    for (let i = 0; i < 5; i++) p = { ...p, quests: applyGameToQuests(p.quests, stats({ marketTakes: 10, marketCoins: 10 }), t0) };
    for (const row of questView(p.quests, t0).daily) expect(row.progress).toBeLessThanOrEqual(row.target);
  });

  it('rolls dailies over at the UTC day and weeklies at the ISO week', () => {
    let p: Progress = emptyProgress();
    p = { ...p, quests: applyGameToQuests(p.quests, stats(), t0) };
    const sameDay = rolloverQuests(p.quests, t0 + 3_600_000);
    expect(sameDay.daily).toEqual(p.quests.daily);
    const nextDay = rolloverQuests(p.quests, t0 + day);
    expect(nextDay.day).toBe('2026-09-29');
    for (const id in nextDay.daily) expect(nextDay.daily[id]?.progress).toBe(0);
    // Still the same ISO week on Tuesday: weekly progress carries.
    expect(nextDay.weekly).toEqual(p.quests.weekly);
    const nextWeek = rolloverQuests(p.quests, t0 + 7 * day);
    expect(nextWeek.week).toBe('2026-W41');
    for (const id in nextWeek.weekly) expect(nextWeek.weekly[id]?.progress).toBe(0);
    // Rows for the new day list the new day's quests.
    const ids = questView(nextDay, t0 + day).daily.map((r) => r.id);
    expect(ids).toEqual(dailyQuests('2026-09-29').map((q) => q.id));
  });
});

describe('game stats', () => {
  it('reads market takes, coins, tokens, majorities and rank from a finished game', () => {
    const seats = [
      { id: 'u1', name: 'A', isBot: false },
      { id: 'u2', name: 'B', isBot: false },
      { id: 'bot:0', name: 'C', isBot: true },
    ];
    let g: GameState = createGame(seats, 7, { stepSeconds: 0 });
    const log: LogEntry[] = [];
    // Play a whole game with a simple policy: draw when free, otherwise take
    // the richest market share; keep everything in the portfolio.
    let guard = 0;
    while (g.phase !== 'ended' && guard++ < 500) {
      const seat = g.active;
      const me = g.seats[seat] as GameState['seats'][number];
      let action: import('../engine').Action;
      if (g.phase === 'take') {
        const takeable = g.market.filter((m) => g.tokens[m.card.company] !== seat).sort((a, b) => b.coins - a.coins);
        const rich = takeable[0];
        if (rich && (rich.coins >= 2 || g.supply.length === 0 || me.bronze === 0)) action = { type: 'take_market', cardId: rich.card.id };
        else if (g.supply.length > 0) action = { type: 'take_supply' };
        else action = { type: 'take_market', cardId: (takeable[0] as { card: { id: number } }).card.id };
      } else {
        const card = me.hand[0] as { id: number; company: number };
        const other = me.hand.find((c) => c.company !== g.tookCompany);
        action = other && me.hand.length > 1 && g.market.length < 3 ? { type: 'play_market', cardId: other.id } : { type: 'play_portfolio', cardId: card.id };
      }
      const r = applyAction(g, seat, action);
      let coins = 0;
      for (const e of r.events) if (e.type === 'took_market') coins = e.coins;
      g = r.state;
      log.push({ seq: g.seq, seat, action, source: 'bot', coins });
    }
    expect(g.phase).toBe('ended');
    const result = g.result as NonNullable<GameState['result']>;
    let totalTakes = 0;
    let totalCoins = 0;
    let totalMajorities = 0;
    let totalTokens = 0;
    let wins = 0;
    for (let seat = 0; seat < 3; seat++) {
      const st = gameStats(g, log, seat);
      expect(st.humans).toBe(2);
      expect(st.withPeople).toBe(1);
      expect(st.goldEnd).toBe(g.seats[seat]?.gold);
      expect(st.rank).toBe(result.scores.find((s) => s.seat === seat)?.rank);
      totalTakes += st.marketTakes;
      totalCoins += st.marketCoins;
      totalMajorities += st.majorities;
      totalTokens += st.tokensEnd;
      wins += st.wins;
    }
    expect(totalTakes).toBe(log.filter((e) => e.action.type === 'take_market').length);
    expect(totalCoins).toBe(log.reduce((n, e) => n + (e.coins || 0), 0));
    expect(totalMajorities).toBe(result.companies.filter((c) => c.majority !== null).length);
    // Tokens stay put on a tie, so they can outnumber strict majorities.
    expect(totalTokens).toBe(g.tokens.filter((t) => t !== null).length);
    expect(wins).toBeGreaterThanOrEqual(1);
    // When the other human forfeited, the caller passes 1: not a game with people.
    const solo = gameStats(g, log, 0, 1);
    expect(solo.humans).toBe(1);
    expect(solo.withPeople).toBe(0);
  });
});

describe('cosmetic track', () => {
  it('unlocks in threshold order and equips only what is unlocked', () => {
    expect(unlockedCosmetics(0)).toEqual(['back_classic', 'table_green']);
    expect(unlockedCosmetics(360)).toContain('back_midnight');
    expect(unlockedCosmetics(839)).not.toContain('table_navy');
    expect(unlockedCosmetics(3600).length).toBe(2 + TRACK.length);
    expect(nextUnlock(0)?.cosmeticId).toBe('back_midnight');
    expect(nextUnlock(3599)?.cosmeticId).toBe('back_pinstripe');
    expect(nextUnlock(3600)).toBeNull();
    const base = { cardBack: 'back_classic', table: 'table_green' };
    expect(equipCosmetic(base, 359, 'cardBack', 'back_midnight').ok).toBe(false);
    const ok = equipCosmetic(base, 360, 'cardBack', 'back_midnight');
    expect(ok.ok).toBe(true);
    expect(ok.equipped).toEqual({ cardBack: 'back_midnight', table: 'table_green' });
    expect(equipCosmetic(base, 360, 'table', 'back_midnight').ok).toBe(false); // wrong slot
    expect(equipCosmetic(base, 360, 'table', 'table_green').ok).toBe(true);
  });

  it('claims feed the track through progress', () => {
    let p: Progress = emptyProgress();
    for (let i = 0; i < 12 && p.trackXp < 360; i++) {
      const now = t0 + i * day;
      p = { ...p, quests: applyGameToQuests(p.quests, stats({ wins: 1, marketTakes: 9, marketCoins: 9, tokensEnd: 2, goldEnd: 9, majorities: 3, withPeople: 1, rank: 1 }), now) };
      p = { ...p, quests: applyGameToQuests(p.quests, stats({ games: 1 }), now) };
      p = { ...p, quests: applyGameToQuests(p.quests, stats({ games: 1 }), now) };
      for (const row of questView(p.quests, now).daily) if (row.claimable) p = claimQuest(p, row.id, now).progress;
    }
    expect(p.trackXp).toBeGreaterThanOrEqual(360);
    expect(p.xp).toBe(p.trackXp);
    expect(unlockedCosmetics(p.trackXp)).toContain('back_midnight');
  });

  it('keeps every cosmetic a player had unlocked with points', () => {
    for (const points of [0, 29, 30, 70, 119, 120, 200, 299, 300, 450]) {
      const oldUnlocks = [30, 70, 120, 200, 300].filter((t) => points >= t).length;
      const migrated = normalizeProgress({ trackPoints: points } as never);
      expect(unlockedCosmetics(migrated.trackXp).length).toBe(2 + oldUnlocks);
    }
  });
});

describe('collecting at the end of a game', () => {
  const wide = stats({ wins: 1, marketTakes: 20, marketCoins: 30, tokensEnd: 3, goldEnd: 9, majorities: 3, withPeople: 1, rank: 1 });

  it('pays every finished quest once and leaves unfinished ones open', () => {
    let p: Progress = emptyProgress();
    p = { ...p, quests: applyGameToQuests(p.quests, wide, t0) };
    const done = questView(p.quests, t0);
    const expected = done.daily.concat(done.weekly).filter((r) => r.claimable);
    expect(expected.length).toBeGreaterThan(0);
    const got = collectQuests(p, t0);
    expect(got.collected.map((d) => d.id).sort()).toEqual(expected.map((r) => r.id).sort());
    const sum = expected.reduce((n, r) => n + r.xp, 0);
    expect(got.progress.xp).toBe(sum);
    expect(got.progress.trackXp).toBe(sum);
    const after = questView(got.progress.quests, t0);
    for (const r of after.daily.concat(after.weekly)) expect(r.claimable).toBe(false);
    // A second pass has nothing left to pay.
    const again = collectQuests(got.progress, t0);
    expect(again.collected).toEqual([]);
    expect(again.progress.xp).toBe(sum);
    // And a manual claim of a collected quest is refused.
    expect(claimQuest(got.progress, expected[0]!.id, t0).ok).toBe(false);
  });

  it('does not mutate the progress it was given', () => {
    let p: Progress = emptyProgress();
    p = { ...p, quests: applyGameToQuests(p.quests, wide, t0) };
    const snapshot = JSON.stringify(p);
    collectQuests(p, t0);
    expect(JSON.stringify(p)).toBe(snapshot);
  });

  it('pays nothing for a quest finished on a day that is over', () => {
    let p: Progress = emptyProgress();
    p = { ...p, quests: applyGameToQuests(p.quests, wide, t0) };
    const weeklyDone = questView(p.quests, t0).weekly.filter((r) => r.claimable);
    // Next day, same week: the dailies started over, the weeklies are still there.
    const got = collectQuests(p, t0 + day);
    expect(got.collected.map((d) => d.id).sort()).toEqual(weeklyDone.map((r) => r.id).sort());
  });

  it('lists open quests, the ones the game moved first and the nearest to done first', () => {
    const before = rolloverQuests(undefined, t0);
    const after = applyGameToQuests(before, stats({ games: 1, marketTakes: 1 }), t0);
    const open = openQuests(before, after, t0, 10);
    const view = questView(after, t0);
    const all = view.daily.concat(view.weekly);
    expect(open.length).toBe(all.filter((r) => !r.claimable && !r.claimed).length);
    const moved = open.filter((q) => q.progress > 0);
    // Every moved quest comes before every untouched one.
    expect(open.slice(0, moved.length).every((q) => q.progress > 0)).toBe(true);
    for (let i = 1; i < moved.length; i++) {
      expect(moved[i - 1]!.progress / moved[i - 1]!.target).toBeGreaterThanOrEqual(moved[i]!.progress / moved[i]!.target);
    }
    expect(openQuests(before, after, t0).length).toBeLessThanOrEqual(2);
    expect(openQuests(before, after, t0, 0)).toEqual([]);
    for (const q of open) expect(q.weekly).toBe(q.id.startsWith('w_'));
  });

  it('lists a quest the game moved before one that is merely close to done', () => {
    const base = rolloverQuests(undefined, t0);
    const [close, far] = weeklyQuests(base.week) as [QuestDef, QuestDef];
    const before = { ...base, weekly: { [close.id]: { progress: close.target - 1, claimed: false }, [far.id]: { progress: 0, claimed: false } } };
    const after = { ...before, weekly: { ...before.weekly, [far.id]: { progress: 1, claimed: false } } };
    expect(openQuests(before, after, t0, 10).filter((q) => q.weekly).map((q) => q.id)).toEqual([far.id, close.id]);
    // With nothing moved, the nearest to done leads.
    expect(openQuests(after, after, t0, 10).filter((q) => q.weekly).map((q) => q.id)).toEqual([close.id, far.id]);
  });

  it('treats quest progress from an earlier day as no progress', () => {
    const yesterday = applyGameToQuests(undefined, stats({ games: 1 }), t0 - day * 7);
    const after = applyGameToQuests(yesterday, stats({ games: 1 }), t0);
    const open = openQuests(yesterday, after, t0, 10);
    for (const q of open) expect(q.progress).toBeLessThanOrEqual(1);
  });
});

describe('stored rows', () => {
  it('normalise old profiles without quest fields', () => {
    const old = { xp: 120, level: 2, gamesPlayed: 3, wins: 1, streak: 4, lastDailyClaim: '2026-09-27', bestRank: 1 };
    const p = normalizeProgress(old as Partial<Progress>);
    expect(p.trackXp).toBe(0);
    expect(p.quests.day).toBe('');
    expect(p.equipped).toEqual({ cardBack: 'back_classic', table: 'table_green' });
    expect(p.xp).toBe(120);
    expect(normalizeProgress(null).level).toBe(1);
  });
});
