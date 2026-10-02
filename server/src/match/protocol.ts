/** Wire protocol between the Godot client and the match handler. */
import type { PlayerView } from '../engine';

/** Owner of server-wide storage rows (room codes, cohorts, config). */
export const SYSTEM_USER = '00000000-0000-0000-0000-000000000000';

/** Client -> server opcodes. */
export const OP_ACTION = 1;
export const OP_READY = 2;
/** {"emote": "<id from EMOTE_IDS>"}; relayed to the table as OP_EMOTE_SHOWN. */
export const OP_EMOTE = 3;
/** {} Give up the game: a bot plays the seat to the end and it counts as a loss. */
export const OP_FORFEIT = 4;

/** Server -> client opcodes. */
export const OP_VIEW = 10;
export const OP_EVENTS = 11;
export const OP_LOBBY = 12;
export const OP_ERROR = 13;
/** {"seat": n, "emote": "<id>"} */
export const OP_EMOTE_SHOWN = 14;
/** {"seat": n} That seat's player forfeited; a bot plays it from now on. */
export const OP_FORFEITED = 15;

/** OP_VIEW payload: the seat's PlayerView plus match timing. */
export interface ViewMessage extends PlayerView {
  /**
   * Milliseconds until the first turn, 0 once play has begun. Until then
   * `legal` is empty. A duration rather than a time, so a phone whose clock
   * is off still counts down correctly.
   */
  startsInMs: number;
}

/**
 * The only chat there is: preset emotes and phrases (all-ages decision D4).
 * Ids are stable; the client owns the text and artwork.
 */
export const EMOTE_IDS = [
  'wave', 'think', 'laugh', 'wow', 'cry', 'clap',
  'hello', 'good_move', 'oops', 'thanks', 'gg', 'hurry_up', 'nice', 'no_way',
];
export const EMOTE_COOLDOWN_MS = 2000;

/** Notification code of a room invite sent by the invite_friend RPC. */
export const INVITE_CODE = 100;

export const MATCH_MODULE = 'big_business';

export interface MatchParams {
  /** true for private rooms created with a code. */
  isPrivate: boolean;
  roomCode?: string;
  minSeats: number;
  maxSeats: number;
  stepSeconds: number;
  /** Seconds to wait in a public lobby before filling with bots. */
  lobbyWaitSeconds: number;
  /** Tutorial: one human, two slow deterministic bots, no timer, fixed seed. */
  tutorial: boolean;
  /** Fixed seed (tutorial only); 0 means random. */
  seed: number;
}

export interface LobbySeat {
  userId: string;
  name: string;
  ready: boolean;
}

export interface LobbyMessage {
  roomCode?: string;
  isPrivate: boolean;
  seats: LobbySeat[];
  minSeats: number;
  maxSeats: number;
  /** Epoch ms when the match auto-starts, 0 if waiting for ready. */
  startsAt: number;
}

export const DEFAULT_PARAMS: MatchParams = {
  isPrivate: false,
  minSeats: 3,
  maxSeats: 5,
  stepSeconds: 30,
  lobbyWaitSeconds: 20,
  tutorial: false,
  seed: 0,
};

export const TUTORIAL_SEED = 20260928;

export const BOT_NAMES = ['Intern Ivy', 'Analyst Avi', 'Broker Bo', 'Auditor Ada', 'CEO Cal', 'Investor Ines'];

/** Shortest and longest private-room step timer in seconds; 0 turns the timer off. */
export const MIN_STEP_SECONDS = 5;
export const MAX_STEP_SECONDS = 120;

/** A requested step timer made safe: 0 (off) or clamped to the allowed range. */
export function clampStepSeconds(requested: unknown): number {
  const n = Number(requested);
  if (requested === undefined || requested === null || !isFinite(n)) return DEFAULT_PARAMS.stepSeconds;
  if (n === 0) return 0;
  return Math.min(MAX_STEP_SECONDS, Math.max(MIN_STEP_SECONDS, Math.round(n)));
}

