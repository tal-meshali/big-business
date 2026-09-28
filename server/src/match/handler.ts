/**
 * Nakama authoritative match handler for Big Business.
 *
 * The handler owns a GameState from the pure engine and is the only place the
 * deck is shuffled or scored. Clients send intents (OP_ACTION) and receive a
 * per-seat PlayerView (OP_VIEW) plus animation events (OP_EVENTS).
 */
import { applyAction, autoAction, createGame, playerView, RulesError, type SeatDef } from '../engine';
import type { Action, GameEvent, GameState } from '../engine';
import {
  BOT_NAMES,
  DEFAULT_PARAMS,
  EMOTE_COOLDOWN_MS,
  EMOTE_IDS,
  OP_ACTION,
  OP_EMOTE,
  OP_EMOTE_SHOWN,
  OP_ERROR,
  OP_EVENTS,
  OP_LOBBY,
  OP_READY,
  OP_VIEW,
  type LobbyMessage,
  type LobbySeat,
  type MatchParams,
} from './protocol';
import { applyGameResult, emptyProgress, PROFILE_COLLECTION, PROFILE_KEY, SEASON_LEADERBOARD, seasonPointsForGame, type Progress } from './progression';

const TICK_RATE = 4; // ticks per second
const BOT_THINK_MS = 900;
const TUTORIAL_BOT_THINK_MS = 1800;
const END_LINGER_MS = 45_000;
const AUTO_MOVES_TO_BOT = 3;

interface MatchState {
  params: MatchParams;
  /** Presences currently connected, keyed by user id. */
  presences: { [userId: string]: nkruntime.Presence };
  /** Lobby seats in join order (humans only) before the game starts. */
  lobby: LobbySeat[];
  /** Seat index by user id once the game has started. */
  seatByUser: { [userId: string]: number };
  game: GameState | null;
  /** Epoch ms of the last join or leave; used to expire empty lobbies. */
  lastActivity: number;
  /** Epoch ms when a public lobby auto-starts (bots fill), 0 if unset. */
  startsAt: number;
  endedAt: number;
  botActAt: number;
  /** Progression and leaderboard written once after the game ends. */
  awarded: boolean;
  /** Last emote time per user id, for the cooldown. */
  lastEmoteAt: { [userId: string]: number };
  /** Append-only log of accepted actions for replay / reconnection. */
  log: Array<{ seq: number; seat: number; action: Action; source: string }>;
}

function nowMs(): number {
  return Date.now();
}

function botThinkMs(s: MatchState): number {
  return s.params.tutorial ? TUTORIAL_BOT_THINK_MS : BOT_THINK_MS;
}

function lobbyMessage(s: MatchState): LobbyMessage {
  return {
    roomCode: s.params.roomCode,
    isPrivate: s.params.isPrivate,
    seats: s.lobby,
    minSeats: s.params.minSeats,
    maxSeats: s.params.maxSeats,
    startsAt: s.startsAt,
  };
}

function label(s: MatchState): string {
  return JSON.stringify({
    mode: s.params.tutorial ? 'tutorial' : s.params.isPrivate ? 'private' : 'public',
    code: s.params.roomCode || '',
    open: s.game === null ? 'yes' : 'no',
    players: s.lobby.length,
    max: s.params.maxSeats,
  });
}

function send(dispatcher: nkruntime.MatchDispatcher, op: number, data: unknown, to?: nkruntime.Presence[]): void {
  dispatcher.broadcastMessage(op, JSON.stringify(data), to, null, true);
}

function sendViews(s: MatchState, dispatcher: nkruntime.MatchDispatcher): void {
  if (!s.game) return;
  for (const userId in s.presences) {
    const presence = s.presences[userId];
    if (!presence) continue;
    const seat = s.seatByUser[userId];
    const view = playerView(s.game, seat === undefined ? null : seat);
    send(dispatcher, OP_VIEW, view, [presence]);
  }
}

function startGame(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger, dispatcher: nkruntime.MatchDispatcher): void {
  const defs: SeatDef[] = s.lobby.map((l) => ({ id: l.userId, name: l.name, isBot: false }));
  let botIndex = 0;
  while (defs.length < s.params.minSeats) {
    defs.push({ id: `bot:${botIndex}`, name: BOT_NAMES[botIndex % BOT_NAMES.length] as string, isBot: true });
    botIndex++;
  }
  const seed = s.params.seed > 0 ? s.params.seed : Math.floor(Math.random() * 0x7fffffff);
  s.game = createGame(defs, seed, { stepSeconds: s.params.stepSeconds }, nowMs());
  if (s.params.tutorial) {
    // The learner always goes first so the coach can explain the opening draw.
    const humanIdx = s.game.seats.findIndex((seat) => !seat.isBot);
    if (humanIdx > 0) {
      const rotated = s.game.seats.slice(humanIdx).concat(s.game.seats.slice(0, humanIdx));
      s.game.seats = rotated;
    }
  }
  s.seatByUser = {};
  for (let i = 0; i < s.game.seats.length; i++) {
    const seat = s.game.seats[i];
    if (seat && !seat.isBot) s.seatByUser[seat.id] = i;
  }
  s.botActAt = nowMs() + botThinkMs(s);
  logger.info('match started seats=%d seed=%d tutorial=%s', s.game.seats.length, seed, String(s.params.tutorial));
  dispatcher.matchLabelUpdate(label(s));
  sendViews(s, dispatcher);
  void nk;
}

function apply(
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
  s.log.push({ seq: s.game.seq, seat, action, source });

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

/** Write XP, levels and season points for every human seat. Best effort. */
function awardProgress(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  if (!s.game || !s.game.result || s.awarded) return;
  s.awarded = true;
  const seatCount = s.game.seats.length;
  let humans = 0;
  for (const seat of s.game.seats) if (!seat.id.startsWith('bot:')) humans++;
  for (const score of s.game.result.scores) {
    const seat = s.game.seats[score.seat];
    if (!seat || seat.id.startsWith('bot:')) continue;
    try {
      const rows = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: seat.id }]);
      const current = rows.length > 0 && rows[0] ? (rows[0].value as Progress) : emptyProgress();
      const next = applyGameResult(current, score.rank, seatCount, humans);
      nk.storageWrite([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: seat.id, value: next, permissionRead: 1, permissionWrite: 0 }]);
      const points = seasonPointsForGame(score.rank, seatCount, humans);
      if (points > 0) {
        nk.leaderboardRecordWrite(SEASON_LEADERBOARD, seat.id, seat.name, points, score.rank === 1 ? 1 : 0);
      }
    } catch (e) {
      logger.warn('progress award failed for %s: %s', seat.id, String(e));
    }
  }
}

export const matchInit: nkruntime.MatchInitFunction<MatchState> = (ctx, logger, nk, params) => {
  const p: MatchParams = {
    isPrivate: params['isPrivate'] === true || params['isPrivate'] === 'true',
    roomCode: typeof params['roomCode'] === 'string' ? (params['roomCode'] as string) : undefined,
    minSeats: Number(params['minSeats']) || DEFAULT_PARAMS.minSeats,
    maxSeats: Number(params['maxSeats']) || DEFAULT_PARAMS.maxSeats,
    stepSeconds: params['stepSeconds'] === undefined ? DEFAULT_PARAMS.stepSeconds : Number(params['stepSeconds']),
    lobbyWaitSeconds: Number(params['lobbyWaitSeconds']) || DEFAULT_PARAMS.lobbyWaitSeconds,
    tutorial: params['tutorial'] === true || params['tutorial'] === 'true',
    seed: Number(params['seed']) || 0,
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
    lobby: [],
    seatByUser: {},
    game: null,
    lastActivity: nowMs(),
    startsAt: 0,
    endedAt: 0,
    botActAt: 0,
    awarded: false,
    lastEmoteAt: {},
    log: [],
  };
  logger.info('match init private=%s code=%s', String(p.isPrivate), p.roomCode || '-');
  void ctx;
  void nk;
  return { state, tickRate: TICK_RATE, label: label(state) };
};

export const matchJoinAttempt: nkruntime.MatchJoinAttemptFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, presence) => {
  void ctx; void logger; void nk; void dispatcher; void tick;
  if (state.game) {
    // Rejoin only.
    if (state.seatByUser[presence.userId] !== undefined) return { state, accept: true };
    return { state, accept: false, rejectMessage: 'game already started' };
  }
  if (state.lobby.length >= state.params.maxSeats) {
    return { state, accept: false, rejectMessage: 'room full' };
  }
  return { state, accept: true };
};

export const matchJoin: nkruntime.MatchJoinFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, presences) => {
  void ctx; void nk; void tick;
  for (const p of presences) {
    state.presences[p.userId] = p;
    if (state.game) {
      const seat = state.seatByUser[p.userId];
      if (seat !== undefined) {
        const seatState = state.game.seats[seat];
        if (seatState) {
          seatState.connected = true;
          seatState.isBot = false;
        }
        logger.info('user %s rejoined seat %d', p.userId, seat);
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
    delete state.presences[p.userId];
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
  void ctx; void tick;
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
      startGame(state, nk, logger, dispatcher);
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

  // ---- Playing: emotes (rate limited, ids validated) --------------------
  for (const m of messages) {
    if (m.opCode !== OP_EMOTE) continue;
    const seat = state.seatByUser[m.sender.userId];
    if (seat === undefined) continue;
    let emote = '';
    try {
      emote = String((JSON.parse(nk.binaryToString(m.data)) as { emote?: string }).emote || '');
    } catch (e) {
      continue;
    }
    if (EMOTE_IDS.indexOf(emote) < 0) continue;
    const last = state.lastEmoteAt[m.sender.userId] || 0;
    if (now - last < EMOTE_COOLDOWN_MS) continue;
    state.lastEmoteAt[m.sender.userId] = now;
    send(dispatcher, OP_EMOTE_SHOWN, { seat, emote });
  }

  // ---- Playing: client actions ------------------------------------------
  for (const m of messages) {
    if (m.opCode !== OP_ACTION) continue;
    const seat = state.seatByUser[m.sender.userId];
    if (seat === undefined) continue;
    let action: Action | null = null;
    try {
      action = JSON.parse(nk.binaryToString(m.data)) as Action;
    } catch (e) {
      send(dispatcher, OP_ERROR, { message: 'bad action payload' }, [m.sender]);
      continue;
    }
    const ok = apply(state, dispatcher, logger, seat, action, 'player');
    if (!ok) send(dispatcher, OP_ERROR, { message: 'illegal action', action }, [m.sender]);
  }

  // ---- Playing: bots and timeouts ---------------------------------------
  const active = state.game.seats[state.game.active];
  if (active) {
    if (active.isBot && now >= state.botActAt) {
      const tieBreak = state.params.tutorial ? 0 : Math.random();
      apply(state, dispatcher, logger, state.game.active, autoAction(state.game, tieBreak), 'bot');
    } else if (!active.isBot && state.game.deadline > 0 && now >= state.game.deadline) {
      apply(state, dispatcher, logger, state.game.active, autoAction(state.game), 'timeout');
    }
  }
  return { state };
};

export const matchTerminate: nkruntime.MatchTerminateFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, graceSeconds) => {
  void ctx; void nk; void tick; void graceSeconds;
  logger.info('match terminating');
  send(dispatcher, OP_ERROR, { message: 'server shutting down' });
  return { state };
};

export const matchSignal: nkruntime.MatchSignalFunction<MatchState> = (ctx, logger, nk, dispatcher, tick, state, data) => {
  void ctx; void logger; void nk; void dispatcher; void tick;
  return { state, data };
};
