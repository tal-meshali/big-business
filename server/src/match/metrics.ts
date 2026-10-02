/**
 * Storage for analytics.ts: the per-player row and the per-install-day
 * cohort counts. Every call is best effort: a storage failure is logged and
 * never reaches the player or breaks a match.
 */
import {
  ANALYTICS_COLLECTION,
  ANALYTICS_USER_KEY,
  applyDelta,
  COHORT_COLLECTION,
  cohortReport,
  firstSight,
  markActive,
  normalizeCohort,
  normalizeUserRow,
  reachMilestone,
  recentDays,
  type CohortDelta,
  type CohortReport,
  type Milestone,
  type Step,
  type UserRow,
} from './analytics';
import { SYSTEM_USER } from './protocol';

/** Tries for a cohort update when other players' writes race it. */
const COHORT_RETRIES = 4;

/** Account creation time in ms (Nakama reports seconds; ms is accepted too). */
function createdMs(nk: nkruntime.Nakama, userId: string): number {
  const user = nk.usersGetId([userId])[0];
  if (!user || typeof user.createTime !== 'number') return 0;
  return user.createTime < 1e12 ? user.createTime * 1000 : user.createTime;
}

function addToCohort(nk: nkruntime.Nakama, day: string, delta: CohortDelta): void {
  for (let attempt = 0; attempt < COHORT_RETRIES; attempt++) {
    const row = nk.storageRead([{ collection: COHORT_COLLECTION, key: day, userId: SYSTEM_USER }])[0];
    const value = applyDelta(normalizeCohort(row ? row.value : null), delta);
    try {
      nk.storageWrite([
        { collection: COHORT_COLLECTION, key: day, userId: SYSTEM_USER, value, version: row ? row.version : '*', permissionRead: 0, permissionWrite: 0 },
      ]);
      return;
    } catch (e) {
      // Version conflict: another player's event landed first; re-read.
    }
  }
  throw new Error('cohort update kept conflicting');
}

/**
 * Runs one step against the player's row. WHY the user row is written
 * first and conditionally: if two events for the same player race, only
 * one wins the row, so a cohort count is never added twice.
 */
function track(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, nowMs: number, step: (row: UserRow | null) => Step): void {
  try {
    const stored = nk.storageRead([{ collection: ANALYTICS_COLLECTION, key: ANALYTICS_USER_KEY, userId }])[0];
    const result = step(stored ? normalizeUserRow(stored.value) : null);
    if (!result.changed) return;
    nk.storageWrite([
      {
        collection: ANALYTICS_COLLECTION,
        key: ANALYTICS_USER_KEY,
        userId,
        value: result.row,
        version: stored ? stored.version : '*',
        permissionRead: 0,
        permissionWrite: 0,
      },
    ]);
    if (result.delta) addToCohort(nk, result.row.installDay, result.delta);
  } catch (e) {
    logger.warn('analytics for %s skipped: %s', userId, String(e));
  }
}

/** The player opened the app (or finished a game) today. */
export function trackActive(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, nowMs: number): void {
  track(nk, logger, userId, nowMs, (row) => (row ? markActive(row, nowMs) : firstSight(createdMs(nk, userId), nowMs)));
}

/** The player reached a funnel step (first tutorial, first game, ...). */
export function trackMilestone(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, m: Milestone, nowMs: number): void {
  track(nk, logger, userId, nowMs, (row) => {
    if (row) return reachMilestone(row, m, nowMs);
    // A step before the player was ever seen also counts as their first sight.
    const first = firstSight(createdMs(nk, userId), nowMs);
    const reached = reachMilestone(first.row, m, nowMs);
    const delta = first.delta || reached.delta ? { ...(first.delta || {}), ...(reached.delta || {}) } : null;
    return { row: reached.row, delta, changed: true };
  });
}

/** Cohort counts for the last `days` install days, newest first. */
export function readCohorts(nk: nkruntime.Nakama, nowMs: number, days: number): CohortReport[] {
  const keys = recentDays(nowMs, days);
  const rows = nk.storageRead(keys.map((key) => ({ collection: COHORT_COLLECTION, key, userId: SYSTEM_USER })));
  const byKey: { [day: string]: unknown } = {};
  for (const r of rows) byKey[r.key] = r.value;
  return keys.map((day) => cohortReport(day, normalizeCohort(byKey[day])));
}
