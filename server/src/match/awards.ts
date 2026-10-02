/** Writes XP, levels, season points and quest progress for every human seat once a game ends. */
import { trackActive, trackMilestone } from './metrics';
import { loadProfile, saveProfile } from './profile';
import { applyForfeit, applyGameResult, SEASON_LEADERBOARD, seasonPointsForGame } from './progression';
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
      // WHY: loadProfile ignores rows the client created itself, so a
      // pre-seeded profile is never carried into the server-owned one.
      const current = loadProfile(nk, seat.id).progress;
      let next = applyGameResult(current, score.rank, seatCount, humans);
      // WHY no quest credit for the tutorial (a scripted game anyone can
      // replay) or for a seat that ended as a bot after repeated timeouts:
      // the cosmetic track must not be farmable by idling or replaying.
      const earnsQuests = !s.params.tutorial && !seat.isBot;
      try {
        if (earnsQuests) next = { ...next, quests: applyGameToQuests(next.quests, gameStats(s.game, s.log, score.seat, humans), now) };
      } catch (e) {
        logger.warn('quest progress failed for %s: %s', seat.id, String(e));
      }
      saveProfile(nk, seat.id, next);
      const points = seasonPointsForGame(score.rank, seatCount, humans);
      if (points > 0) {
        nk.leaderboardRecordWrite(SEASON_LEADERBOARD, seat.id, seat.name, points, score.rank === 1 ? 1 : 0);
      }
      trackGame(nk, logger, seat.id, s.params.tutorial, humans, now);
    } catch (e) {
      logger.warn('progress award failed for %s: %s', seat.id, String(e));
    }
  }
}

/** Funnel steps for a finished game (analytics.ts); each counts once per player. */
function trackGame(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, tutorial: boolean, humans: number, now: number): void {
  trackActive(nk, logger, userId, now);
  if (tutorial) {
    trackMilestone(nk, logger, userId, 'tutorial', now);
    return;
  }
  trackMilestone(nk, logger, userId, 'firstGame', now);
  if (humans >= 2) trackMilestone(nk, logger, userId, 'peopleGame', now);
}

/** Records a forfeit on the player's profile. Best effort, like awardProgress. */
export function awardForfeit(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string): void {
  try {
    saveProfile(nk, userId, applyForfeit(loadProfile(nk, userId).progress));
  } catch (e) {
    logger.warn('forfeit record failed for %s: %s', userId, String(e));
  }
}
