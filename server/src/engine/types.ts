import type { CompanyId } from './companies';

export interface Card {
  id: number;
  company: CompanyId;
}

export interface MarketSlot {
  card: Card;
  coins: number;
}

export type Phase = 'take' | 'play' | 'ended';

export interface Seat {
  /** Stable player id (Nakama user id, or "bot:n"). */
  id: string;
  name: string;
  isBot: boolean;
  connected: boolean;
  hand: Card[];
  portfolio: Card[];
  /** Coins worth 1. */
  bronze: number;
  /** Coins worth 3 (received as dividends). */
  gold: number;
  /** Consecutive turns completed by auto-move. */
  autoMoves: number;
}

export interface GameOptions {
  /** Seconds per step. 0 disables the timer. */
  stepSeconds: number;
}

export interface GameState {
  seed: number;
  options: GameOptions;
  /** Top of the supply is the LAST element. */
  supply: Card[];
  removed: Card[];
  market: MarketSlot[];
  seats: Seat[];
  active: number;
  phase: Phase;
  /** Turn counter, starts at 1. */
  turn: number;
  /** Company of the share taken this turn, valid during the play step. */
  tookCompany: CompanyId | null;
  /** Seat index holding each company's regulator token, or null. */
  tokens: Array<number | null>;
  /** Sequence number of the last applied action. */
  seq: number;
  /** Epoch ms when the current step auto-moves. 0 = no deadline. */
  deadline: number;
  result: DividendResult | null;
}

export type Action =
  | { type: 'take_supply' }
  | { type: 'take_market'; cardId: number }
  | { type: 'play_portfolio'; cardId: number }
  | { type: 'play_market'; cardId: number };

export type ActionSource = 'player' | 'bot' | 'timeout';

export interface Payment {
  from: number;
  to: number;
  coins: number;
}

export interface CompanyDividend {
  company: CompanyId;
  /** Seat index of the majority holder, or null on a tie / no holders. */
  majority: number | null;
  payments: Payment[];
}

export interface SeatScore {
  seat: number;
  bronze: number;
  gold: number;
  score: number;
  /** 1-based rank; ties share a rank. */
  rank: number;
}

export interface DividendResult {
  companies: CompanyDividend[];
  scores: SeatScore[];
}

export type GameEvent =
  | { type: 'took_supply'; seat: number; cost: number }
  | { type: 'took_market'; seat: number; card: Card; coins: number }
  | { type: 'played'; seat: number; card: Card; to: 'portfolio' | 'market' }
  | { type: 'token_moved'; company: CompanyId; from: number | null; to: number }
  | { type: 'step'; seat: number; phase: Phase; turn: number }
  | { type: 'hands_revealed'; hands: Card[][] }
  | { type: 'game_ended'; result: DividendResult };

export interface ApplyResult {
  state: GameState;
  events: GameEvent[];
}

/** What one client is allowed to see. */
export interface SeatView {
  id: string;
  name: string;
  isBot: boolean;
  connected: boolean;
  handCount: number;
  /** Only present for the viewer's own seat, or for everyone once the game ends. */
  hand?: Card[];
  portfolio: Card[];
  bronze: number;
  gold: number;
  tokens: CompanyId[];
}

export interface PlayerView {
  you: number | null;
  seats: SeatView[];
  market: MarketSlot[];
  supplyCount: number;
  removedCount: number;
  active: number;
  phase: Phase;
  turn: number;
  tookCompany: CompanyId | null;
  tokens: Array<number | null>;
  seq: number;
  deadline: number;
  /** Cost for the viewer to draw from the supply right now (null if not their take step). */
  drawCost: number | null;
  legal: Action[];
  result: DividendResult | null;
}
