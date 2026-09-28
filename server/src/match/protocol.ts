/** Wire protocol between the Godot client and the match handler. */

/** Client -> server opcodes. */
export const OP_ACTION = 1;
export const OP_READY = 2;
/** {"emote": "<id from EMOTE_IDS>"}; relayed to the table as OP_EMOTE_SHOWN. */
export const OP_EMOTE = 3;

/** Server -> client opcodes. */
export const OP_VIEW = 10;
export const OP_EVENTS = 11;
export const OP_LOBBY = 12;
export const OP_ERROR = 13;
/** {"seat": n, "emote": "<id>"} */
export const OP_EMOTE_SHOWN = 14;

/**
 * The only chat there is: preset emotes and phrases (all-ages decision D4).
 * Ids are stable; the client owns the text and artwork.
 */
export const EMOTE_IDS = [
  'wave', 'think', 'laugh', 'wow', 'cry', 'clap',
  'hello', 'good_move', 'oops', 'thanks', 'gg', 'hurry_up', 'nice', 'no_way',
];
export const EMOTE_COOLDOWN_MS = 2000;

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
