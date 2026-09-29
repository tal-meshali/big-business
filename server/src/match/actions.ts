/**
 * Applies actions to the game (from clients, bots and timeouts) and relays
 * the results: per-seat views and animation events. Client OP_ACTION
 * messages are decoded and guarded here so nothing a client sends can throw
 * inside the match loop.
 */
import { applyAction, playerView, RulesError } from '../engine';
import type { Action, GameEvent } from '../engine';
import { MAX_ACTION_BYTES, parseAction } from './input';
import { OP_ACTION, OP_ERROR, OP_EVENTS, OP_VIEW } from './protocol';
import { botThinkMs, label, nowMs, send, type MatchState } from './state';

const AUTO_MOVES_TO_BOT = 3;

export function sendViews(s: MatchState, dispatcher: nkruntime.MatchDispatcher): void {
  if (!s.game) return;
  for (const userId in s.presences) {
    const presence = s.presences[userId];
    if (!presence) continue;
    const seat = s.seatByUser[userId];
    const view = playerView(s.game, seat === undefined ? null : seat);
    send(dispatcher, OP_VIEW, view, [presence]);
  }
}

/** Applies one action for a seat; false when the engine rejects it. */
export function apply(
  s: MatchState,
  dispatcher: nkruntime.MatchDispatcher,
  logger: nkruntime.Logger,
  seat: number,
  action: Action,
  source: 'player' | 'bot' | 'timeout',
): boolean {
  if (!s.game) return false;
  let events: GameEvent[];
  try {
    const result = applyAction(s.game, seat, action, nowMs(), source !== 'player');
    s.game = result.state;
    events = result.events;
  } catch (e) {
    if (e instanceof RulesError) {
      logger.warn('rejected %s from seat %d: %s', action.type, seat, e.message);
      return false;
    }
    throw e;
  }
  // WHY: coins that came with a Market share are not in the action itself; the
  // quest stats read them from the log instead of replaying the game.
  let coins = 0;
  for (const e of events) if (e.type === 'took_market') coins = e.coins;
  s.log.push({ seq: s.game.seq, seat, action, source, coins });

  // A human who keeps timing out becomes a bot for the rest of the game.
  const seatState = s.game.seats[seat];
  if (seatState && !seatState.isBot && seatState.autoMoves >= AUTO_MOVES_TO_BOT) {
    seatState.isBot = true;
    logger.info('seat %d converted to bot after repeated timeouts', seat);
  }

  send(dispatcher, OP_EVENTS, { seq: s.game.seq, events });
  sendViews(s, dispatcher);
  if (s.game.phase === 'ended') {
    s.endedAt = nowMs();
    dispatcher.matchLabelUpdate(label(s));
  } else {
    s.botActAt = nowMs() + botThinkMs(s);
  }
  return true;
}

/**
 * Handles OP_ACTION messages from seated players. Oversized or malformed
 * payloads get OP_ERROR without being applied; engine rejections get
 * OP_ERROR with the action echoed.
 *
 * WHY the try/catch per message: anything thrown here would end the match
 * for everyone at the table, so a client-driven failure is logged and the
 * message dropped instead.
 */
export function handleActions(
  state: MatchState,
  messages: nkruntime.MatchMessage[],
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  logger: nkruntime.Logger,
): void {
  for (const m of messages) {
    if (m.opCode !== OP_ACTION) continue;
    const seat = state.seatByUser[m.sender.userId];
    if (seat === undefined) continue;
    try {
      const tooBig = !m.data || m.data.byteLength > MAX_ACTION_BYTES;
      const action = tooBig ? null : parseAction(nk.binaryToString(m.data));
      if (!action) {
        send(dispatcher, OP_ERROR, { message: 'bad action payload' }, [m.sender]);
        continue;
      }
      const ok = apply(state, dispatcher, logger, seat, action, 'player');
      if (!ok) send(dispatcher, OP_ERROR, { message: 'illegal action', action }, [m.sender]);
    } catch (e) {
      logger.error('action from %s failed: %s', m.sender.userId, String(e));
    }
  }
}
