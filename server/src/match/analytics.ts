/**
 * Server-side analytics: D1 / D7 retention and the first-session funnel,
 * counted per install-day cohort. Pure functions; storage is in metrics.ts.
 *
 * WHY on the server and in Nakama storage (not a client analytics SDK): the
 * audience is mixed (decision D4), so nothing here is personal or sent to a
 * third party. Each player has one server-only row with their install day,
 * the day offsets they were active on and when they reached each funnel
 * step; each install day has one row of counts. Crashlytics and any client
 * SDK stay a local task (docs/TODO-local.md G).
 */
import { utcDate } from './progression';

export const ANALYTICS_COLLECTION = 'analytics';
export const ANALYTICS_USER_KEY = 'user';
export const COHORT_COLLECTION = 'analytics_cohort';
/** Days after install a player is followed; later activity writes nothing. */
export const TRACKED_DAYS = 30;
const DAY_MS = 86_400_000;

/** Funnel steps after install, in the order a new player usually meets them. */
export type Milestone = 'tutorial' | 'firstGame' | 'peopleGame' | 'purchase';
export const MILESTONES: ReadonlyArray<Milestone> = ['tutorial', 'firstGame', 'peopleGame', 'purchase'];

export interface UserRow {
  /** UTC date the account was created. */
  installDay: string;
  /** Account was older than TRACKED_DAYS when first seen: counted nowhere. */
  legacy: boolean;
  /** Day offsets since install the player was active on (0 = install day). */
  days: number[];
  /** Day offset each funnel step was first reached on. */
  milestones: { [m: string]: number };
}

export interface Cohort {
  installs: number;
  d1: number;
  d7: number;
  tutorial: number;
  firstGame: number;
  peopleGame: number;
  purchase: number;
}

export type CohortDelta = Partial<Cohort>;

export function emptyCohort(): Cohort {
  return { installs: 0, d1: 0, d7: 0, tutorial: 0, firstGame: 0, peopleGame: 0, purchase: 0 };
}

/** Whole UTC days from the install day to `nowMs`. */
export function dayOffset(installDay: string, nowMs: number): number {
  const start = Date.parse(installDay + 'T00:00:00Z');
  if (!isFinite(start)) return -1;
  return Math.floor((Date.parse(utcDate(nowMs) + 'T00:00:00Z') - start) / DAY_MS);
}

export function normalizeUserRow(raw: unknown): UserRow | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const r = raw as { [k: string]: unknown };
  const installDay = typeof r['installDay'] === 'string' ? (r['installDay'] as string).slice(0, 10) : '';
  if (!isFinite(Date.parse(installDay + 'T00:00:00Z'))) return null;
  const days: number[] = [];
  if (Array.isArray(r['days'])) {
    for (const d of r['days'] as unknown[]) if (typeof d === 'number' && d >= 0 && d <= TRACKED_DAYS && days.indexOf(d) < 0) days.push(d);
  }
  const milestones: { [m: string]: number } = {};
  const ms = r['milestones'];
  if (typeof ms === 'object' && ms !== null) {
    for (const m of MILESTONES) {
      const v = (ms as { [k: string]: unknown })[m];
      if (typeof v === 'number' && v >= 0) milestones[m] = v;
    }
  }
  return { installDay, legacy: r['legacy'] === true, days, milestones };
}

export interface Step {
  row: UserRow;
  /** Counts to add to the install day's cohort; null when none. */
  delta: CohortDelta | null;
  /** Whether the user row must be written. */
  changed: boolean;
}

/**
 * First sight of a player: their row, counting the install unless the
 * account predates tracking (it existed before this code shipped).
 */
export function firstSight(createMs: number, nowMs: number): Step {
  const installDay = utcDate(createMs > 0 && createMs <= nowMs ? createMs : nowMs);
  const offset = dayOffset(installDay, nowMs);
  if (offset > TRACKED_DAYS) return { row: { installDay, legacy: true, days: [], milestones: {} }, delta: null, changed: true };
  const row: UserRow = { installDay, legacy: false, days: [offset], milestones: {} };
  const delta: CohortDelta = { installs: 1 };
  if (offset === 1) delta.d1 = 1;
  if (offset === 7) delta.d7 = 1;
  return { row, delta, changed: true };
}

/** Marks today active. D1 counts activity on day 1, D7 on day 7 (the classic definition). */
export function markActive(row: UserRow, nowMs: number): Step {
  const offset = dayOffset(row.installDay, nowMs);
  if (row.legacy || offset < 0 || offset > TRACKED_DAYS || row.days.indexOf(offset) >= 0) return { row, delta: null, changed: false };
  const next: UserRow = { ...row, days: row.days.concat([offset]) };
  let delta: CohortDelta | null = null;
  if (offset === 1) delta = { d1: 1 };
  if (offset === 7) delta = { d7: 1 };
  return { row: next, delta, changed: true };
}

/** Records the first time a funnel step is reached; later ones change nothing. */
export function reachMilestone(row: UserRow, m: Milestone, nowMs: number): Step {
  const offset = dayOffset(row.installDay, nowMs);
  if (row.legacy || offset < 0 || offset > TRACKED_DAYS || row.milestones[m] !== undefined) return { row, delta: null, changed: false };
  const milestones: { [k: string]: number } = {};
  for (const k in row.milestones) milestones[k] = row.milestones[k] as number;
  milestones[m] = offset;
  const delta: CohortDelta = {};
  delta[m] = 1;
  return { row: { ...row, milestones }, delta, changed: true };
}

export function normalizeCohort(raw: unknown): Cohort {
  const out = emptyCohort();
  if (typeof raw !== 'object' || raw === null) return out;
  const r = raw as { [k: string]: unknown };
  for (const k of Object.keys(out) as Array<keyof Cohort>) {
    const v = r[k];
    if (typeof v === 'number' && isFinite(v) && v > 0) out[k] = Math.floor(v);
  }
  return out;
}

export function applyDelta(c: Cohort, d: CohortDelta): Cohort {
  const out = { ...c };
  for (const k of Object.keys(d) as Array<keyof Cohort>) out[k] = out[k] + (d[k] || 0);
  return out;
}

/** Install days (YYYY-MM-DD) of the last `count` days, newest first. */
export function recentDays(nowMs: number, count: number): string[] {
  const out: string[] = [];
  for (let i = 0; i < count; i++) out.push(utcDate(nowMs - i * DAY_MS));
  return out;
}

export interface CohortReport extends Cohort {
  day: string;
  /** Share of installs, 0..1, rounded to 3 places; null with no installs. */
  d1Rate: number | null;
  d7Rate: number | null;
}

export function cohortReport(day: string, c: Cohort): CohortReport {
  const rate = (n: number): number | null => (c.installs > 0 ? Math.round((n / c.installs) * 1000) / 1000 : null);
  return { day, ...c, d1Rate: rate(c.d1), d7Rate: rate(c.d7) };
}
