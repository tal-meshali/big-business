/**
 * Evaluation for the bot policy: scores a state from one seat using only
 * what that seat can see. The search in bot.ts calls `evaluate`; the
 * weights live here so both files share them. ES2016 only (goja).
 */
import { COMPANIES, COMPANY_COUNT, GOLD_VALUE, HAND_SIZE, REMOVED_SHARES, TOTAL_SHARES } from './companies';
import { canTakeMarketCard, drawCost } from './game';
import type { Card, GameState, Seat } from './types';

/** Scoring weights, in points (1 point = 1 bronze coin at dividend day). */
export const BOT_WEIGHTS = {
  /** A bronze coin in hand is exactly one point at the end. */
  COIN: 1,
  /** Weight of the projected dividend outcome while the Supply is full. */
  PROJECTION_EARLY: 0.6,
  /** Weight of the projected dividend outcome when the Supply is empty. */
  PROJECTION_LATE: 1.0,
  /** Fraction of a company's unseen shares (Supply, removed cards, hidden hands) expected to end up in some Portfolio. */
  FUTURE_HOLD: 0.7,
  /** Fraction of a hand share's minority liability that is charged while it can still be sold (1 = as if in the Portfolio). */
  HAND_KEEP: 0,
  /** My remaining turns below which hand shares count as kept (they can no longer all be sold). */
  SHED_TURNS: 3,
  /** Holding a regulator token: free draws for that company's Market shares. */
  TOKEN: 0.5,
  /** Per opponent, the cost of a token blocking me from taking a share of a company I collect. */
  TOKEN_BLOCK: 0.2,
  /** Cost of each lone hand share beyond CLUTTER_FREE, at four opponents (they take a play each to sell). */
  CLUTTER: 0.4,
  /** Lone hand shares that are not charged (one can be sold next turn). */
  CLUTTER_FREE: 1,
  /** Each Market share I would have to pay for on my next draw. */
  DRAW_TAX: 0.25,
  /** Coins sitting on Market shares the next seat may take. */
  MARKET_GIFT: 0.4,
  /** Chance the next seat takes a Market share that improves its standing against me. */
  GIFT_LEAD_NEXT: 0.8,
  /** The same for any later seat (they may not get there first). */
  GIFT_LEAD_OTHER: 0.3,
  /** How much the strongest opponent counts against the average opponent (1 = only the leader matters). */
  RIVAL_MAX: 0.7,
  /** Actions scoring within this margin of the best are tie-broken by `tieBreak`. */
  TIE_EPSILON: 0.05,
  /** Market takes may exceed Supply draws (game-wide) by this many per seat before the bot insists on drawing. */
  STALL_MARGIN_PER_SEAT: 3,
  /**
   * 1: a take is scored by the best play that can follow it; 0: by the state
   * right after the take. WHY off: measured no gain over the reply search
   * alone (35.0% vs 36.7% rank-1 at 5 seats) at four times the cost.
   */
  OWN_TURN_SEARCH: 0,
  /**
   * 1: a play is scored after the next seat's most likely take; 0: right
   * after the play. WHY on: 30.7% -> 36.7% rank-1 at 5 seats against the
   * auto-move (300 games), 66.7% -> 67.9% at 3 seats, 1.3 ms worst case.
   */
  REPLY_SEARCH: 1,
};

const W = BOT_WEIGHTS;

export function initialSupply(state: GameState): number {
  return TOTAL_SHARES - REMOVED_SHARES - state.seats.length * HAND_SIZE;
}

/** Shares per company not visible to `seat`: Supply, removed cards and other hands. */
export function unseenCounts(state: GameState, seat: number): number[] {
  const out: number[] = [];
  for (let c = 0; c < COMPANY_COUNT; c++) out.push((COMPANIES[c] as { shares: number }).shares);
  const seen = (card: Card): void => {
    out[card.company] = (out[card.company] as number) - 1;
  };
  for (let s = 0; s < state.seats.length; s++) {
    const st = state.seats[s] as Seat;
    for (const card of st.portfolio) seen(card);
    if (s === seat) for (const card of st.hand) seen(card);
  }
  for (const slot of state.market) seen(slot.card);
  return out;
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

/** Visible share counts per seat and company; the evaluating seat includes its hand. */
function visibleCounts(state: GameState, me: number): number[][] {
  const counts: number[][] = [];
  for (let s = 0; s < state.seats.length; s++) {
    const row: number[] = [];
    for (let c = 0; c < COMPANY_COUNT; c++) row.push(0);
    const st = state.seats[s] as Seat;
    for (const card of st.portfolio) row[card.company] = (row[card.company] as number) + 1;
    if (s === me) for (const card of st.hand) row[card.company] = (row[card.company] as number) + 1;
    counts.push(row);
  }
  return counts;
}

/** Shares per company in the seat's hand. */
function handCounts(state: GameState, seat: number): number[] {
  const out: number[] = [];
  for (let c = 0; c < COMPANY_COUNT; c++) out.push(0);
  for (const card of (state.seats[seat] as Seat).hand) out[card.company] = (out[card.company] as number) + 1;
  return out;
}

/** 0 when the Supply is untouched, 1 when it is empty. */
function stageOf(state: GameState): number {
  const initial = initialSupply(state);
  if (initial <= 0) return 1;
  return 1 - Math.min(1, state.supply.length / initial);
}

/**
 * Projected dividend-day gain per seat (coins excluded), from visible
 * shares. A strict leader collects one coin (worth GOLD_VALUE) per share
 * every other holder has; the others pay one bronze per share. Every seat's
 * expectation is weighted by its chance of being the leader at the end.
 */
function projectedScores(counts: number[][], additions: number[][], me: number, hand: number[], handKeep: number): number[] {
  const n = counts.length;
  const proj: number[] = [];
  for (let s = 0; s < n; s++) proj.push(0);
  for (let c = 0; c < COMPANY_COUNT; c++) {
    for (let s = 0; s < n; s++) {
      proj[s] = (proj[s] as number) + companyGain(counts, c, s, me, additions, s === me ? (hand[c] as number) : 0, handKeep);
    }
  }
  return proj;
}

/**
 * Expected shares per seat and company still to reach that seat's
 * Portfolio, as seen by `me`: the company's unseen cards (Supply, removed
 * cards and the hidden hands, which join their Portfolios at the end at
 * the latest) that will end in some Portfolio, shared out evenly. My own
 * row is empty: my hand is in `counts`, and what I add later is decided
 * by the search, not assumed. WHY: weighting the split towards the seats
 * that already collect a company, or crediting my own future pickups,
 * both measured worse (the bot hoards or gives up on contested companies).
 */
function expectedAdditions(seats: number, unseen: number[]): number[][] {
  const add: number[][] = [];
  for (let s = 0; s < seats; s++) {
    const row: number[] = [];
    for (let c = 0; c < COMPANY_COUNT; c++) row.push(((unseen[c] as number) * W.FUTURE_HOLD) / seats);
    add.push(row);
  }
  return add;
}

/**
 * Chance that a Poisson variable with the given mean is at most `t`. A
 * fractional `t` interpolates between the two whole thresholds; a negative
 * `t` is impossible. With mean 0 this is exact (1 or 0).
 */
function poissonAtMost(mean: number, t: number): number {
  if (t < 0) return 0;
  const lo = Math.floor(t);
  let term = Math.exp(-mean);
  let atLo = term;
  for (let i = 1; i <= lo; i++) {
    term *= mean / i;
    atLo += term;
  }
  const frac = t - lo;
  if (frac <= 0) return Math.min(1, atLo);
  const atHi = atLo + (term * mean) / (lo + 1);
  return Math.min(1, atLo + (atHi - atLo) * frac);
}

/**
 * Projected dividend-day gain of one seat in one company. The company's
 * unseen shares (Supply, removed cards, hidden hands) mostly end up in
 * somebody's Portfolio; they are shared out in proportion to what each seat
 * already shows, and each rival's extra shares are modelled as a Poisson
 * count. WHY: the majority is decided against every rival separately, so
 * the chance of a strict lead is the product over rivals; that is what
 * makes a thin lead worth much less at a full table than with two rivals,
 * and it stays soft while hands are hidden (the old margin tables hardened
 * to certainty as the Supply emptied, although 3 cards per rival were
 * still unknown). With nothing unseen it is the exact "strictly more" rule.
 */
function companyGain(
  counts: number[][],
  c: number,
  seat: number,
  me: number,
  additions: number[][],
  inHand: number,
  handKeep: number,
): number {
  const k = (counts[seat] as number[])[c] as number;
  if (k === 0) return 0;
  const n = counts.length;
  const mine = k;
  let lead = 1;
  let leadOrTie = 1;
  let rivalShares = 0;
  for (let s = 0; s < n; s++) {
    if (s === seat) continue;
    const v = (counts[s] as number[])[c] as number;
    const mean = (additions[s] as number[])[c] as number;
    rivalShares += v + mean;
    lead *= poissonAtMost(mean, mine - 1 - v);
    leadOrTie *= poissonAtMost(mean, mine - v);
  }
  const pay = 1 - leadOrTie;
  const income = GOLD_VALUE * rivalShares;
  // WHY: a share still in hand can be sold before it costs anything, so
  // only part of its minority liability is charged.
  const liable = mine - inHand * (1 - handKeep);
  return lead * income - pay * liable;
}

/**
 * Expected loss from Market shares an opponent could pick up: for every
 * share and every seat allowed to take it, how much my projected gain in
 * that company drops if that seat adds the share to its Portfolio (which is
 * also what would move the company's token to them). Weighted by how likely
 * each seat is to get there first; the next seat moves before anyone else.
 */
function marketGiftPenalty(
  state: GameState,
  counts: number[][],
  additions: number[][],
  hand: number[],
  handKeep: number,
  me: number,
  next: number,
): number {
  const n = state.seats.length;
  let penalty = 0;
  for (const slot of state.market) {
    const c = slot.card.company;
    // WHY: only a share of a company I am invested in can hurt me; a share
    // nobody holds gives an opponent a token but costs me nothing.
    if (((counts[me] as number[])[c] as number) === 0) continue;
    const now = companyGain(counts, c, me, me, additions, hand[c] as number, handKeep);
    for (let j = 0; j < n; j++) {
      if (j === me || !canTakeMarketCard(state, j, slot.card)) continue;
      const row = counts[j] as number[];
      row[c] = (row[c] as number) + 1;
      const loss = now - companyGain(counts, c, me, me, additions, hand[c] as number, handKeep);
      row[c] = (row[c] as number) - 1;
      if (loss > 0) penalty += loss * (j === next ? W.GIFT_LEAD_NEXT : W.GIFT_LEAD_OTHER);
    }
  }
  return penalty;
}

/** Coins on Market shares the given seat is allowed to take. */
function marketCoinsFor(state: GameState, seat: number): number {
  let coins = 0;
  for (const slot of state.market) {
    if (canTakeMarketCard(state, seat, slot.card)) coins += slot.coins;
  }
  return coins;
}

/** The seat that takes from the Market next in this state (never `me` unless alone). */
function nextTaker(state: GameState, me: number): number {
  const n = state.seats.length;
  // WHY: after a reply is simulated the acting seat is no longer me; the
  // seat about to take is the active one in a take step, else its successor.
  const next = state.phase === 'take' ? state.active : (state.active + 1) % n;
  return next === me ? (me + 1) % n : next;
}

/**
 * Score a state from `me`'s seat: my projected result minus the strongest
 * opponent's (blended with the average opponent), plus token, draw-cost and
 * Market danger terms that the projection does not capture.
 */
export function evaluate(state: GameState, me: number): number {
  const stage = stageOf(state);
  const counts = visibleCounts(state, me);
  const unseen = unseenCounts(state, me);
  const hand = handCounts(state, me);
  // WHY: a hand share can still be sold, one per turn, until my turns run
  // out; at the end every hand share joins the Portfolio and pays like one.
  const turnsLeft = state.supply.length / state.seats.length;
  const handKeep = 1 - (1 - W.HAND_KEEP) * Math.min(1, turnsLeft / W.SHED_TURNS);
  const additions = expectedAdditions(state.seats.length, unseen);
  const proj = projectedScores(counts, additions, me, hand, handKeep);
  const next = nextTaker(state, me);
  // WHY: coins are certain but dividends are a projection; trust it more as
  // the Supply runs down and the projection converges on the real result.
  const projW = W.PROJECTION_EARLY + (W.PROJECTION_LATE - W.PROJECTION_EARLY) * stage;
  const total = (s: number): number => {
    const st = state.seats[s] as Seat;
    return st.bronze * W.COIN + st.gold * GOLD_VALUE + projW * (proj[s] as number);
  };
  const mine = total(me);
  let bestOther = -Infinity;
  let sumOther = 0;
  for (let s = 0; s < state.seats.length; s++) {
    if (s === me) continue;
    const t = total(s);
    sumOther += t;
    if (t > bestOther) bestOther = t;
  }
  // WHY: the game is won on rank, so the leading opponent matters most, but
  // at a full table chasing only the leader ignores the seats about to pass us.
  const meanOther = sumOther / (state.seats.length - 1);
  let value = mine - (W.RIVAL_MAX * bestOther + (1 - W.RIVAL_MAX) * meanOther);

  for (let c = 0; c < COMPANY_COUNT; c++) {
    if (state.tokens[c] !== me) continue;
    value += W.TOKEN;
    // WHY: the token forbids taking that company's shares from the Market,
    // which is how a collector gets them at a full table: every opponent
    // between my turns may sell one that I then cannot pick up.
    if (((counts[me] as number[])[c] as number) > 0) value -= W.TOKEN_BLOCK * (state.seats.length - 1);
  }
  value -= W.DRAW_TAX * drawCost(state, me);
  // WHY: a hand share of a company I hold nothing else of is not free even
  // while it carries no liability: it costs a play to sell (one per turn),
  // so a hand that clogs up with them stops growing the Portfolio. The first
  // one can go next turn; every further one is charged.
  let clutter = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) {
    if ((hand[c] as number) > 0 && ((counts[me] as number[])[c] as number) === (hand[c] as number) && (hand[c] as number) === 1) clutter++;
  }
  // The cost grows with the opponents between my turns: they refill the
  // Market with singles, so a cluttered hand keeps trading instead of building.
  value -= (W.CLUTTER * (state.seats.length - 1) / 4) * Math.max(0, clutter - W.CLUTTER_FREE);
  value -= W.MARKET_GIFT * marketCoinsFor(state, next);
  value -= projW * marketGiftPenalty(state, counts, additions, hand, handKeep, me, next);
  return value;
}
