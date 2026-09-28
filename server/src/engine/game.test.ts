import { describe, expect, it } from 'vitest';
import {
  COMPANIES,
  HAND_SIZE,
  REMOVED_SHARES,
  STARTING_COINS,
  TOTAL_SHARES,
  type CompanyId,
} from './companies';
import {
  applyAction,
  autoAction,
  computeDividends,
  createGame,
  drawCost,
  isLegal,
  legalActions,
  playerView,
  RulesError,
  strictLeader,
  totalCards,
  totalCoins,
  type SeatDef,
} from './game';
import type { Action, Card, GameState } from './types';

function seats(n: number): SeatDef[] {
  const out: SeatDef[] = [];
  for (let i = 0; i < n; i++) out.push({ id: `p${i}`, name: `Player ${i}`, isBot: false });
  return out;
}

function card(id: number, company: CompanyId): Card {
  return { id, company };
}

/** Deterministic hand-built state for edge-case tests. */
function fixture(n = 3): GameState {
  const s = createGame(seats(n), 1);
  s.market = [];
  s.supply = [card(40, 5), card(41, 5), card(42, 5)];
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

function playFullGame(n: number, seed: number): { state: GameState; steps: number } {
  let state = createGame(seats(n), seed, { stepSeconds: 0 });
  let steps = 0;
  while (state.phase !== 'ended') {
    const action = autoAction(state, (steps * 7919) % 1000 / 1000);
    state = applyAction(state, state.active, action).state;
    steps++;
    expect(totalCoins(state)).toBe(n * STARTING_COINS);
    expect(totalCards(state)).toBe(TOTAL_SHARES);
    if (steps > 500) throw new Error('game did not end');
  }
  return { state, steps };
}

describe('setup', () => {
  it('deals 3 cards, 10 coins, removes 5, supply matches player count', () => {
    const expected: Record<number, number> = { 3: 31, 4: 28, 5: 25, 6: 22, 7: 19 };
    for (let n = 3; n <= 7; n++) {
      const s = createGame(seats(n), 42);
      expect(s.removed.length).toBe(REMOVED_SHARES);
      expect(s.supply.length).toBe(expected[n]!);
      for (const seat of s.seats) {
        expect(seat.hand.length).toBe(HAND_SIZE);
        expect(seat.bronze).toBe(STARTING_COINS);
        expect(seat.portfolio.length).toBe(0);
      }
      expect(s.market.length).toBe(0);
      expect(totalCards(s)).toBe(TOTAL_SHARES);
      expect(s.phase).toBe('take');
    }
  });

  it('rejects 2 or 8 seats', () => {
    expect(() => createGame(seats(2), 1)).toThrow(RulesError);
    expect(() => createGame(seats(8), 1)).toThrow(RulesError);
  });

  it('share counts per company are 5..10', () => {
    const s = createGame(seats(3), 7);
    const counts = [0, 0, 0, 0, 0, 0];
    const all = [...s.supply, ...s.removed];
    for (const seat of s.seats) all.push(...seat.hand);
    for (const c of all) counts[c.company] = (counts[c.company] ?? 0) + 1;
    expect(counts).toEqual([5, 6, 7, 8, 9, 10]);
    expect(COMPANIES.map((c) => c.shares)).toEqual([5, 6, 7, 8, 9, 10]);
  });

  it('is deterministic for the same seed and different for another', () => {
    const a = createGame(seats(4), 123);
    const b = createGame(seats(4), 123);
    const c = createGame(seats(4), 124);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    expect(JSON.stringify(a)).not.toBe(JSON.stringify(c));
  });

  it('sets a deadline when stepSeconds > 0 and now is given', () => {
    const s = createGame(seats(3), 1, { stepSeconds: 30 }, 1000);
    expect(s.deadline).toBe(31000);
    const t = createGame(seats(3), 1, { stepSeconds: 0 }, 1000);
    expect(t.deadline).toBe(0);
  });
});

describe('take step', () => {
  it('drawing from the supply costs one coin per market card and puts coins on them', () => {
    const s = fixture();
    s.market = [
      { card: card(0, 0), coins: 0 },
      { card: card(5, 1), coins: 2 },
    ];
    s.seats[0]!.hand = [card(10, 1), card(11, 2), card(12, 3)];
    expect(drawCost(s, 0)).toBe(2);
    const r = applyAction(s, 0, { type: 'take_supply' });
    expect(r.state.seats[0]!.bronze).toBe(8);
    expect(r.state.market.map((m) => m.coins)).toEqual([1, 3]);
    expect(r.state.seats[0]!.hand.length).toBe(4);
    expect(r.state.supply.length).toBe(2);
    expect(r.state.phase).toBe('play');
    expect(r.state.tookCompany).toBe(5);
    expect(r.events[0]).toEqual({ type: 'took_supply', seat: 0, cost: 2 });
  });

  it('does not pay onto companies whose regulator token you hold', () => {
    const s = fixture();
    s.market = [
      { card: card(0, 0), coins: 0 },
      { card: card(5, 1), coins: 0 },
    ];
    s.tokens[0] = 0;
    expect(drawCost(s, 0)).toBe(1);
    const r = applyAction(s, 0, { type: 'take_supply' });
    expect(r.state.market.map((m) => m.coins)).toEqual([0, 1]);
    expect(r.state.seats[0]!.bronze).toBe(9);
  });

  it('forbids drawing when you cannot afford the market', () => {
    const s = fixture();
    s.market = [
      { card: card(0, 0), coins: 0 },
      { card: card(5, 1), coins: 0 },
    ];
    s.seats[0]!.bronze = 1;
    expect(isLegal(s, 0, { type: 'take_supply' })).toBe(false);
    expect(() => applyAction(s, 0, { type: 'take_supply' })).toThrow(RulesError);
    // The market is still available.
    expect(isLegal(s, 0, { type: 'take_market', cardId: 0 })).toBe(true);
  });

  it('a broke player with tokens on every market company can still draw for free', () => {
    const s = fixture();
    s.market = [{ card: card(0, 0), coins: 0 }];
    s.tokens[0] = 0;
    s.seats[0]!.bronze = 0;
    expect(drawCost(s, 0)).toBe(0);
    expect(isLegal(s, 0, { type: 'take_supply' })).toBe(true);
    expect(isLegal(s, 0, { type: 'take_market', cardId: 0 })).toBe(false);
    expect(legalActions(s, 0).length).toBe(1);
  });

  it('taking from the market collects its coins', () => {
    const s = fixture();
    s.market = [{ card: card(0, 0), coins: 3 }];
    const r = applyAction(s, 0, { type: 'take_market', cardId: 0 });
    expect(r.state.seats[0]!.bronze).toBe(13);
    expect(r.state.market.length).toBe(0);
    expect(r.state.seats[0]!.hand[0]).toEqual(card(0, 0));
    expect(r.state.tookCompany).toBe(0);
  });

  it('forbids taking a market card of a company whose token you hold', () => {
    const s = fixture();
    s.market = [{ card: card(0, 0), coins: 3 }];
    s.tokens[0] = 0;
    expect(isLegal(s, 0, { type: 'take_market', cardId: 0 })).toBe(false);
    s.tokens[0] = 1;
    expect(isLegal(s, 0, { type: 'take_market', cardId: 0 })).toBe(true);
  });

  it('rejects actions from a non-active seat and play actions during take', () => {
    const s = fixture();
    expect(isLegal(s, 1, { type: 'take_supply' })).toBe(false);
    expect(legalActions(s, 1)).toEqual([]);
    s.seats[0]!.hand = [card(1, 0)];
    expect(isLegal(s, 0, { type: 'play_portfolio', cardId: 1 })).toBe(false);
  });
});

describe('play step', () => {
  function afterTake(): GameState {
    const s = fixture();
    s.seats[0]!.hand = [card(10, 1), card(11, 2), card(12, 5)];
    return applyAction(s, 0, { type: 'take_supply' }).state; // takes card 42 (company 5)
  }

  it('can play any hand card to the portfolio', () => {
    const s = afterTake();
    const r = applyAction(s, 0, { type: 'play_portfolio', cardId: 42 });
    expect(r.state.seats[0]!.portfolio).toEqual([card(42, 5)]);
    expect(r.state.seats[0]!.hand.length).toBe(3);
    expect(r.state.active).toBe(1);
    expect(r.state.phase).toBe('take');
    expect(r.state.turn).toBe(2);
    expect(r.state.tookCompany).toBe(null);
  });

  it('cannot play to the market a card of the company just taken', () => {
    const s = afterTake();
    expect(isLegal(s, 0, { type: 'play_market', cardId: 42 })).toBe(false);
    expect(isLegal(s, 0, { type: 'play_market', cardId: 12 })).toBe(false); // same company 5
    expect(isLegal(s, 0, { type: 'play_market', cardId: 10 })).toBe(true);
    const r = applyAction(s, 0, { type: 'play_market', cardId: 10 });
    expect(r.state.market).toEqual([{ card: card(10, 1), coins: 0 }]);
  });

  it('cannot play a card that is not in hand', () => {
    const s = afterTake();
    expect(isLegal(s, 0, { type: 'play_portfolio', cardId: 999 })).toBe(false);
  });
});

describe('regulator tokens', () => {
  it('goes to the seat with strictly the most and stays on ties', () => {
    const s = fixture();
    s.supply = [];
    for (let i = 0; i < 12; i++) s.supply.push(card(40 + i, 5));
    // Seat 0 plays company 1 to portfolio: 1 vs 0 -> seat 0 gets the token.
    s.seats[0]!.hand = [card(10, 1), card(11, 1), card(12, 2)];
    s.seats[1]!.hand = [card(13, 1), card(14, 3), card(15, 3)];
    s.seats[2]!.hand = [card(16, 1), card(17, 1), card(18, 3)];
    let r = applyAction(s, 0, { type: 'take_supply' });
    r = applyAction(r.state, 0, { type: 'play_portfolio', cardId: 10 });
    expect(r.state.tokens[1]).toBe(0);
    expect(r.events.some((e) => e.type === 'token_moved' && e.company === 1 && e.to === 0)).toBe(true);

    // Seat 1 plays company 1: 1 vs 1 -> tie, seat 0 keeps it.
    r = applyAction(r.state, 1, { type: 'take_supply' });
    r = applyAction(r.state, 1, { type: 'play_portfolio', cardId: 13 });
    expect(r.state.tokens[1]).toBe(0);
    expect(r.events.some((e) => e.type === 'token_moved')).toBe(false);

    // Seat 2 plays company 1: three-way tie, seat 0 still keeps it.
    r = applyAction(r.state, 2, { type: 'take_supply' });
    r = applyAction(r.state, 2, { type: 'play_portfolio', cardId: 16 });
    expect(r.state.tokens[1]).toBe(0);

    // Seats 0 and 1 play elsewhere; seat 2 plays a second company-1 share and takes the token.
    r = applyAction(r.state, 0, { type: 'take_supply' });
    r = applyAction(r.state, 0, { type: 'play_portfolio', cardId: 12 });
    r = applyAction(r.state, 1, { type: 'take_supply' });
    r = applyAction(r.state, 1, { type: 'play_portfolio', cardId: 14 });
    r = applyAction(r.state, 2, { type: 'take_supply' });
    r = applyAction(r.state, 2, { type: 'play_portfolio', cardId: 17 });
    expect(r.state.tokens[1]).toBe(2);
    expect(r.events.some((e) => e.type === 'token_moved' && e.company === 1 && e.from === 0 && e.to === 2)).toBe(true);

    // Token holder may not take company 1 from the market but pays nothing onto it.
    r.state.market = [{ card: card(11, 1), coins: 0 }];
    r.state.active = 2;
    r.state.phase = 'take';
    expect(isLegal(r.state, 2, { type: 'take_market', cardId: 11 })).toBe(false);
    expect(drawCost(r.state, 2)).toBe(0);
    expect(drawCost(r.state, 0)).toBe(1);
  });

  it('strictLeader returns null when nobody holds shares or when tied', () => {
    const s = fixture();
    expect(strictLeader(s, 0)).toBe(null);
    s.seats[0]!.portfolio = [card(0, 0)];
    s.seats[1]!.portfolio = [card(1, 0)];
    expect(strictLeader(s, 0)).toBe(null);
    s.seats[1]!.portfolio.push(card(2, 0));
    expect(strictLeader(s, 0)).toBe(1);
  });
});

describe('game end and dividends', () => {
  it('ends after the last supply card is drawn and the play step completes, merging hands', () => {
    const s = fixture();
    s.supply = [card(40, 5)];
    s.seats[0]!.hand = [card(10, 1), card(11, 2), card(12, 3)];
    s.seats[1]!.hand = [card(13, 1), card(14, 2), card(15, 3)];
    s.seats[2]!.hand = [card(16, 1), card(17, 2), card(18, 3)];
    let r = applyAction(s, 0, { type: 'take_supply' });
    expect(r.state.phase).toBe('play');
    r = applyAction(r.state, 0, { type: 'play_portfolio', cardId: 40 });
    expect(r.state.phase).toBe('ended');
    expect(r.state.result).not.toBeNull();
    for (const seat of r.state.seats) expect(seat.hand.length).toBe(0);
    expect(r.state.seats[0]!.portfolio.length).toBe(4);
    expect(r.events.some((e) => e.type === 'hands_revealed')).toBe(true);
    expect(r.events[r.events.length - 1]!.type).toBe('game_ended');
    expect(legalActions(r.state, 0)).toEqual([]);
  });

  it('pays the majority holder one coin per share from each minority holder, flipped to gold', () => {
    const s = fixture();
    s.seats[0]!.portfolio = [card(0, 0), card(1, 0), card(2, 0)]; // majority of company 0
    s.seats[1]!.portfolio = [card(3, 0), card(4, 0)]; // owes 2
    s.seats[2]!.portfolio = [card(5, 1)]; // sole holder of company 1, nobody owes
    const result = computeDividends(s);
    expect(result.companies[0]!.majority).toBe(0);
    expect(result.companies[0]!.payments).toEqual([{ from: 1, to: 0, coins: 2 }]);
    expect(result.companies[1]!.majority).toBe(2);
    expect(result.companies[1]!.payments).toEqual([]);
    expect(s.seats[0]!.bronze).toBe(10);
    expect(s.seats[0]!.gold).toBe(2);
    expect(s.seats[1]!.bronze).toBe(8);
    expect(result.scores.find((x) => x.seat === 0)!.score).toBe(16);
    expect(result.scores.find((x) => x.seat === 0)!.rank).toBe(1);
    expect(result.scores.find((x) => x.seat === 2)!.rank).toBe(2);
    expect(result.scores.find((x) => x.seat === 1)!.rank).toBe(3);
  });

  it('pays nothing for a company whose lead is tied', () => {
    const s = fixture();
    s.seats[0]!.portfolio = [card(0, 0), card(1, 0)];
    s.seats[1]!.portfolio = [card(3, 0), card(4, 0)];
    s.seats[2]!.portfolio = [card(2, 0)];
    const result = computeDividends(s);
    expect(result.companies[0]!.majority).toBe(null);
    expect(result.companies[0]!.payments).toEqual([]);
    expect(s.seats.map((x) => x.bronze)).toEqual([10, 10, 10]);
  });

  it('a player who cannot cover what they owe pays everything they have, in creditor order', () => {
    const s = fixture();
    s.seats[0]!.portfolio = [card(0, 0), card(1, 0), card(2, 0)]; // majority co 0
    s.seats[1]!.portfolio = [card(5, 1), card(6, 1), card(7, 1)]; // majority co 1
    s.seats[2]!.portfolio = [card(3, 0), card(4, 0), card(8, 1), card(9, 1)]; // owes 2 to seat 0 and 2 to seat 1
    s.seats[2]!.bronze = 3;
    computeDividends(s);
    expect(s.seats[2]!.bronze).toBe(0);
    // Round-robin one coin at a time: 0,1,0 -> seat 0 gets 2, seat 1 gets 1.
    expect(s.seats[0]!.gold).toBe(2);
    expect(s.seats[1]!.gold).toBe(1);
    expect(totalCoins(s)).toBe(23);
  });

  it('dividends received cannot be used to pay other dividends', () => {
    const s = fixture();
    s.seats[0]!.portfolio = [card(0, 0), card(1, 0), card(5, 1)]; // majority co 0; owes 1 to seat 1 for co 1
    s.seats[1]!.portfolio = [card(6, 1), card(7, 1), card(2, 0)]; // majority co 1; owes 1 to seat 0
    s.seats[0]!.bronze = 0;
    s.seats[1]!.bronze = 0;
    computeDividends(s);
    expect(s.seats[0]!.gold).toBe(0);
    expect(s.seats[1]!.gold).toBe(0);
  });

  it('ranks ties by more gold, then fewer portfolio shares', () => {
    const s = fixture();
    s.seats[0]!.bronze = 7;
    s.seats[0]!.gold = 1; // 10
    s.seats[1]!.bronze = 10;
    s.seats[1]!.gold = 0; // 10
    s.seats[2]!.bronze = 10;
    s.seats[2]!.gold = 0; // 10
    s.seats[1]!.portfolio = [card(0, 0)];
    s.seats[2]!.portfolio = [];
    const result = computeDividends(s);
    const rank = (i: number) => result.scores.find((x) => x.seat === i)!.rank;
    expect(rank(0)).toBe(1);
    expect(rank(2)).toBe(2);
    expect(rank(1)).toBe(3);
  });
});

describe('player view', () => {
  it('hides other hands, the supply and the removed cards', () => {
    const s = createGame(seats(4), 9);
    const v = playerView(s, 1);
    expect(v.you).toBe(1);
    expect(v.seats[1]!.hand).toEqual(s.seats[1]!.hand);
    expect(v.seats[0]!.hand).toBeUndefined();
    expect(v.seats[0]!.handCount).toBe(3);
    expect(v.supplyCount).toBe(28);
    expect(v.removedCount).toBe(5);
    expect(JSON.stringify(v)).not.toContain('"seed"');
    expect(JSON.stringify(v)).not.toContain('"supply":[');
    expect(v.legal.length).toBe(0); // not active seat (seat 0 starts)
    const v0 = playerView(s, 0);
    expect(v0.legal).toEqual([{ type: 'take_supply' }]);
    expect(v0.drawCost).toBe(0);
  });

  it('reveals every hand once the game has ended, and gives spectators no legal actions', () => {
    const { state } = playFullGame(3, 5);
    const v = playerView(state, null);
    expect(v.you).toBe(null);
    expect(v.legal).toEqual([]);
    expect(v.result).not.toBeNull();
    for (const seat of v.seats) expect(seat.hand).toEqual([]);
  });
});

describe('full games with auto-moves', () => {
  it('conserve coins and cards and always end, for 3 to 7 seats and many seeds', () => {
    for (let n = 3; n <= 7; n++) {
      for (let seed = 1; seed <= 40; seed++) {
        const { state, steps } = playFullGame(n, seed * 31 + n);
        expect(state.phase).toBe('ended');
        expect(state.supply.length).toBe(0);
        expect(state.result!.scores.length).toBe(n);
        const supplySize = TOTAL_SHARES - REMOVED_SHARES - n * HAND_SIZE;
        // Every step pair is one turn; at least one draw per turn is not required
        // (market takes exist) so steps >= 2 * supplySize.
        expect(steps).toBeGreaterThanOrEqual(2 * supplySize);
        expect(totalCoins(state)).toBe(n * STARTING_COINS);
      }
    }
  });

  it('autoAction sells a lone share of a company it is not collecting', () => {
    const s = fixture();
    s.seats[0]!.hand = [card(10, 1), card(11, 1), card(12, 3)];
    s.seats[0]!.portfolio = [card(13, 1)];
    let r = applyAction(s, 0, { type: 'take_supply' }); // takes company 5 (lone, but just taken)
    const a = autoAction(r.state);
    expect(a).toEqual({ type: 'play_market', cardId: 12 }); // company 3 is the lone sellable share
    r = applyAction(r.state, 0, a);
    expect(r.state.market.length).toBe(1);
  });

  it('autoAction always returns a legal action', () => {
    let state = createGame(seats(5), 77, { stepSeconds: 0 });
    for (let i = 0; i < 200 && state.phase !== 'ended'; i++) {
      const a = autoAction(state, (i % 10) / 10);
      expect(isLegal(state, state.active, a)).toBe(true);
      state = applyAction(state, state.active, a).state;
    }
  });

  it('counts consecutive auto-moves per seat and resets on a human action', () => {
    let state = createGame(seats(3), 3, { stepSeconds: 0 });
    const a1 = autoAction(state);
    state = applyAction(state, 0, a1, 0, true).state;
    const a2 = autoAction(state);
    state = applyAction(state, 0, a2, 0, true).state;
    expect(state.seats[0]!.autoMoves).toBe(1);
    // Next time seat 0 plays by hand.
    while (state.active !== 0) state = applyAction(state, state.active, autoAction(state)).state;
    state = applyAction(state, 0, autoAction(state)).state;
    state = applyAction(state, 0, autoAction(state)).state;
    expect(state.seats[0]!.autoMoves).toBe(0);
  });

  it('does not mutate the input state', () => {
    const s = createGame(seats(3), 11);
    const before = JSON.stringify(s);
    applyAction(s, 0, { type: 'take_supply' } as Action);
    expect(JSON.stringify(s)).toBe(before);
  });
});
