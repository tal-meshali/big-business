/**
 * Heuristic bot policy for non-tutorial bot seats.
 *
 * One-ply lookahead: every legal action is applied with the pure
 * `applyAction` and the resulting state is scored from the bot's seat by
 * `evaluate`. The bot only uses information its seat can see (its own hand,
 * everyone's portfolio, the Market, coin counts, tokens, the Supply size):
 * the Supply order and other hands are never read.
 *
 * Pure and deterministic for a given (state, tieBreak). ES2016 only, for
 * Nakama's goja runtime. Timeouts and tutorial bots use `autoAction` in
 * game.ts instead (rules-spec section 8).
 */
import { COMPANIES, COMPANY_COUNT, GOLD_VALUE, HAND_SIZE, REMOVED_SHARES, TOTAL_SHARES, type CompanyId } from './companies';
import { applyAction, canTakeMarketCard, drawCost, legalActions, RulesError } from './game';
import type { Action, Card, GameState, Seat } from './types';

/** Scoring weights, in points (1 point = 1 bronze coin at dividend day). */
export const BOT_WEIGHTS = {
  /** A bronze coin in hand is exactly one point at the end. */
  COIN: 1,
  /** Weight of the projected dividend outcome while the Supply is full. */
  PROJECTION_EARLY: 0.6,
  /** Weight of the projected dividend outcome when the Supply is empty. */
  PROJECTION_LATE: 1.0,
  /** Chance of ending as majority holder when 3 behind ... 3 ahead of the best rival, in a fully open company. */
  LEAD_P: [0.02, 0.08, 0.2, 0.4, 0.6, 0.8, 0.95],
  /** Chance of a tie for the most (nobody pays) at the same margins, in a fully open company. */
  TIE_P: [0.03, 0.07, 0.15, 0.2, 0.15, 0.07, 0.03],
  /** Fraction of a company's unseen shares expected to end up in opponents' Portfolios. */
  FUTURE_HOLD: 0.4,
  /** Fraction of those future opponent shares expected to land with the strongest rival. */
  FUTURE_TO_LEADER: 0.5,
  /** Holding a regulator token: free draws for that company's Market shares. */
  TOKEN: 0.5,
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
};

const W = BOT_WEIGHTS;

/**
 * Deterministic heuristic action for the active seat. `tieBreak` in [0,1)
 * chooses among actions that evaluate within `TIE_EPSILON` of the best.
 * Always returns one of `legalActions(state, state.active)`.
 */
export function botAction(state: GameState, tieBreak = 0): Action {
  const seat = state.active;
  const legal = legalActions(state, seat);
  if (legal.length === 0) throw new RulesError('no legal action');
  if (legal.length === 1) return legal[0] as Action;

  const forced = progressAction(state, seat, legal);
  if (forced) return forced;

  let best = -Infinity;
  const scored: Array<{ action: Action; score: number }> = [];
  for (const action of legal) {
    const score = scoreAction(state, seat, action);
    scored.push({ action, score });
    if (score > best) best = score;
  }
  const candidates: Action[] = [];
  for (const s of scored) {
    if (s.score >= best - W.TIE_EPSILON) candidates.push(s.action);
  }
  const pick = Math.min(candidates.length - 1, Math.floor(clamp01(tieBreak) * candidates.length));
  return candidates[pick] as Action;
}

function clamp01(x: number): number {
  if (!(x >= 0)) return 0;
  if (x >= 1) return 0.999999;
  return x;
}

// ---------------------------------------------------------------------------
// Progress guarantee
// ---------------------------------------------------------------------------

function initialSupply(state: GameState): number {
  return TOTAL_SHARES - REMOVED_SHARES - state.seats.length * HAND_SIZE;
}

/**
 * The game only ends when the Supply empties. A table of bots that keep
 * taking from the Market and selling back to it would never draw, so when
 * Market takes run ahead of Supply draws by the stall margin the bot draws if it
 * can, otherwise takes the richest share (gathering coins for a later draw)
 * and plays to its Portfolio (shrinking the Market so draws get cheaper).
 */
function progressAction(state: GameState, seat: number, legal: Action[]): Action | null {
  // WHY: the counts are derived from the state alone (turn number and Supply
  // size) so the policy stays a pure function of (state, tieBreak); a
  // per-bot streak counter would need mutable state outside the engine.
  const draws = initialSupply(state) - state.supply.length;
  const takes = state.turn - 1 - draws;
  // WHY: scaled by seat count because a full table of Market-happy players
  // legitimately takes more often per draw than three players do.
  if (takes - draws < W.STALL_MARGIN_PER_SEAT * state.seats.length) return null;

  if (state.phase === 'take') {
    for (const a of legal) if (a.type === 'take_supply') return a;
    let best: Action | null = null;
    let bestCoins = -1;
    for (const slot of state.market) {
      if (!canTakeMarketCard(state, seat, slot.card) || slot.coins <= bestCoins) continue;
      bestCoins = slot.coins;
      best = { type: 'take_market', cardId: slot.card.id };
    }
    return best;
  }
  // Play step: keep the share, choosing the best Portfolio play by the heuristic.
  let best: Action | null = null;
  let bestScore = -Infinity;
  for (const a of legal) {
    if (a.type !== 'play_portfolio') continue;
    const score = scoreAction(state, seat, a);
    if (score > bestScore) {
      bestScore = score;
      best = a;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// Lookahead
// ---------------------------------------------------------------------------

function scoreAction(state: GameState, seat: number, action: Action): number {
  const next = applyAction(state, seat, action).state;
  if (action.type === 'take_supply') return expectedDrawValue(state, next, seat);
  if (next.phase === 'ended') unreveal(next, state, seat);
  return evaluate(next, seat);
}

/**
 * Value of drawing: the drawn card is hidden information, so the successor
 * state is scored once per company the top card could belong to, weighted by
 * how many shares of that company are still unseen.
 */
function expectedDrawValue(state: GameState, next: GameState, seat: number): number {
  const me = next.seats[seat] as Seat;
  // WHY: applyAction reveals the real top card in the successor hand; drop it
  // so the bot never plays on knowledge a human at the table could not have.
  me.hand.pop();
  const unseen = unseenCounts(state, seat);
  let total = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) total += unseen[c] as number;
  if (total <= 0) return evaluate(next, seat);
  let value = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const n = unseen[c] as number;
    if (n <= 0) continue;
    const fake: Card = { id: -1, company: c as CompanyId };
    me.hand.push(fake);
    value += (n / total) * evaluate(next, seat);
    me.hand.pop();
  }
  return value;
}

/** Shares per company not visible to `seat`: Supply, removed cards and other hands. */
function unseenCounts(state: GameState, seat: number): number[] {
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

/**
 * When the lookahead play ends the game, applyAction reveals every hand and
 * pays dividends. Put the successor back to what the bot may see: other
 * hands stay hidden and coins are pre-dividend, then `evaluate` projects the
 * outcome from visible shares like on any other turn.
 */
function unreveal(next: GameState, before: GameState, seat: number): void {
  for (let s = 0; s < next.seats.length; s++) {
    const cur = next.seats[s] as Seat;
    const prev = before.seats[s] as Seat;
    cur.bronze = prev.bronze;
    cur.gold = prev.gold;
    // WHY: endGame appends each hand to its portfolio in order, so the last
    // `hand.length` portfolio cards of another seat are the ones we may not see.
    if (s !== seat) cur.portfolio.splice(cur.portfolio.length - prev.hand.length, prev.hand.length);
  }
  next.result = null;
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

/** 0 when the Supply is untouched, 1 when it is empty. */
function stageOf(state: GameState): number {
  const initial = initialSupply(state);
  if (initial <= 0) return 1;
  return 1 - Math.min(1, state.supply.length / initial);
}

/**
 * How much a company's standings can still change: the share of its stock
 * nobody at the table can see (Supply, removed cards, other hands), scaled
 * down as the Supply runs out. 0 means the standings are final.
 */
function volatility(company: number, unseen: number[], stage: number): number {
  const shares = (COMPANIES[company] as { shares: number }).shares;
  return ((unseen[company] as number) / shares) * (1 - stage);
}

/** Linear interpolation into a table indexed by margin -3..3. */
function marginTable(table: number[], margin: number): number {
  const x = Math.max(0, Math.min(table.length - 1, margin + 3));
  const i = Math.floor(x);
  const a = table[i] as number;
  const b = table[Math.min(i + 1, table.length - 1)] as number;
  return a + (b - a) * (x - i);
}

/** Chance of holding the majority at the end, `margin` shares ahead of the best rival. */
function leadChance(margin: number, vol: number): number {
  // WHY: with no more shares to come the rules decide it (strictly more
  // wins); the more of the company is still unseen, the softer the odds.
  const hard = margin >= 1 ? 1 : margin <= 0 ? 0 : margin;
  return hard + (marginTable(W.LEAD_P, margin) - hard) * vol;
}

/** Chance of a tie for the most, when nobody pays. */
function tieChance(margin: number, vol: number): number {
  const hard = Math.max(0, 1 - Math.abs(margin));
  return hard + (marginTable(W.TIE_P, margin) - hard) * vol;
}

/**
 * Projected dividend-day gain per seat (coins excluded), from visible
 * shares. A strict leader collects one coin (worth GOLD_VALUE) per share
 * every other holder has; the others pay one bronze per share. Every seat's
 * expectation is weighted by its chance of being the leader at the end.
 */
function projectedScores(counts: number[][], unseen: number[], stage: number): number[] {
  const n = counts.length;
  const proj: number[] = [];
  for (let s = 0; s < n; s++) proj.push(0);
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const vol = volatility(c, unseen, stage);
    const future = futureShares(c, unseen, stage);
    for (let s = 0; s < n; s++) proj[s] = (proj[s] as number) + companyGain(counts, c, s, vol, future);
  }
  return proj;
}

/** Unseen shares of a company expected to reach opponents' Portfolios before the end. */
function futureShares(company: number, unseen: number[], stage: number): number {
  return (unseen[company] as number) * W.FUTURE_HOLD * (1 - stage);
}

/**
 * Projected dividend-day gain of one seat in one company: the chance of
 * holding the majority times the dividend on every other share, minus the
 * chance of paying times the seat's own shares.
 */
function companyGain(counts: number[][], c: number, seat: number, vol: number, future: number): number {
  const k = (counts[seat] as number[])[c] as number;
  if (k === 0) return 0;
  let best = 0;
  let holders = 0;
  for (let s = 0; s < counts.length; s++) {
    const v = (counts[s] as number[])[c] as number;
    holders += v;
    if (s !== seat && v > best) best = v;
  }
  // WHY: a lone share in a company nobody else shows is not safe: the unseen
  // shares will be drawn by somebody, so the rival to beat is measured
  // against what they are expected to collect, not only what is on the table.
  const rival = best + future * W.FUTURE_TO_LEADER;
  const margin = k - rival;
  const income = GOLD_VALUE * (holders + future - k);
  const lead = leadChance(margin, vol);
  const pay = Math.max(0, 1 - lead - tieChance(margin, vol));
  return lead * income - pay * k;
}

/**
 * Expected loss from Market shares an opponent could pick up: for every
 * share and every seat allowed to take it, how much my projected gain in
 * that company drops if that seat adds the share to its Portfolio (which is
 * also what would move the company's token to them). Weighted by how likely
 * each seat is to get there first; the next seat moves before anyone else.
 */
function marketGiftPenalty(state: GameState, counts: number[][], unseen: number[], stage: number, me: number): number {
  const n = state.seats.length;
  const next = (me + 1) % n;
  let penalty = 0;
  for (const slot of state.market) {
    const c = slot.card.company;
    // WHY: only a share of a company I am invested in can hurt me; a share
    // nobody holds gives an opponent a token but costs me nothing.
    if (((counts[me] as number[])[c] as number) === 0) continue;
    const vol = volatility(c, unseen, stage);
    const future = futureShares(c, unseen, stage);
    const now = companyGain(counts, c, me, vol, future);
    for (let j = 0; j < n; j++) {
      if (j === me || !canTakeMarketCard(state, j, slot.card)) continue;
      const row = counts[j] as number[];
      row[c] = (row[c] as number) + 1;
      const loss = now - companyGain(counts, c, me, vol, future);
      row[c] = (row[c] as number) - 1;
      if (loss > 0) penalty += loss * (j === next ? W.GIFT_LEAD_NEXT : W.GIFT_LEAD_OTHER);
    }
  }
  return penalty;
}

/** Coins on Market shares the next seat is allowed to take. */
function marketCoinsForNext(state: GameState, me: number): number {
  const next = (me + 1) % state.seats.length;
  let coins = 0;
  for (const slot of state.market) {
    if (canTakeMarketCard(state, next, slot.card)) coins += slot.coins;
  }
  return coins;
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
  const proj = projectedScores(counts, unseen, stage);
  // WHY: coins are certain but dividends are a projection; trust it more as
  // the Supply runs down and the projection converges on the real result.
  const projW = W.PROJECTION_EARLY + (W.PROJECTION_LATE - W.PROJECTION_EARLY) * stage;
  const total = (s: number): number => {
    const st = state.seats[s] as Seat;
    return st.bronze * W.COIN + st.gold * GOLD_VALUE + projW * (proj[s] as number);
  };
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
  let value = total(me) - (W.RIVAL_MAX * bestOther + (1 - W.RIVAL_MAX) * meanOther);

  let tokens = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) if (state.tokens[c] === me) tokens++;
  value += W.TOKEN * tokens;
  value -= W.DRAW_TAX * drawCost(state, me);
  value -= W.MARKET_GIFT * marketCoinsForNext(state, me);
  value -= projW * marketGiftPenalty(state, counts, unseen, stage, me);
  return value;
}
