/**
 * Nakama authoritative match handler for Big Business.
 *
 * The handler owns a GameState from the pure engine and is the only place the
 * deck is shuffled or scored. Clients send intents (OP_ACTION) and receive a
 * per-seat PlayerView (OP_VIEW) plus animation events (OP_EVENTS). Applying
 * actions and decoding client messages live in actions.ts and emotes.ts.
 */
import { autoAction, botAction, createGame, type SeatDef } from '../engine';
import { BOT_NAMES, clampStepSeconds, DEFAULT_PARAMS, OP_ACTION, OP_ERROR, OP_LOBBY, OP_READY, type MatchParams } from './protocol';
import { apply, handleActions } from './actions';
import { awardProgress } from './awards';
import { handleEmotes } from './emotes';
import { handleForfeits } from './forfeit';
import { botThinkMs, GET_READY_MS, label, lobbyJoinError, lobbyMessage, nowMs, send, type MatchState } from './state';
import { chooseRoomDeck, sendDeck } from './room_deck';
import { pushTurnIfAway } from './turn_push';
import { sendViews } from './views';
import { answerSignal, mayWatch, recordPlaying } from './watch';

const TICK_RATE = 4; // ticks per second
const END_LINGER_MS = 45_000;

function startGame(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger, dispatcher: nkruntime.MatchDispatcher, matchId: string): void {
  const defs: SeatDef[] = s.lobby.map((l) => ({ id: l.userId, name: l.name, isBot: false }));
  let botIndex = 0;
  while (defs.length < s.params.minSeats) {
    defs.push({ id: `bot:${botIndex}`, name: BOT_NAMES[botIndex % BOT_NAMES.length] as string, isBot: true });
    botIndex++;
  }
  const seed = s.params.seed > 0 ? s.params.seed : Math.floor(Math.random() * 0x7fffffff);
  // WHY: the tutorial's coach opens with its own welcome card, so only real
  // games show the get-ready countdown before the first turn.
  const readyMs = s.params.tutorial ? 0 : GET_READY_MS;
  const firstTurnAt = nowMs() + readyMs;
  s.game = createGame(defs, seed, { stepSeconds: s.params.stepSeconds }, firstTurnAt);
  s.playStartsAt = readyMs > 0 ? firstTurnAt : 0;
  if (s.params.tutorial) {
    // The learner always goes first so the coach can explain the opening draw.
    const humanIdx = s.game.seats.findIndex((seat) => !seat.isBot);
    if (humanIdx > 0) {
      const rotated = s.game.seats.slice(humanIdx).concat(s.game.seats.slice(0, humanIdx));
      s.game.seats = rotated;
    }
  }
  s.seatByUser = {};
  s.pendingJoins = {};
  for (let i = 0; i < s.game.seats.length; i++) {
    const seat = s.game.seats[i];
    if (seat && !seat.isBot) s.seatByUser[seat.id] = i;
  }
  s.botActAt = firstTurnAt + botThinkMs(s);
  chooseRoomDeck(s, nk, logger);
  // Friends can find this game to watch it (not the tutorial: nothing to see).
  if (!s.params.tutorial) recordPlaying(nk, logger, matchId, Object.keys(s.seatByUser), nowMs());
  logger.info('match started seats=%d seed=%d tutorial=%s deck=%s', s.game.seats.length, seed, String(s.params.tutorial), s.customDeck ? 'custom' : 'standard');
  dispatcher.matchLabelUpdate(label(s));
  // The look goes first so the table can fetch the art while it lays out.
  sendDeck(s, nk, dispatcher);
  sendViews(s, dispatcher);
}

export const matchInit: nkruntime.MatchInitFunction<MatchState> = (ctx, logger, nk, params) => {
  const p: MatchParams = {
    isPrivate: params['isPrivate'] === true || params['isPrivate'] === 'true',
    roomCode: typeof params['roomCode'] === 'string' ? (params['roomCode'] as string) : undefined,
    minSeats: Number(params['minSeats']) || DEFAULT_PARAMS.minSeats,
    maxSeats: Number(params['maxSeats']) || DEFAULT_PARAMS.maxSeats,
    stepSeconds: clampStepSeconds(params['stepSeconds']),
    lobbyWaitSeconds: Number(params['lobbyWaitSeconds']) || DEFAULT_PARAMS.lobbyWaitSeconds,
    tutorial: params['tutorial'] === true || params['tutorial'] === 'true',
    seed: Number(params['seed']) || 0,
    hostId: typeof params['hostId'] === 'string' ? (params['hostId'] as string) : undefined,
  };
  if (p.tutorial) {
    p.isPrivate = false;
    p.minSeats = 3;
    p.maxSeats = 1;
    p.stepSeconds = 0;
    p.lobbyWaitSeconds = 0;
  }
  const state: MatchState = {
    params: p,
    presences: {},
    pendingJoins: {},
    lobby: [],
    seatByUser: {},
    game: null,
    playStartsAt: 0,
    forfeited: {},
    lastActivity: nowMs(),
    startsAt: 0,
    endedAt: 0,
    botActAt: 0,
    awarded: false,
    lastEmoteAt: {},
    log: [],
    pushTurnKey: '',
    pushSentAt: {},
    pushFailures: 0,
    customDeck: null,
    watchers: {},
  };
  logger.info('match init private=%s code=%s', String(p.isPrivate), p.roomCode || '-');
  void ctx;
  void nk;
  return { state, tickRate: TICK_RATE, label: label(state) };
};

export const matchJoinAttempt: nkruntime.MatchJoinAttemptFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, presence, metadata) => {
  void ctx; void logger; void nk; void dispatcher; void tick;
  if (state.game) {
    // Rejoin, or a friend with a watch pass (watch.ts).
    if (state.seatByUser[presence.userId] !== undefined) return { state, accept: true };
    if (metadata && metadata['watch'] && mayWatch(state, presence.userId, nowMs())) return { state, accept: true };
    return { state, accept: false, rejectMessage: 'game already started' };
  }
  const now = nowMs();
  const error = lobbyJoinError(state, presence.userId, metadata ? metadata['code'] : undefined, now);
  if (error) return { state, accept: false, rejectMessage: error };
  // WHY: matchJoin runs after this returns, so two attempts in the same
  // window would both see the old count; accepted-but-not-joined users
  // hold a seat until their matchJoin arrives (lobbyJoinError).
  let inLobby = false;
  for (const l of state.lobby) if (l.userId === presence.userId) inLobby = true;
  if (!inLobby) state.pendingJoins[presence.userId] = now;
  return { state, accept: true };
};

export const matchJoin: nkruntime.MatchJoinFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  void ctx; void nk; void tick;
  for (const p of presences) {
    // A second session of the same user (another device, or a reconnect the
    // server has not noticed yet) takes over: views go to the newest socket.
    state.presences[p.userId] = p;
    delete state.pendingJoins[p.userId];
    if (state.game) {
      const seat = state.seatByUser[p.userId];
      if (seat !== undefined) {
        const seatState = state.game.seats[seat];
        if (seatState) {
          seatState.connected = true;
          seatState.isBot = false;
        }
        sendDeck(state, nk, dispatcher, [p]);
        logger.info('user %s rejoined seat %d', p.userId, seat);
      } else {
        sendDeck(state, nk, dispatcher, [p]);
        logger.info('user %s is watching', p.userId);
      }
      continue;
    }
    let present = false;
    for (const l of state.lobby) if (l.userId === p.userId) present = true;
    if (!present) state.lobby.push({ userId: p.userId, name: p.username, ready: false });
  }
  state.lastActivity = nowMs();
  if (state.game) {
    sendViews(state, dispatcher);
  } else {
    // Public lobbies count down from the first human's arrival.
    if (!state.params.isPrivate && state.lobby.length > 0 && state.startsAt === 0) {
      state.startsAt = nowMs() + state.params.lobbyWaitSeconds * 1000;
    }
    dispatcher.matchLabelUpdate(label(state));
    send(dispatcher, OP_LOBBY, lobbyMessage(state));
  }
  return { state };
};

export const matchLeave: nkruntime.MatchLeaveFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  void ctx; void nk; void tick;
  for (const p of presences) {
    // WHY: only the session that is current for this user counts as leaving;
    // a stale session's leave must not drop a user who already reconnected.
    const current = state.presences[p.userId];
    if (current && current.sessionId !== p.sessionId) {
      logger.info('ignoring leave of stale session for %s', p.userId);
      continue;
    }
    delete state.presences[p.userId];
    delete state.pendingJoins[p.userId];
    if (state.game) {
      const seat = state.seatByUser[p.userId];
      if (seat !== undefined) {
        const seatState = state.game.seats[seat];
        if (seatState) seatState.connected = false;
        logger.info('user %s left seat %d (kept for rejoin)', p.userId, seat);
      }
    } else {
      state.lobby = state.lobby.filter((l) => l.userId !== p.userId);
      if (state.lobby.length === 0) state.startsAt = 0;
    }
  }
  state.lastActivity = nowMs();
  if (state.game) {
    sendViews(state, dispatcher);
  } else {
    dispatcher.matchLabelUpdate(label(state));
    send(dispatcher, OP_LOBBY, lobbyMessage(state));
  }
  return { state };
};

export const matchLoop: nkruntime.MatchLoopFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, messages) => {
  void tick;
  const now = nowMs();

  // ---- Lobby -------------------------------------------------------------
  if (!state.game) {
    for (const m of messages) {
      if (m.opCode === OP_READY) {
        for (const l of state.lobby) if (l.userId === m.sender.userId) l.ready = true;
      }
    }
    const humans = state.lobby.length;
    const allReady = humans > 0 && state.lobby.every((l) => l.ready);
    const enough = humans >= state.params.minSeats;
    const full = humans >= state.params.maxSeats;
    const timedOut = humans > 0 && state.startsAt > 0 && now >= state.startsAt;
    // Public: start when full, or when the wait since the first human elapses
    // (bots fill the rest). Private: everyone ready starts it.
    const publicStart = !state.params.isPrivate && (full || timedOut);
    const privateStart = state.params.isPrivate && allReady && (enough || humans >= 2);
    if (publicStart || privateStart) {
      startGame(state, nk, logger, dispatcher, ctx.matchId || '');
    } else if (humans === 0 && now - state.lastActivity > 5 * 60_000) {
      return null; // empty room expired
    } else {
      send(dispatcher, OP_LOBBY, lobbyMessage(state));
    }
    return { state };
  }

  // ---- Ended -------------------------------------------------------------
  if (state.game.phase === 'ended') {
    awardProgress(state, nk, logger);
    if (now - state.endedAt > END_LINGER_MS || Object.keys(state.presences).length === 0) return null;
    return { state };
  }

  // ---- Playing: client messages (never allowed to throw) ----------------
  try {
    handleEmotes(state, messages, nk, dispatcher, now);
  } catch (e) {
    logger.error('emote handling failed: %s', String(e));
  }
  try {
    handleForfeits(state, messages, nk, logger, dispatcher, now);
  } catch (e) {
    logger.error('forfeit handling failed: %s', String(e));
  }
  if (Object.keys(state.seatByUser).length === 0) {
    logger.info('every player forfeited; closing the match');
    return null;
  }

  // ---- Get ready: nobody acts until the countdown ends -------------------
  if (state.playStartsAt > 0) {
    if (now < state.playStartsAt) {
      for (const m of messages) {
        if (m.opCode === OP_ACTION) send(dispatcher, OP_ERROR, { message: 'the game has not started yet' }, [m.sender]);
      }
      return { state };
    }
    state.playStartsAt = 0;
    sendViews(state, dispatcher);
  }

  // ---- Playing: client actions ------------------------------------------
  handleActions(state, messages, nk, dispatcher, logger);

  // ---- Playing: bots and timeouts ---------------------------------------
  const active = state.game.seats[state.game.active];
  if (active) {
    if (active.isBot && now >= state.botActAt) {
      // WHY: the tutorial's coach steps are scripted against a fixed seed and
      // the simple deterministic policy, so tutorial bots keep autoAction with
      // tieBreak 0. Real games use the heuristic bot; its rng is Math.random
      // because replays come from the action log, and deriving it from the
      // private game seed would correlate public bot moves with the seed.
      const action = state.params.tutorial ? autoAction(state.game, 0) : botAction(state.game, () => Math.random());
      apply(state, dispatcher, logger, state.game.active, action, 'bot');
    } else if (!active.isBot && state.game.deadline > 0 && now >= state.game.deadline) {
      apply(state, dispatcher, logger, state.game.active, autoAction(state.game), 'timeout');
    }
  }

  // ---- "Your turn" push for a player who is away (never throws) ---------
  try {
    pushTurnIfAway(state, ctx, nk, logger, now);
  } catch (e) {
    logger.error('turn push failed: %s', String(e));
  }
  return { state };
};

export const matchTerminate: nkruntime.MatchTerminateFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, graceSeconds) => {
  void ctx; void nk; void tick; void graceSeconds;
  logger.info('match terminating');
  send(dispatcher, OP_ERROR, { message: 'server shutting down' });
  return { state };
};

/** Signals: a watch request from watch_friend (watch.ts) answers {ok} or {error}. */
export const matchSignal: nkruntime.MatchSignalFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, data) => {
  void ctx; void logger; void nk; void dispatcher; void tick;
  return { state, data: answerSignal(state, data, nowMs()) };
};
