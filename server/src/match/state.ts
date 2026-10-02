/** Match state shared by the handler and its helper modules. */
import type { Action, GameState } from '../engine';
import type { LobbyMessage, LobbySeat, MatchParams } from './protocol';

export const BOT_THINK_MS = 900;
export const TUTORIAL_BOT_THINK_MS = 1800;
/** Countdown between the table appearing and the first turn. */
export const GET_READY_MS = 4000;
/**
 * How long an accepted join attempt holds a lobby seat while its matchJoin
 * has not arrived. A socket that dropped in between never sends one.
 */
export const PENDING_JOIN_MS = 10_000;

export interface MatchState {
  params: MatchParams;
  /** Presences currently connected, keyed by user id. */
  presences: { [userId: string]: nkruntime.Presence };
  /**
   * Users whose join attempt was accepted but whose matchJoin has not run
   * yet, with the epoch ms of the attempt, so concurrent attempts cannot
   * overfill a lobby. Cleared on join; expires after PENDING_JOIN_MS.
   */
  pendingJoins: { [userId: string]: number };
  /** Lobby seats in join order (humans only) before the game starts. */
  lobby: LobbySeat[];
  /** Seat index by user id once the game has started. */
  seatByUser: { [userId: string]: number };
  game: GameState | null;
  /** Epoch ms when the first turn begins; 0 once play has begun (or no countdown). */
  playStartsAt: number;
  /** Users who forfeited. Their seats are played by bots and cannot be rejoined. */
  forfeited: { [userId: string]: boolean };
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
  /** Append-only log of accepted actions for replay / reconnection. `coins` is what a Market share paid (quest stats). */
  log: Array<{ seq: number; seat: number; action: Action; source: string; coins?: number }>;
  /** "turn:active" of the last turn checked for a push (turn_push.ts). */
  pushTurnKey: string;
  /** Epoch ms of the last "your turn" push per user id. */
  pushSentAt: { [userId: string]: number };
  /** Failed push sends; at PUSH_MAX_FAILURES the match stops trying. */
  pushFailures: number;
}

export function nowMs(): number {
  return Date.now();
}

export function botThinkMs(s: MatchState): number {
  return s.params.tutorial ? TUTORIAL_BOT_THINK_MS : BOT_THINK_MS;
}

export function lobbyMessage(s: MatchState): LobbyMessage {
  return {
    roomCode: s.params.roomCode,
    isPrivate: s.params.isPrivate,
    seats: s.lobby,
    minSeats: s.params.minSeats,
    maxSeats: s.params.maxSeats,
    startsAt: s.startsAt,
  };
}

/**
 * Match label used by quick play's listing query; values are strings so Bleve
 * matches them.
 *
 * WHY no room code: any client can list matches with their labels, so a code
 * here would let strangers into every private room.
 */
export function label(s: MatchState): string {
  return JSON.stringify({
    mode: s.params.tutorial ? 'tutorial' : s.params.isPrivate ? 'private' : 'public',
    open: s.game === null ? 'yes' : 'no',
    players: s.lobby.length,
    max: s.params.maxSeats,
  });
}

/**
 * Why a join attempt to a lobby (before the game starts) is refused, or null
 * to accept it. Users already in the lobby may always come back. Private
 * rooms need the room code in the join metadata: the match id alone can be
 * listed by any client. Seats held by other users' accepted attempts count
 * until they join or PENDING_JOIN_MS passes; the user's own earlier attempt
 * never counts against them.
 */
export function lobbyJoinError(s: MatchState, userId: string, code: unknown, now: number): string | null {
  for (const l of s.lobby) if (l.userId === userId) return null;
  if (s.params.isPrivate && (typeof code !== 'string' || code.toUpperCase() !== (s.params.roomCode || ''))) return 'invalid code';
  let pending = 0;
  for (const id in s.pendingJoins) {
    if (id === userId || now - (s.pendingJoins[id] || 0) >= PENDING_JOIN_MS) continue;
    let listed = false;
    for (const l of s.lobby) if (l.userId === id) listed = true;
    if (!listed) pending++;
  }
  if (s.lobby.length + pending >= s.params.maxSeats) return 'room full';
  return null;
}

export function send(dispatcher: nkruntime.MatchDispatcher, op: number, data: unknown, to?: nkruntime.Presence[]): void {
  dispatcher.broadcastMessage(op, JSON.stringify(data), to, null, true);
}
