/** Match state shared by the handler and its helper modules. */
import type { Action, GameState } from '../engine';
import type { LobbyMessage, LobbySeat, MatchParams } from './protocol';

export const BOT_THINK_MS = 900;
export const TUTORIAL_BOT_THINK_MS = 1800;

export interface MatchState {
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
  /** Append-only log of accepted actions for replay / reconnection. `coins` is what a Market share paid (quest stats). */
  log: Array<{ seq: number; seat: number; action: Action; source: string; coins?: number }>;
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

/** Match label used by quick play's listing query; values are strings so Bleve matches them. */
export function label(s: MatchState): string {
  return JSON.stringify({
    mode: s.params.tutorial ? 'tutorial' : s.params.isPrivate ? 'private' : 'public',
    code: s.params.roomCode || '',
    open: s.game === null ? 'yes' : 'no',
    players: s.lobby.length,
    max: s.params.maxSeats,
  });
}

export function send(dispatcher: nkruntime.MatchDispatcher, op: number, data: unknown, to?: nkruntime.Presence[]): void {
  dispatcher.broadcastMessage(op, JSON.stringify(data), to, null, true);
}
