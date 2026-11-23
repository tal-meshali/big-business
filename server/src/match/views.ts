/** Sends each connected player the view of the game its seat may see. */
import { playerView } from '../engine';
import { OP_EARNINGS, OP_VIEW, type ViewMessage } from './protocol';
import { nowMs, send, type MatchState } from './state';

export function sendViews(s: MatchState, dispatcher: nkruntime.MatchDispatcher): void {
  if (!s.game) return;
  const startsInMs = Math.max(0, s.playStartsAt - nowMs());
  for (const userId in s.presences) {
    const presence = s.presences[userId];
    if (!presence) continue;
    const seat = s.seatByUser[userId];
    const view = playerView(s.game, seat === undefined ? null : seat) as ViewMessage;
    view.startsInMs = startsInMs;
    // WHY: nobody may act during the get-ready countdown, so clients wait
    // on an empty legal list instead of sending moves that get rejected.
    if (startsInMs > 0) {
      view.legal = [];
      view.drawCost = null;
    }
    send(dispatcher, OP_VIEW, view, [presence]);
  }
}

/**
 * Sends each connected player the earnings receipt of the finished game:
 * to everyone once the awards are written, or to `only` (a player who came
 * back while the result is still up).
 */
export function sendEarnings(s: MatchState, dispatcher: nkruntime.MatchDispatcher, only?: nkruntime.Presence[]): void {
  const targets = only || Object.keys(s.presences).map((userId) => s.presences[userId]);
  for (const presence of targets) {
    if (!presence) continue;
    const earnings = s.earnings[presence.userId];
    if (earnings) send(dispatcher, OP_EARNINGS, earnings, [presence]);
  }
}
