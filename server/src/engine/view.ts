/**
 * Per-seat views (rules-spec section 10): what one client may see. The match
 * handler sends these, and the heuristic bot decides from one, so hidden
 * information stays out of both.
 *
 * Written for Nakama's goja runtime: ES2016 features only.
 */
import { COMPANY_COUNT, type CompanyId } from './companies';
import { drawCost, legalActions } from './game';
import type { GameState, PlayerView, SeatView } from './types';

/** Build what one seat (or a spectator, seat = null) may see. */
export function playerView(state: GameState, viewer: number | null): PlayerView {
  const ended = state.phase === 'ended';
  const seats: SeatView[] = state.seats.map((s, i) => {
    const tokens: CompanyId[] = [];
    for (let c = 0; c < COMPANY_COUNT; c++) {
      if (state.tokens[c] === i) tokens.push(c as CompanyId);
    }
    const view: SeatView = {
      id: s.id,
      name: s.name,
      isBot: s.isBot,
      connected: s.connected,
      handCount: s.hand.length,
      portfolio: s.portfolio.slice(),
      bronze: s.bronze,
      gold: s.gold,
      tokens,
    };
    if (i === viewer || ended) view.hand = s.hand.slice();
    return view;
  });
  const myTake = viewer !== null && viewer === state.active && state.phase === 'take';
  return {
    you: viewer,
    seats,
    market: state.market.map((m) => ({ card: m.card, coins: m.coins })),
    supplyCount: state.supply.length,
    removedCount: state.removed.length,
    active: state.active,
    phase: state.phase,
    turn: state.turn,
    tookCompany: state.tookCompany,
    tokens: state.tokens.slice(),
    seq: state.seq,
    deadline: state.deadline,
    drawCost: myTake ? drawCost(state, viewer as number) : null,
    legal: viewer === null ? [] : legalActions(state, viewer),
    result: state.result,
  };
}
