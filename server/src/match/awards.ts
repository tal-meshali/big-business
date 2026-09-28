/** Writes XP, levels, season points and quest progress for every human seat once a game ends. */
import { applyForfeit, applyGameResult, normalizeProgress, PROFILE_COLLECTION, PROFILE_KEY, SEASON_LEADERBOARD, seasonPointsForGame, type Progress } from './progression';
import { applyGameToQuests, gameStats } from './quests';
import type { MatchState } from './state';

/** Best effort: a storage failure is logged and never breaks the match. */
export function awardProgress(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  if (!s.game || !s.game.result || s.awarded) return;
  s.awarded = true;
  const seatCount = s.game.seats.length;
  let humans = 0;
  // WHY: a player who forfeited is not playing, so a 2-human room where one
  // forfeits counts as a solo game (no season points, reduced XP).
  for (const seat of s.game.seats) if (!seat.id.startsWith('bot:') && !s.forfeited[seat.id]) humans++;
  const now = Date.now();
  for (const score of s.game.result.scores) {
    const seat = s.game.seats[score.seat];
    // Forfeited players were recorded when they forfeited (awardForfeit).
    if (!seat || seat.id.startsWith('bot:') || s.forfeited[seat.id]) continue;
    try {
      const rows = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: seat.id }]);
      const current = normalizeProgress(rows.length > 0 && rows[0] ? (rows[0].value as Partial<Progress>) : null);
      let next = applyGameResult(current, score.rank, seatCount, humans);
      try {
        next = { ...next, quests: applyGameToQuests(next.quests, gameStats(s.game, s.log, score.seat), now) };
      } catch (e) {
        logger.warn('quest progress failed for %s: %s', seat.id, String(e));
      }
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

/** Records a forfeit on the player's profile. Best effort, like awardProgress. */
export function awardForfeit(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string): void {
  try {
    const rows = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId }]);
    const current = normalizeProgress(rows.length > 0 && rows[0] ? (rows[0].value as Partial<Progress>) : null);
    nk.storageWrite([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: applyForfeit(current), permissionRead: 1, permissionWrite: 0 }]);
  } catch (e) {
    logger.warn('forfeit record failed for %s: %s', userId, String(e));
  }
}
