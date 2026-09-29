/**
 * Simple auto-move policy (rules-spec section 8.1): plays for a human whose
 * step timer runs out and for the tutorial's bots. Real-game bots use the
 * heuristic bot in bot.ts.
 *
 * Written for Nakama's goja runtime: ES2016 features only.
 */
import { COMPANIES, type CompanyId } from './companies';
import { canTakeMarketCard, drawCost, legalActions, portfolioCount, RulesError } from './game';
import type { Action, Card, GameState, MarketSlot, Seat } from './types';

function heldCount(seatState: Seat, company: CompanyId): number {
  let n = portfolioCount(seatState, company);
  for (const c of seatState.hand) if (c.company === company) n++;
  return n;
}

/**
 * Deterministic default action for the active seat. `tieBreak` in [0,1)
 * varies the choice between equally ranked options; timeouts and the
 * tutorial pass 0.
 */
export function autoAction(state: GameState, tieBreak = 0): Action {
  const seat = state.active;
  const me = state.seats[seat] as Seat;
  const legal = legalActions(state, seat);
  if (legal.length === 0) throw new RulesError('no legal action');

  if (state.phase === 'take') {
    const cost = drawCost(state, seat);
    const canDraw = state.supply.length > 0 && me.bronze >= cost;
    const takeable: MarketSlot[] = [];
    for (const slot of state.market) {
      if (canTakeMarketCard(state, seat, slot.card)) takeable.push(slot);
    }
    const bestMarket = (): MarketSlot | null => {
      let best: MarketSlot | null = null;
      let bestScore = -1;
      for (const slot of takeable) {
        const score = slot.coins * 100 + heldCount(me, slot.card.company) * 10 + Math.floor(tieBreak * 10);
        if (score > bestScore) {
          bestScore = score;
          best = slot;
        }
      }
      return best;
    };
    const rich = bestMarket();
    if (rich && rich.coins >= 2) return { type: 'take_market', cardId: rich.card.id };
    if (canDraw && cost <= 1) return { type: 'take_supply' };
    if (rich) return { type: 'take_market', cardId: rich.card.id };
    if (canDraw) return { type: 'take_supply' };
    return legal[0] as Action;
  }

  // Play step. A pair (or more) of one company goes to the Portfolio first,
  // the company we hold most of; tie -> larger company.
  // WHY: selling every lone share first meant tutorial bots sold on each of
  // their first three turns, which learners read as "bots never keep". The
  // rule waits for a non-empty Market so the tutorial's opening still shows a
  // bot selling, the next one paying onto that share, and the learner taking
  // it with its coins (coach steps bot_paid and take_with_coins).
  if (state.market.length > 0) {
    let pair: Card | null = null;
    let pairScore = -1;
    for (const card of me.hand) {
      const held = heldCount(me, card.company);
      if (held < 2) continue;
      const company = COMPANIES[card.company];
      const score = held * 100 + (company ? company.shares : 0);
      if (score > pairScore) {
        pairScore = score;
        pair = card;
      }
    }
    if (pair) return { type: 'play_portfolio', cardId: pair.id };
  }
  // Minority shares cost coins on dividend day, so a lone share of a company
  // we are not collecting is sold to the Market (when allowed and the Market
  // is not crowded). Otherwise keep the company we hold most of; tie -> larger
  // company.
  if (state.market.length < 4) {
    let dump: Card | null = null;
    for (const card of me.hand) {
      if (card.company === state.tookCompany) continue;
      if (heldCount(me, card.company) === 1 && (dump === null || card.company < dump.company)) dump = card;
    }
    if (dump) return { type: 'play_market', cardId: dump.id };
  }
  let best: Card | null = null;
  let bestScore = -1;
  for (const card of me.hand) {
    const company = COMPANIES[card.company];
    const score = heldCount(me, card.company) * 100 + (company ? company.shares : 0) + Math.floor(tieBreak * 3);
    if (score > bestScore) {
      bestScore = score;
      best = card;
    }
  }
  if (best) return { type: 'play_portfolio', cardId: best.id };
  return legal[0] as Action;
}
