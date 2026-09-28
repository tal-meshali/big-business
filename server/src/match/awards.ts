/** Writes XP, levels, season points and quest progress for every human seat once a game ends. */
import { applyGameResult, normalizeProgress, PROFILE_COLLECTION, PROFILE_KEY, SEASON_LEADERBOARD, seasonPointsForGame, type Progress } from './progression';
import { applyGameToQuests, gameStats } from './quests';
import type { MatchState } from './state';

/** Best effort: a storage failure is logged and never breaks the match. */
export function awardProgress(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  if (!s.game || !s.game.result || s.awarded) return;
  s.awarded = true;
  const seatCount = s.game.seats.length;
  let humans = 0;
  for (const seat of s.game.seats) if (!seat.id.startsWith('bot:')) humans++;
  const now = Date.now();
  for (const score of s.game.result.scores) {
    const seat = s.game.seats[score.seat];
    if (!seat || seat.id.startsWith('bot:')) continue;
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
