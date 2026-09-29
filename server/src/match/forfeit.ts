/**
 * Forfeits: a player gives up mid-game. A bot plays the seat to the end, the
 * player cannot rejoin it, and it counts as a game played with no XP.
 */
import { OP_FORFEIT, OP_FORFEITED } from './protocol';
import { awardForfeit } from './awards';
import { botThinkMs, send, type MatchState } from './state';
import { sendViews } from './views';

export function handleForfeits(
  state: MatchState,
  messages: nkruntime.MatchMessage[],
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  dispatcher: nkruntime.MatchDispatcher,
  now: number,
): void {
  const game = state.game;
  if (!game || game.phase === 'ended') return;
  for (const m of messages) {
    if (m.opCode !== OP_FORFEIT) continue;
    const userId = m.sender.userId;
    const seat = state.seatByUser[userId];
    const seatState = seat === undefined ? undefined : game.seats[seat];
    if (seat === undefined || !seatState) continue;
    // WHY: without a seatByUser entry the user's actions are ignored and
    // matchJoinAttempt refuses a rejoin, so the bot keeps the seat.
    delete state.seatByUser[userId];
    state.forfeited[userId] = true;
    seatState.isBot = true;
    seatState.connected = false;
    if (seat === game.active) state.botActAt = now + botThinkMs(state);
    awardForfeit(nk, logger, userId);
    logger.info('user %s forfeited seat %d', userId, seat);
    send(dispatcher, OP_FORFEITED, { seat });
    sendViews(state, dispatcher);
  }
}
