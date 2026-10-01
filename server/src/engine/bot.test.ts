import { describe, expect, it } from 'vitest';
import { botAction } from './bot';
import { HAND_SIZE, REMOVED_SHARES, STARTING_COINS, TOTAL_SHARES, type CompanyId } from './companies';
import { autoAction } from './auto';
import { applyAction, createGame, isLegal, totalCards, totalCoins, type SeatDef } from './game';
import { makeRng, shuffle } from './rng';
import type { Action, Card, GameState } from './types';

// WHY: tsconfig targets the goja runtime (lib ES2016, no DOM or Node types),
// but vitest runs in Node, where console exists; declare just what we use.
declare const console: { log: (...args: unknown[]) => void };

type Policy = (state: GameState, rng: () => number) => Action;

const NEW: Policy = (state, rng) => botAction(state, rng);
const OLD: Policy = (state, rng) => autoAction(state, rng());

function seats(n: number): SeatDef[] {
  const out: SeatDef[] = [];
  for (let i = 0; i < n; i++) out.push({ id: `b${i}`, name: `Bot ${i}`, isBot: true });
  return out;
}

function card(id: number, company: CompanyId): Card {
  return { id, company };
}

/**
 * Plays a full game; policies[i] acts for post-shuffle seat i. Checks
 * legality and conservation on every step.
 */
function playGame(n: number, seed: number, policies: Policy[], maxSteps = 1500): GameState {
  let state = createGame(seats(n), seed, { stepSeconds: 0 });
  const rng = makeRng(seed * 7919 + 17).next;
  let steps = 0;
  while (state.phase !== 'ended') {
    const action = (policies[state.active] as Policy)(state, rng);
    expect(isLegal(state, state.active, action)).toBe(true);
    state = applyAction(state, state.active, action).state;
    steps++;
    if (steps > maxSteps) throw new Error(`game ${n}/${seed} did not end`);
  }
  expect(totalCoins(state)).toBe(n * STARTING_COINS);
  expect(totalCards(state)).toBe(TOTAL_SHARES);
  return state;
}

/** Hand-built state: seat 0 to act, empty market, known supply. */
function fixture(n = 3): GameState {
  const s = createGame(seats(n), 1, { stepSeconds: 0 });
  s.market = [];
  s.removed = [card(40, 5), card(41, 5), card(42, 5), card(43, 5), card(44, 5)];
  s.supply = [];
  for (let i = 0; i < 12; i++) s.supply.push(card(100 + i, 4));
  s.tokens = [null, null, null, null, null, null];
  for (const seat of s.seats) {
    seat.hand = [];
    seat.portfolio = [];
    seat.bronze = STARTING_COINS;
    seat.gold = 0;
  }
  s.active = 0;
  s.phase = 'take';
  s.tookCompany = null;
  return s;
}

describe('botAction legality and termination', () => {
  it('always returns a legal action and games end with coins and cards conserved, 3 to 7 seats', () => {
    for (let n = 3; n <= 7; n++) {
      for (let seed = 1; seed <= 12; seed++) {
        const all: Policy[] = [];
        const mixed: Policy[] = [];
        for (let i = 0; i < n; i++) {
          all.push(NEW);
          mixed.push(i % 2 === 0 ? NEW : OLD);
        }
        const a = playGame(n, seed * 101 + n, all);
        expect(a.phase).toBe('ended');
        expect(a.supply.length).toBe(0);
        const b = playGame(n, seed * 103 + n, mixed);
        expect(b.result!.scores.length).toBe(n);
      }
    }
  });

  it('is deterministic for the same state and rng sequence', () => {
    let state = createGame(seats(5), 99, { stepSeconds: 0 });
    for (let i = 0; i < 60 && state.phase !== 'ended'; i++) {
      const a = botAction(state, makeRng(i).next);
      const b = botAction(state, makeRng(i).next);
      expect(a).toEqual(b);
      state = applyAction(state, state.active, a).state;
    }
  });
});

interface Standing {
  avg: number;
  winRate: number;
}

/**
 * Plays every rotation of `lineup` over `seedCount` fixed seeds (so each
 * policy sits in every seat of every deal) and returns per-label averages.
 * Shared first places count as a fraction of a win.
 */
function tournament(n: number, lineup: Array<'new' | 'old'>, seedCount: number, seedBase: number): { new: Standing; old: Standing } {
  const sum = { new: { score: 0, wins: 0, seats: 0 }, old: { score: 0, wins: 0, seats: 0 } };
  for (let sd = 0; sd < seedCount; sd++) {
    for (let rot = 0; rot < n; rot++) {
      const labels: Array<'new' | 'old'> = [];
      for (let i = 0; i < n; i++) labels.push(lineup[(i + rot) % n] as 'new' | 'old');
      const state = playGame(n, seedBase + sd, labels.map((l) => (l === 'new' ? NEW : OLD)));
      const scores = state.result!.scores;
      const winners = scores.filter((x) => x.rank === 1).length;
      for (const sc of scores) {
        const acc = sum[labels[sc.seat] as 'new' | 'old'];
        acc.score += sc.score;
        acc.seats++;
        if (sc.rank === 1) acc.wins += 1 / winners;
      }
    }
  }
  const standing = (a: { score: number; wins: number; seats: number }): Standing => ({
    avg: a.seats > 0 ? a.score / a.seats : 0,
    winRate: a.seats > 0 ? a.wins / a.seats : 0,
  });
  return { new: standing(sum.new), old: standing(sum.old) };
}

describe('botAction strength against the placeholder policy', () => {
  it('scores clearly more and wins clearly more often than autoAction, 3 to 7 seats', () => {
    // [seats, lineup, seeds, min average-score lead, min win rate per new seat]
    // Thresholds leave a wide margin under the measured values (see rules-spec
    // section 8). At 7 seats the win-rate edge is too small to assert on this
    // sample, so only the score lead and "wins more often than old" are checked.
    const cases: Array<[number, Array<'new' | 'old'>, number, number, number]> = [
      [3, ['new', 'old', 'old'], 60, 5, 0.5],
      [4, ['new', 'old', 'old', 'old'], 40, 3.5, 0.32],
      [5, ['new', 'old', 'old', 'old', 'old'], 40, 2.5, 0.24],
      [5, ['new', 'new', 'old', 'old', 'old'], 40, 2.5, 0.23],
      [5, ['new', 'new', 'new', 'old', 'old'], 30, 2, 0.21],
      [7, ['new', 'old', 'old', 'old', 'old', 'old', 'old'], 20, 1.5, 0],
    ];
    const results: Array<{ lead: number; win: number; oldWin: number; minLead: number; minWin: number }> = [];
    const lines: string[] = [];
    for (const [n, lineup, seedCount, minLead, minWin] of cases) {
      const r = tournament(n, lineup, seedCount, 7000 + n * 100);
      const newSeats = lineup.filter((l) => l === 'new').length;
      lines.push(
        `${n} seats, ${newSeats} new vs ${n - newSeats} old, ${seedCount * n} games: ` +
          `new avg ${r.new.avg.toFixed(2)} win ${(100 * r.new.winRate).toFixed(1)}% | ` +
          `old avg ${r.old.avg.toFixed(2)} win ${(100 * r.old.winRate).toFixed(1)}% | fair ${(100 / n).toFixed(1)}%`,
      );
      results.push({ lead: r.new.avg - r.old.avg, win: r.new.winRate, oldWin: r.old.winRate, minLead, minWin });
    }
    console.log('bot tournament (every seat rotation of each deal):\n' + lines.join('\n'));
    for (const r of results) {
      expect(r.lead).toBeGreaterThan(r.minLead);
      expect(r.win).toBeGreaterThan(r.minWin);
      expect(r.win).toBeGreaterThan(r.oldWin);
    }
  }, 30_000);

  it('holds one simple seat well under its fair share at a 3-seat table', () => {
    // The commonest table with bots: one person and two bots. The simple
    // policy stands in for the person.
    const r = tournament(3, ['old', 'new', 'new'], 80, 7700);
    console.log(`3 seats, 2 new vs 1 old, 240 games: old avg ${r.old.avg.toFixed(2)} win ${(100 * r.old.winRate).toFixed(1)}% | new avg ${r.new.avg.toFixed(2)}`);
    // Measured on these deals: the simple seat wins 22.5% and trails the bots
    // by 5.3 points; with the large-table model at 3 seats it won 28.3% and
    // trailed by 3.4 (rules-spec section 8.2).
    expect(r.old.winRate).toBeLessThan(0.25);
    expect(r.new.avg - r.old.avg).toBeGreaterThan(4);
  }, 30_000);
});

describe('botAction uses only what its seat can see', () => {
  /** Reshuffle everything the active seat cannot see, keeping every count. */
  function scrambleHidden(state: GameState, seed: number): GameState {
    const s = JSON.parse(JSON.stringify(state)) as GameState;
    const me = s.active;
    const pool: Card[] = s.supply.concat(s.removed);
    for (let i = 0; i < s.seats.length; i++) if (i !== me) pool.push(...(s.seats[i] as GameState['seats'][number]).hand);
    shuffle(pool, makeRng(seed));
    s.supply = pool.splice(0, s.supply.length);
    s.removed = pool.splice(0, s.removed.length);
    for (let i = 0; i < s.seats.length; i++) {
      if (i === me) continue;
      const seat = s.seats[i] as GameState['seats'][number];
      seat.hand = pool.splice(0, seat.hand.length);
    }
    expect(pool.length).toBe(0);
    return s;
  }

  it('picks the same action when other hands, the supply order and removed cards differ', () => {
    let checked = 0;
    for (const n of [3, 5, 7]) {
      let state = createGame(seats(n), 4242 + n, { stepSeconds: 0 });
      const rng = makeRng(n).next;
      while (state.phase !== 'ended') {
        const r = Math.floor(rng() * 1e9);
        const action = botAction(state, makeRng(r).next);
        for (let v = 0; v < 2; v++) {
          const variant = scrambleHidden(state, r + v + 1);
          expect(JSON.stringify(variant)).not.toBe(JSON.stringify(state));
          expect(botAction(variant, makeRng(r).next)).toEqual(action);
          checked++;
        }
        state = applyAction(state, state.active, action).state;
      }
    }
    expect(checked).toBeGreaterThan(100);
  });
});

describe('botAction decisions', () => {
  it('takes a Market share carrying 3 coins rather than paying to draw', () => {
    const s = fixture();
    s.seats[0]!.hand = [card(10, 3), card(11, 3), card(12, 2)];
    s.market = [
      { card: card(20, 3), coins: 3 },
      { card: card(21, 1), coins: 0 },
    ];
    const a = botAction(s, makeRng(1).next);
    expect(a).toEqual({ type: 'take_market', cardId: 20 });
  });

  it('never sells the company it took this turn', () => {
    for (let seed = 1; seed <= 20; seed++) {
      let state = createGame(seats(4), seed, { stepSeconds: 0 });
      const rng = makeRng(seed).next;
      while (state.phase !== 'ended') {
        const action = botAction(state, rng);
        if (action.type === 'play_market') {
          const seat = state.seats[state.active]!;
          const played = seat.hand.find((c) => c.id === action.cardId)!;
          expect(played.company).not.toBe(state.tookCompany);
        }
        state = applyAction(state, state.active, action).state;
      }
    }
  });

  it('dumps a hopeless minority share to the Market', () => {
    const s = fixture();
    // Seat 1 has 4 of company 0 locked in; our lone company-0 share can only pay them.
    s.seats[1]!.portfolio = [card(0, 0), card(1, 0), card(2, 0), card(3, 0)];
    s.tokens[0] = 1;
    s.seats[0]!.portfolio = [card(30, 5), card(31, 5)];
    s.seats[0]!.hand = [card(4, 0), card(32, 5), card(33, 5)];
    const r = applyAction(s, 0, { type: 'take_supply' }); // draws company 4
    const a = botAction(r.state, makeRng(3).next);
    expect(a).toEqual({ type: 'play_market', cardId: 4 });
  });

  it('keeps shares of a company it leads', () => {
    const s = fixture();
    s.seats[0]!.portfolio = [card(30, 5), card(31, 5)];
    s.seats[0]!.hand = [card(32, 5), card(33, 5), card(20, 2)];
    s.seats[1]!.portfolio = [card(34, 5)];
    const r = applyAction(s, 0, { type: 'take_supply' }); // draws company 4
    for (let seed = 1; seed <= 20; seed++) {
      const a = botAction(r.state, makeRng(seed).next);
      // Either everything is kept, or the stray company-2 share is sold; never company 5.
      if (a.type === 'play_market') expect(a.cardId).toBe(20);
      else expect(a.type).toBe('play_portfolio');
    }
  });

  it('locks a pair into the Portfolio on its first turn instead of selling a stray share', () => {
    const s = fixture();
    s.seats[0]!.hand = [card(32, 5), card(33, 5), card(20, 2)];
    const r = applyAction(s, 0, { type: 'take_supply' }); // draws company 4
    for (let seed = 1; seed <= 20; seed++) {
      const a = botAction(r.state, makeRng(seed).next);
      expect(a.type).toBe('play_portfolio');
      expect(r.state.seats[0]!.hand.find((c) => c.id === (a as { cardId: number }).cardId)!.company).toBe(5);
    }
  });

  it('commits its focus company to the Portfolio once it falls behind the keep pace', () => {
    const s = fixture();
    s.seats[0]!.portfolio = [];
    // No pair in hand: only the keep pace can make it keep.
    s.seats[0]!.hand = [card(32, 5), card(10, 3), card(20, 2)];
    const r = applyAction(s, 0, { type: 'take_supply' }); // draws company 4
    // Seat 0's first turn: no pace to keep yet, so a stray share may be sold.
    const early = new Set<string>();
    for (let seed = 1; seed <= 20; seed++) early.add(JSON.stringify(botAction(r.state, makeRng(seed).next)));
    expect([...early].some((a) => a.includes('play_market'))).toBe(true);
    // Seat 0's fourth turn with an empty Portfolio: it keeps a company-5 share.
    r.state.turn = 10;
    for (let seed = 1; seed <= 20; seed++) {
      const a = botAction(r.state, makeRng(seed).next);
      expect(a.type).toBe('play_portfolio');
      expect(r.state.seats[0]!.hand.find((c) => c.id === (a as { cardId: number }).cardId)!.company).toBe(5);
    }
  });

  it('builds a Portfolio over the game instead of selling turn after turn', () => {
    // One simple seat stands in for a person; the rest are heuristic bots.
    for (const n of [3, 4]) {
      let keeps = 0;
      let sells = 0;
      let stuck = 0;
      let bots = 0;
      let firstKeepTotal = 0;
      for (let seed = 1; seed <= 30; seed++) {
        const human = seed % n;
        const policies: Policy[] = [];
        for (let i = 0; i < n; i++) policies.push(i === human ? OLD : NEW);
        let state = createGame(seats(n), 5100 + seed, { stepSeconds: 0 });
        const rng = makeRng(seed).next;
        const initial = state.supply.length;
        let mid: number[] | null = null;
        const plays: number[] = [];
        const firstKeep: number[] = [];
        for (let i = 0; i < n; i++) {
          plays.push(0);
          firstKeep.push(0);
        }
        while (state.phase !== 'ended') {
          const action = (policies[state.active] as Policy)(state, rng);
          if (state.active !== human && state.phase === 'play') {
            plays[state.active] = (plays[state.active] as number) + 1;
            if (action.type === 'play_portfolio') {
              keeps++;
              if (firstKeep[state.active] === 0) firstKeep[state.active] = plays[state.active] as number;
            } else {
              sells++;
            }
          }
          state = applyAction(state, state.active, action).state;
          if (!mid && state.supply.length <= initial / 2) mid = state.seats.map((x) => x.portfolio.length);
        }
        for (let i = 0; i < n; i++) {
          if (i === human) continue;
          bots++;
          if (mid![i]! <= 1) stuck++;
          expect(firstKeep[i]).toBeGreaterThan(0);
          firstKeepTotal += firstKeep[i] as number;
        }
      }
      // Measured on these deals: 50% and 62% of plays kept, the first keep on
      // a bot's 1.65th and 1.6th turn on average, and 0% and 7% of bots with at
      // most one Portfolio share at mid-game. Before the small-table model:
      // 47% and 59% kept, first keep on turn 2.1 and 1.9, 0% and 8% stuck.
      // With the keep pace alone: 33% and 35% kept, first keep on turn 3;
      // before it, 18 to 32% of bots stuck.
      expect(keeps / (keeps + sells)).toBeGreaterThan(0.45);
      expect(firstKeepTotal / bots).toBeLessThan(2.2);
      expect(stuck / bots).toBeLessThan(0.12);
    }
  }, 30_000);

  it('draws when the table has been cycling Market shares for too long', () => {
    const s = fixture();
    s.seats[0]!.hand = [card(10, 3), card(11, 3), card(12, 2)];
    s.market = [{ card: card(20, 3), coins: 3 }];
    // Without the guard it takes the 3-coin share.
    expect(botAction(s, makeRng(1).next)).toEqual({ type: 'take_market', cardId: 20 });
    // 40 turns played but only 1 draw: the stall guard forces a draw.
    const initialSupply = TOTAL_SHARES - REMOVED_SHARES - 3 * HAND_SIZE;
    s.supply = [];
    for (let i = 0; i < initialSupply - 1; i++) s.supply.push(card(100 + i, 4));
    s.turn = 41;
    const drawsSoFar = initialSupply - s.supply.length;
    expect(s.turn - 1 - drawsSoFar).toBeGreaterThan(3 * drawsSoFar + 15);
    expect(botAction(s, makeRng(1).next)).toEqual({ type: 'take_supply' });
  });
});
