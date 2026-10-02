/**
 * Creates the leaderboards on every start (creating an existing one is a
 * no-op): the monthly season and the weekly club league with each player's
 * part in it.
 */
import { CLUB_LEAGUE, CLUB_RESET, CLUB_WEEK } from './clubs';
import { SEASON_LEADERBOARD } from './progression';

export function createLeaderboards(nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  // Authoritative, descending, points accumulate. nkruntime is types only at
  // runtime, so pass the enum string values.
  const boards: Array<[string, string]> = [
    // Monthly season: resets on the 1st.
    [SEASON_LEADERBOARD, '0 0 1 * *'],
    [CLUB_LEAGUE, CLUB_RESET],
    [CLUB_WEEK, CLUB_RESET],
  ];
  for (const [id, reset] of boards) {
    try {
      nk.leaderboardCreate(id, true, 'descending' as nkruntime.SortOrder, 'increment' as nkruntime.Operator, reset);
    } catch (e) {
      logger.warn('leaderboard create %s: %s', id, String(e));
    }
  }
}
