/**
 * Watch RPCs: which mutual friends are in a game now, and a pass to watch
 * one of them. The match grants the pass itself (watch.ts grantWatch via
 * matchSignal); the client then joins with {watch: "1"}.
 */
import { isUserId, parseBody, reject, requireUser } from './input';
import { checkRate } from './ratelimit';
import { areMutualFriends, mutualFriends } from './social';
import { readPlaying } from './watch';

/** Friends checked per call: the friends panel shows at most this many. */
const FRIENDS_MAX = 100;

function running(nk: nkruntime.Nakama, matchId: string): boolean {
  try {
    return nk.matchGet(matchId) !== null;
  } catch (e) {
    return false;
  }
}

/** RPC friends_playing: mutual friends seated in a game that is still running. */
export const rpcFriendsPlaying: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'friends_playing', Date.now());
  const friends = mutualFriends(nk, userId).slice(0, FRIENDS_MAX);
  const playing = readPlaying(nk, friends, Date.now());
  return JSON.stringify({ playing: Object.keys(playing).filter((id) => running(nk, playing[id] as string)) });
};

/** RPC watch_friend {userId}: {matchId} to join as a watcher, if the game lets you in. */
export const rpcWatchFriend: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const target = parseBody(payload)['userId'];
  if (!isUserId(target) || target === userId) reject('invalid player');
  checkRate(nk, userId, 'watch_friend', Date.now());
  if (!areMutualFriends(nk, userId, target)) reject('not friends');
  const matchId = readPlaying(nk, [target], Date.now())[target];
  if (!matchId || !running(nk, matchId)) reject('not playing');
  let answer: { [k: string]: unknown } = {};
  try {
    answer = JSON.parse(nk.matchSignal(matchId, JSON.stringify({ watch: userId, friend: target })) || '{}');
  } catch (e) {
    logger.warn('watch signal failed: %s', String(e));
    reject('not playing');
  }
  if (typeof answer['error'] === 'string') reject(answer['error'] as string);
  return JSON.stringify({ matchId });
};
