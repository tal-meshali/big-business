/** Writes XP, levels, season points and quest progress for every human seat once a game ends. */
import { loadProfile, saveProfile } from './profile';
import { applyGameResult, SEASON_LEADERBOARD, seasonPointsForGame } from './progression';
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
      // WHY: loadProfile ignores rows the client created itself, so a
      // pre-seeded profile is never carried into the server-owned one.
      const current = loadProfile(nk, seat.id).progress;
      let next = applyGameResult(current, score.rank, seatCount, humans);
      try {
        next = { ...next, quests: applyGameToQuests(next.quests, gameStats(s.game, s.log, score.seat), now) };
      } catch (e) {
        logger.warn('quest progress failed for %s: %s', seat.id, String(e));
      }
      saveProfile(nk, seat.id, next);
      const points = seasonPointsForGame(score.rank, seatCount, humans);
      if (points > 0) {
        nk.leaderboardRecordWrite(SEASON_LEADERBOARD, seat.id, seat.name, points, score.rank === 1 ? 1 : 0);
      }
    } catch (e) {
      logger.warn('progress award failed for %s: %s', seat.id, String(e));
    }
  }
}
