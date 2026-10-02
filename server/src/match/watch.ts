/**
 * Spectating (research section 7, Phase 3): a player may watch a game a
 * mutual friend is playing. Watchers get the view a player with no seat
 * gets (no hands; engine playerView with viewer null) and can send nothing
 * the match acts on: actions, emotes and forfeits all need a seat.
 *
 * How: the match records its seated players in `playing` rows when it
 * starts; watch_friend checks the friendship, then asks the match itself
 * (matchSignal) to let the watcher in for WATCH_PASS_MS, so only the match
 * decides whether its game can be watched. The join carries {watch: "1"}.
 */
import type { MatchState } from './state';

/** Server-only rows: 'current' = the match a player is seated in. */
export const PLAYING_COLLECTION = 'playing';
const PLAYING_KEY = 'current';
/** A playing row older than this is ignored. */
export const PLAYING_MAX_MS = 3 * 60 * 60 * 1000;
/** Watchers per game. */
export const MAX_WATCHERS = 8;
/** How long a pass from matchSignal lets the watcher join. */
export const WATCH_PASS_MS = 30_000;

export interface PlayingRow {
  matchId: string;
  at: number;
}

export interface WatchRequest {
  watch: string;
  friend: string;
}

/** Records the match each seated person is in (best effort, at game start). */
export function recordPlaying(nk: nkruntime.Nakama, logger: nkruntime.Logger, matchId: string, userIds: ReadonlyArray<string>, now: number): void {
  if (!matchId || userIds.length === 0) return;
  try {
    nk.storageWrite(userIds.map((userId) => ({ collection: PLAYING_COLLECTION, key: PLAYING_KEY, userId, value: { matchId, at: now }, permissionRead: 0, permissionWrite: 0 })));
  } catch (e) {
    logger.warn('playing rows failed: %s', String(e));
  }
}

/** The match ids these players are in (fresh rows only), by user id. */
export function readPlaying(nk: nkruntime.Nakama, userIds: ReadonlyArray<string>, now: number): { [userId: string]: string } {
  const out: { [userId: string]: string } = {};
  if (userIds.length === 0) return out;
  const rows = nk.storageRead(userIds.map((userId) => ({ collection: PLAYING_COLLECTION, key: PLAYING_KEY, userId })));
  for (const r of rows) {
    if (r.permissionWrite !== 0) continue;
    const v = r.value as Partial<PlayingRow>;
    if (typeof v.matchId === 'string' && typeof v.at === 'number' && now - v.at < PLAYING_MAX_MS) out[r.userId] = v.matchId;
  }
  return out;
}

/** People watching now: present, without a seat, and let in as watchers. */
export function watcherCount(s: MatchState): number {
  let n = 0;
  for (const id in s.presences) if (s.seatByUser[id] === undefined && s.watchers[id] !== undefined) n++;
  return n;
}

/** Why the match refuses a watch request, or '' after granting a pass. */
export function grantWatch(s: MatchState, req: WatchRequest, now: number): string {
  if (!s.game || s.game.phase === 'ended' || s.params.tutorial) return 'not playing';
  if (s.seatByUser[req.friend] === undefined) return 'not playing';
  if (s.seatByUser[req.watch] !== undefined) return 'you are playing';
  if (s.presences[req.watch] === undefined && watcherCount(s) >= MAX_WATCHERS) return 'too many watching';
  s.watchers[req.watch] = now + WATCH_PASS_MS;
  return '';
}

/** True when a join attempt is a watcher's with a pass still valid (or one already watching). */
export function mayWatch(s: MatchState, userId: string, now: number): boolean {
  const until = s.watchers[userId];
  return until !== undefined && (now < until || s.presences[userId] !== undefined);
}

export function parseWatchRequest(data: string): WatchRequest | null {
  try {
    const o = JSON.parse(data) as { [k: string]: unknown };
    if (typeof o['watch'] === 'string' && typeof o['friend'] === 'string') return { watch: o['watch'] as string, friend: o['friend'] as string };
  } catch (e) {
    // Not a watch request.
  }
  return null;
}

/** The match's answer to a signal: {ok} after granting a watch pass, or {error}. */
export function answerSignal(s: MatchState, data: string, now: number): string {
  const req = parseWatchRequest(data);
  if (!req) return JSON.stringify({ error: 'unknown signal' });
  const error = grantWatch(s, req, now);
  return JSON.stringify(error ? { error } : { ok: true });
}
