import { describe, expect, it } from 'vitest';
import { STARTING_COINS, TOTAL_SHARES } from './companies';
import { botAction } from './bot';
import { applyAction, autoAction, createGame, isLegal, totalCards, totalCoins, type SeatDef } from './game';
import type { Action, GameState } from './types';

// The Nakama type lib has no console or performance; vitest runs under Node, which does.
declare const console: { log(message: string): void };
declare const performance: { now(): number };

const MAX_TURNS = 200;

function seats(n: number): SeatDef[] {
  const out: SeatDef[] = [];
  for (let i = 0; i < n; i++) out.push({ id: `bot:${i}`, name: `Bot ${i}`, isBot: true });
  return out;
}

/** Deterministic per-step pseudo tie-break in [0, 1). */
function tie(step: number, seed: number): number {
  return ((step * 7919 + seed * 104729) % 1000) / 1000;
}

interface Played {
  state: GameState;
  turns: number;
  actions: Array<{ before: GameState; action: Action }>;
}

/** Play a full game where every seat uses botAction; asserts legality and invariants. */
function playBotGame(n: number, seed: number, keep = false): Played {
  let state = createGame(seats(n), seed, { stepSeconds: 0 });
  let steps = 0;
  const actions: Played['actions'] = [];
  while (state.phase !== 'ended') {
    const action = botAction(state, tie(steps, seed));
    expect(isLegal(state, state.active, action)).toBe(true);
    if (keep) actions.push({ before: state, action });
    state = applyAction(state, state.active, action).state;
    steps++;
    expect(totalCoins(state)).toBe(n * STARTING_COINS);
    expect(totalCards(state)).toBe(TOTAL_SHARES);
    if (state.turn > MAX_TURNS + 1) throw new Error(`game with ${n} bots (seed ${seed}) did not end within ${MAX_TURNS} turns`);
  }
  return { state, turns: state.turn, actions };
}

describe('botAction legality', () => {
  it('only ever returns legal actions over many seeded full games', () => {
    for (let n = 3; n <= 7; n++) {
      for (let seed = 1; seed <= 12; seed++) {
        const { state } = playBotGame(n, seed * 31 + n);
        expect(state.phase).toBe('ended');
        expect(state.result).not.toBeNull();
      }
    }
  });
});

describe('botAction determinism', () => {
  it('returns the same action for the same state and tieBreak', () => {
    const { actions } = playBotGame(4, 77, true);
    expect(actions.length).toBeGreaterThan(20);
    for (let i = 0; i < actions.length; i++) {
      const { before, action } = actions[i]!;
      const snapshot = JSON.stringify(before);
      expect(botAction(before, tie(i, 77))).toEqual(action);
      expect(botAction(before, tie(i, 77))).toEqual(action);
      // The lookahead never mutates the input state.
      expect(JSON.stringify(before)).toBe(snapshot);
    }
  });

  it('any tieBreak still yields a legal action', () => {
    const { actions } = playBotGame(5, 5, true);
    for (const t of [0, 0.25, 0.5, 0.999, 1, -1, Number.NaN]) {
      for (let i = 0; i < actions.length; i += 7) {
        const before = actions[i]!.before;
        expect(isLegal(before, before.active, botAction(before, t))).toBe(true);
      }
    }
  });
});

describe('botAction progress guarantee', () => {
  it('bot-only games with 3, 5 and 7 seats end within 200 turns', () => {
    for (const n of [3, 5, 7]) {
      for (let seed = 100; seed < 116; seed++) {
        const { state, turns } = playBotGame(n, seed);
        expect(state.phase).toBe('ended');
        expect(turns).toBeLessThanOrEqual(MAX_TURNS);
      }
    }
  });
});

/**
 * One botAction seat (rotated through every position) against autoAction
 * seats. Returns the rank-1 rate and the per-decision times of the strong seat.
 */
function tournament(seatCount: number, games: number, seedBase: number): { rate: number; strict: number; avgTurns: number; times: number[] } {
  let wins = 0;
  let strictWins = 0;
  let turnsTotal = 0;
  const times: number[] = [];
  for (let g = 0; g < games; g++) {
    const strongSlot = g % seatCount;
    const defs: SeatDef[] = [];
    for (let i = 0; i < seatCount; i++) {
      defs.push({ id: i === strongSlot ? 'strong' : `auto:${i}`, name: `Seat ${i}`, isBot: true });
    }
    let state = createGame(defs, seedBase + g, { stepSeconds: 0 });
    const strong = state.seats.findIndex((s) => s.id === 'strong');
    expect(strong).toBeGreaterThanOrEqual(0);
    let steps = 0;
    while (state.phase !== 'ended') {
      const t = tie(steps, g);
      let action: Action;
      if (state.active === strong) {
        const started = performance.now();
        action = botAction(state, t);
        times.push(performance.now() - started);
      } else {
        action = autoAction(state, t);
      }
      expect(isLegal(state, state.active, action)).toBe(true);
      state = applyAction(state, state.active, action).state;
      steps++;
      if (state.turn > MAX_TURNS + 1) throw new Error(`tournament game ${g} did not end`);
    }
    turnsTotal += state.turn;
    const score = state.result!.scores.find((s) => s.seat === strong)!;
    if (score.rank === 1) wins++;
    let strict = true;
    for (const other of state.result!.scores) {
      if (other.seat !== strong && other.rank === 1) strict = false;
    }
    if (score.rank === 1 && strict) strictWins++;
  }
  return { rate: wins / games, strict: strictWins, avgTurns: turnsTotal / games, times };
}

describe('botAction tournament', () => {
  it('beats two autoAction seats in clearly more than a third of games', { timeout: 120_000 }, () => {
    const games = 240;
    const r = tournament(3, games, 1000);
    console.log(`bot tournament (3 seats): ${(r.rate * 100).toFixed(1)}% rank-1, ${r.strict} outright, avg ${r.avgTurns.toFixed(1)} turns`);
    expect(r.rate).toBeGreaterThanOrEqual(0.45);
  });

  it('beats four autoAction seats in clearly more than a fifth of games, within the time budget', { timeout: 180_000 }, () => {
    // Public quick play fills to 5 seats, so this is the table that matters.
    // Measured over 1600 games in four seed sets: 27.5% to 33.5% rank-1
    // (chance is 20%), so the bound is set below the observed range.
    const games = 500;
    const r = tournament(5, games, 1000);
    const sorted = r.times.slice().sort((a, b) => a - b);
    const avg = sorted.reduce((a, b) => a + b, 0) / sorted.length;
    const p99 = sorted[Math.floor(sorted.length * 0.99)] as number;
    const worst = sorted[sorted.length - 1] as number;
    console.log(`bot tournament (5 seats): ${(r.rate * 100).toFixed(1)}% rank-1, ${r.strict} outright, avg ${r.avgTurns.toFixed(1)} turns; decision ms avg ${avg.toFixed(2)} p99 ${p99.toFixed(2)} max ${worst.toFixed(2)}`);
    expect(r.rate).toBeGreaterThanOrEqual(0.24);
    // WHY: the match loop ticks 4 times a second inside Nakama's goja runtime,
    // roughly 20-50x slower than Node, so a Node p99 under 5 ms keeps a bot
    // decision inside one tick there. Measured: avg 0.3 ms, p99 1.0 ms; the
    // single slowest call is JIT and GC noise, so it is reported, not bounded.
    expect(avg).toBeLessThan(1);
    expect(p99).toBeLessThan(5);
  });
});
