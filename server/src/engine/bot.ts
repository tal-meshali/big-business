/**
 * Heuristic bot policy for non-tutorial bot seats.
 *
 * Lookahead: every legal action is applied with the pure `applyAction`; a
 * play is followed by the next seat's most likely take (see
 * `valueAfterReply`), and the resulting state is scored from the bot's seat
 * by `evaluate`. The bot only uses information its seat can see (its own
 * hand, everyone's portfolio, the Market, coin counts, tokens, the Supply
 * size): the Supply order and other hands are never read.
 *
 * Pure and deterministic for a given (state, tieBreak). ES2016 only, for
 * Nakama's goja runtime. Timeouts and tutorial bots use `autoAction` in
 * game.ts instead (rules-spec section 8).
 */
import { COMPANY_COUNT, type CompanyId } from './companies';
import { BOT_WEIGHTS, evaluate, initialSupply, unseenCounts } from './bot_eval';
import { applyAction, canTakeMarketCard, cloneState, legalActions, RulesError } from './game';

export { BOT_WEIGHTS, evaluate } from './bot_eval';

const W = BOT_WEIGHTS;
import type { Action, Card, GameState, Seat } from './types';

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

/**
 * Score one of my actions. Take step: the take is followed by my best play
 * (the two steps of a turn are one decision: what I take decides what I may
 * sell). Play step: the play is followed by the next seat's most likely
 * take, then the state is scored from my seat.
 */
function scoreAction(state: GameState, seat: number, action: Action): number {
  if (state.phase === 'take') return scoreTake(state, seat, action);
  return scorePlay(state, seat, action, W.REPLY_SEARCH > 0);
}

function scoreTake(state: GameState, seat: number, action: Action): number {
  const next = applyAction(state, seat, action).state;
  const score = (s: GameState): number => (W.OWN_TURN_SEARCH > 0 ? bestPlayValue(s, seat) : evaluate(s, seat));
  if (action.type === 'take_supply') return expectedDrawValue(state, next, seat, score);
  return score(next);
}

/** Best value over my legal plays in a play-step state (the hand may hold a fake drawn card). */
function bestPlayValue(state: GameState, seat: number): number {
  let best = -Infinity;
  for (const play of legalActions(state, seat)) {
    // WHY: the reply search is skipped under a take: it multiplies the work
    // by the reply count for every play of every possible take, and the take
    // decision mostly needs to know which play the take allows.
    const v = scorePlay(state, seat, play, false);
    if (v > best) best = v;
  }
  return best;
}

function scorePlay(state: GameState, seat: number, action: Action, withReply: boolean): number {
  const next = applyAction(state, seat, action).state;
  if (next.phase === 'ended') {
    unreveal(next, state, seat);
    return evaluate(next, seat);
  }
  if (!withReply) return evaluate(next, seat);
  return valueAfterReply(next, seat);
}

/**
 * Score a state at the next seat's take step from my seat, after that seat
 * makes the take its own one-ply evaluation prefers. WHY: with four
 * opponents between my turns the Market is picked over before I move
 * again, so what I leave there is scored by what the next seat does with
 * it, not by what it looks like now.
 */
function valueAfterReply(state: GameState, me: number): number {
  const rival = state.active;
  // WHY: the reply is chosen from what the rival can see, and I cannot see
  // its hand, so the search runs on a copy where that hand is empty.
  const view = cloneState(state);
  (view.seats[rival] as Seat).hand = [];
  const replies = legalActions(view, rival);
  if (replies.length === 0) return evaluate(view, me);
  let bestReply: Action = replies[0] as Action;
  let bestValue = -Infinity;
  for (const reply of replies) {
    const after = applyAction(view, rival, reply).state;
    const v = reply.type === 'take_supply' ? expectedDrawValue(view, after, rival, (s) => evaluate(s, rival)) : evaluate(after, rival);
    if (v > bestValue) {
      bestValue = v;
      bestReply = reply;
    }
  }
  let after = applyAction(view, rival, bestReply).state;
  if (bestReply.type === 'take_market') {
    // WHY: a share taken from the Market goes into a hand I cannot see; it
    // surfaces in that Portfolio at the latest when hands are revealed, so it
    // is counted there now (the same-company rule forbids selling it back).
    const beforePlay = after;
    after = applyAction(after, rival, { type: 'play_portfolio', cardId: bestReply.cardId }).state;
    if (after.phase === 'ended') unreveal(after, beforePlay, rival);
  }
  return evaluate(after, me);
}

/** Card id of the unknown drawn card in the lookahead; no real card has it. */
const FAKE_CARD_ID = -1;

/**
 * Value of drawing: the drawn card is hidden information, so the successor
 * state is scored once per company the top card could belong to, weighted by
 * how many shares of that company are still unseen.
 */
function expectedDrawValue(state: GameState, next: GameState, seat: number, score: (s: GameState) => number): number {
  const me = next.seats[seat] as Seat;
  // WHY: applyAction reveals the real top card in the successor hand; drop it
  // so the bot never plays on knowledge a human at the table could not have.
  me.hand.pop();
  const unseen = unseenCounts(state, seat);
  let total = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) total += unseen[c] as number;
  if (total <= 0) return score(next);
  let value = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const n = unseen[c] as number;
    if (n <= 0) continue;
    const fake: Card = { id: FAKE_CARD_ID, company: c as CompanyId };
    me.hand.push(fake);
    next.tookCompany = fake.company;
    value += (n / total) * score(next);
    me.hand.pop();
  }
  return value;
}

/**
 * When a lookahead play ends the game, applyAction reveals every hand and
 * pays dividends. Put the successor back to what may be seen: every hand
 * but the acting seat's stays hidden and coins are pre-dividend, then
 * `evaluate` projects the outcome from visible shares like on any other turn.
 */
function unreveal(next: GameState, before: GameState, actor: number): void {
  for (let s = 0; s < next.seats.length; s++) {
    const cur = next.seats[s] as Seat;
    const prev = before.seats[s] as Seat;
    cur.bronze = prev.bronze;
    cur.gold = prev.gold;
    // WHY: endGame appends each hand to its portfolio in order, so the last
    // `hand.length` portfolio cards of another seat are the ones we may not see.
    if (s !== actor) cur.portfolio.splice(cur.portfolio.length - prev.hand.length, prev.hand.length);
  }
  next.result = null;
}
