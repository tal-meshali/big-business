/**
 * Big Business rules engine. Pure functions over plain data; no Nakama
 * imports, no Date, no global randomness. See docs/design/rules-spec.md.
 *
 * Written for Nakama's goja runtime: ES2016 features only (no
 * structuredClone, Array.prototype.flat, Object.fromEntries, at()).
 */
import {
  COMPANIES,
  COMPANY_COUNT,
  GOLD_VALUE,
  HAND_SIZE,
  MAX_SEATS,
  MIN_SEATS,
  REMOVED_SHARES,
  STARTING_COINS,
  TOTAL_SHARES,
  type CompanyId,
} from './companies';
import { makeRng, shuffle } from './rng';
import type {
  Action,
  ApplyResult,
  Card,
  CompanyDividend,
  DividendResult,
  GameEvent,
  GameOptions,
  GameState,
  MarketSlot,
  Payment,
  Seat,
  SeatScore,
} from './types';

export class RulesError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RulesError';
  }
}

export interface SeatDef {
  id: string;
  name: string;
  isBot: boolean;
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

/** Build the 45-card share set. Card ids are stable across games. */
export function buildDeck(): Card[] {
  const cards: Card[] = [];
  let id = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const company = COMPANIES[c];
    if (!company) continue;
    for (let s = 0; s < company.shares; s++) {
      cards.push({ id: id++, company: company.id });
    }
  }
  return cards;
}

export function createGame(
  seatDefs: SeatDef[],
  seed: number,
  options: Partial<GameOptions> = {},
  now = 0,
): GameState {
  if (seatDefs.length < MIN_SEATS || seatDefs.length > MAX_SEATS) {
    throw new RulesError(`need ${MIN_SEATS}-${MAX_SEATS} seats, got ${seatDefs.length}`);
  }
  const rng = makeRng(seed);
  const deck = shuffle(buildDeck(), rng);
  if (deck.length !== TOTAL_SHARES) throw new RulesError('deck size');

  const removed = deck.splice(0, REMOVED_SHARES);

  // Randomise seat order.
  const order = shuffle(seatDefs.slice(), rng);
  const seats: Seat[] = order.map((d) => ({
    id: d.id,
    name: d.name,
    isBot: d.isBot,
    connected: !d.isBot,
    hand: deck.splice(0, HAND_SIZE),
    portfolio: [],
    bronze: STARTING_COINS,
    gold: 0,
    autoMoves: 0,
  }));

  const state: GameState = {
    seed,
    options: { stepSeconds: options.stepSeconds === undefined ? 30 : options.stepSeconds },
    supply: deck,
    removed,
    market: [],
    seats,
    active: 0,
    phase: 'take',
    turn: 1,
    tookCompany: null,
    tokens: [null, null, null, null, null, null],
    seq: 0,
    deadline: 0,
    result: null,
  };
  state.deadline = nextDeadline(state, now);
  return state;
}

function nextDeadline(state: GameState, now: number): number {
  if (state.options.stepSeconds <= 0 || now <= 0) return 0;
  return now + state.options.stepSeconds * 1000;
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

/** Coins the seat must place onto the market to draw from the supply. */
export function drawCost(state: GameState, seat: number): number {
  let cost = 0;
  for (const slot of state.market) {
    if (state.tokens[slot.card.company] !== seat) cost++;
  }
  return cost;
}

export function canTakeMarketCard(state: GameState, seat: number, card: Card): boolean {
  return state.tokens[card.company] !== seat;
}

function findInHand(seatState: Seat, cardId: number): number {
  for (let i = 0; i < seatState.hand.length; i++) {
    const c = seatState.hand[i];
    if (c && c.id === cardId) return i;
  }
  return -1;
}

function findInMarket(state: GameState, cardId: number): number {
  for (let i = 0; i < state.market.length; i++) {
    const s = state.market[i];
    if (s && s.card.id === cardId) return i;
  }
  return -1;
}

export function legalActions(state: GameState, seat: number): Action[] {
  const out: Action[] = [];
  if (state.phase === 'ended' || seat !== state.active) return out;
  const me = state.seats[seat];
  if (!me) return out;

  if (state.phase === 'take') {
    if (state.supply.length > 0 && me.bronze >= drawCost(state, seat)) {
      out.push({ type: 'take_supply' });
    }
    for (const slot of state.market) {
      if (canTakeMarketCard(state, seat, slot.card)) {
        out.push({ type: 'take_market', cardId: slot.card.id });
      }
    }
  } else {
    for (const card of me.hand) {
      out.push({ type: 'play_portfolio', cardId: card.id });
      if (card.company !== state.tookCompany) {
        out.push({ type: 'play_market', cardId: card.id });
      }
    }
  }
  return out;
}

export function isLegal(state: GameState, seat: number, action: Action): boolean {
  const legal = legalActions(state, seat);
  for (const a of legal) {
    if (a.type !== action.type) continue;
    if (a.type === 'take_supply') return true;
    if ('cardId' in a && 'cardId' in action && a.cardId === action.cardId) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Apply
// ---------------------------------------------------------------------------

/** JSON round-trip clone: plain data only, works in goja. */
export function cloneState(state: GameState): GameState {
  return JSON.parse(JSON.stringify(state)) as GameState;
}

/**
 * Apply an action for a seat. Returns a new state; the input is not mutated.
 * Throws RulesError on an illegal action.
 */
export function applyAction(
  input: GameState,
  seat: number,
  action: Action,
  now = 0,
  auto = false,
): ApplyResult {
  if (!isLegal(input, seat, action)) {
    throw new RulesError(`illegal action ${action.type} for seat ${seat} in phase ${input.phase}`);
  }
  const state = cloneState(input);
  const events: GameEvent[] = [];
  const me = state.seats[seat] as Seat;

  switch (action.type) {
    case 'take_supply': {
      const cost = drawCost(state, seat);
      for (const slot of state.market) {
        if (state.tokens[slot.card.company] !== seat) slot.coins++;
      }
      me.bronze -= cost;
      const card = state.supply.pop() as Card;
      me.hand.push(card);
      state.tookCompany = card.company;
      events.push({ type: 'took_supply', seat, cost });
      break;
    }
    case 'take_market': {
      const idx = findInMarket(state, action.cardId);
      const slot = state.market.splice(idx, 1)[0] as MarketSlot;
      me.bronze += slot.coins;
      me.hand.push(slot.card);
      state.tookCompany = slot.card.company;
      events.push({ type: 'took_market', seat, card: slot.card, coins: slot.coins });
      break;
    }
    case 'play_portfolio': {
      const idx = findInHand(me, action.cardId);
      const card = me.hand.splice(idx, 1)[0] as Card;
      me.portfolio.push(card);
      events.push({ type: 'played', seat, card, to: 'portfolio' });
      break;
    }
    case 'play_market': {
      const idx = findInHand(me, action.cardId);
      const card = me.hand.splice(idx, 1)[0] as Card;
      state.market.push({ card, coins: 0 });
      events.push({ type: 'played', seat, card, to: 'market' });
      break;
    }
  }

  state.seq++;

  if (state.phase === 'take') {
    state.phase = 'play';
    state.deadline = nextDeadline(state, now);
    events.push({ type: 'step', seat, phase: 'play', turn: state.turn });
    return { state, events };
  }

  // End of play step: tokens, then either end the game or advance the turn.
  me.autoMoves = auto ? me.autoMoves + 1 : 0;
  updateTokens(state, events);
  state.tookCompany = null;

  if (state.supply.length === 0) {
    endGame(state, events);
    return { state, events };
  }

  state.active = (state.active + 1) % state.seats.length;
  state.phase = 'take';
  state.turn++;
  state.deadline = nextDeadline(state, now);
  events.push({ type: 'step', seat: state.active, phase: 'take', turn: state.turn });
  return { state, events };
}

export function portfolioCount(seatState: Seat, company: CompanyId): number {
  let n = 0;
  for (const c of seatState.portfolio) if (c.company === company) n++;
  return n;
}

/** Seat with strictly the most portfolio shares of a company, or null. */
export function strictLeader(state: GameState, company: CompanyId): number | null {
  let best = -1;
  let bestCount = 0;
  let tied = false;
  for (let s = 0; s < state.seats.length; s++) {
    const n = portfolioCount(state.seats[s] as Seat, company);
    if (n > bestCount) {
      bestCount = n;
      best = s;
      tied = false;
    } else if (n === bestCount && n > 0) {
      tied = true;
    }
  }
  if (best < 0 || tied) return null;
  return best;
}

function updateTokens(state: GameState, events: GameEvent[]): void {
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const company = c as CompanyId;
    const leader = strictLeader(state, company);
    const holder = state.tokens[company];
    if (leader !== null && leader !== holder) {
      state.tokens[company] = leader;
      events.push({ type: 'token_moved', company, from: holder === undefined ? null : holder, to: leader });
    }
  }
}

// ---------------------------------------------------------------------------
// End of game and dividends
// ---------------------------------------------------------------------------

function endGame(state: GameState, events: GameEvent[]): void {
  const hands: Card[][] = [];
  for (const s of state.seats) {
    hands.push(s.hand.slice());
    for (const c of s.hand) s.portfolio.push(c);
    s.hand = [];
  }
  events.push({ type: 'hands_revealed', hands });
  state.phase = 'ended';
  state.deadline = 0;
  state.result = computeDividends(state);
  events.push({ type: 'game_ended', result: state.result });
}

/**
 * Simultaneous dividend resolution per rules-spec section 6. Mutates seat
 * coin counts and returns the breakdown.
 */
export function computeDividends(state: GameState): DividendResult {
  const n = state.seats.length;
  const companies: CompanyDividend[] = [];
  // owed[from][to]
  const owed: number[][] = [];
  for (let i = 0; i < n; i++) {
    const row: number[] = [];
    for (let j = 0; j < n; j++) row.push(0);
    owed.push(row);
  }

  for (let c = 0; c < COMPANY_COUNT; c++) {
    const company = c as CompanyId;
    const majority = strictLeader(state, company);
    const payments: Payment[] = [];
    if (majority !== null) {
      for (let s = 0; s < n; s++) {
        if (s === majority) continue;
        const shares = portfolioCount(state.seats[s] as Seat, company);
        if (shares > 0) {
          payments.push({ from: s, to: majority, coins: shares });
          (owed[s] as number[])[majority] = ((owed[s] as number[])[majority] as number) + shares;
        }
      }
    }
    companies.push({ company, majority, payments });
  }

  // Pay from bronze only, using pre-dividend balances; shortfalls are
  // resolved in creditor (seat) order, one coin at a time.
  const received: number[] = [];
  for (let i = 0; i < n; i++) received.push(0);
  for (let from = 0; from < n; from++) {
    const seat = state.seats[from] as Seat;
    let budget = seat.bronze;
    const row = owed[from] as number[];
    let remaining = 0;
    for (let to = 0; to < n; to++) remaining += row[to] as number;
    while (remaining > 0 && budget > 0) {
      for (let to = 0; to < n && budget > 0; to++) {
        if ((row[to] as number) > 0) {
          row[to] = (row[to] as number) - 1;
          remaining--;
          budget--;
          received[to] = (received[to] as number) + 1;
        }
      }
    }
    seat.bronze = budget;
  }
  for (let i = 0; i < n; i++) {
    (state.seats[i] as Seat).gold += received[i] as number;
  }

  // Scores and ranks. Tie-breaks: more gold, then fewer portfolio shares.
  const scores: SeatScore[] = state.seats.map((s, i) => ({
    seat: i,
    bronze: s.bronze,
    gold: s.gold,
    score: s.bronze + s.gold * GOLD_VALUE,
    rank: 0,
  }));
  const order = scores.slice().sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if (b.gold !== a.gold) return b.gold - a.gold;
    const pa = (state.seats[a.seat] as Seat).portfolio.length;
    const pb = (state.seats[b.seat] as Seat).portfolio.length;
    return pa - pb;
  });
  let rank = 0;
  for (let i = 0; i < order.length; i++) {
    const cur = order[i] as SeatScore;
    const prev = order[i - 1];
    const sameAsPrev =
      prev !== undefined &&
      prev.score === cur.score &&
      prev.gold === cur.gold &&
      (state.seats[prev.seat] as Seat).portfolio.length === (state.seats[cur.seat] as Seat).portfolio.length;
    if (!sameAsPrev) rank = i + 1;
    cur.rank = rank;
  }
  return { companies, scores };
}

// ---------------------------------------------------------------------------
// Invariants (used by tests and optionally by the match loop in debug)
// ---------------------------------------------------------------------------

export function totalCoins(state: GameState): number {
  let n = 0;
  for (const s of state.seats) n += s.bronze + s.gold;
  for (const m of state.market) n += m.coins;
  return n;
}

export function totalCards(state: GameState): number {
  let n = state.supply.length + state.removed.length + state.market.length;
  for (const s of state.seats) n += s.hand.length + s.portfolio.length;
  return n;
}
