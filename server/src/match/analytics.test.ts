import { describe, expect, it } from 'vitest';
import { applyDelta, cohortReport, dayOffset, emptyCohort, firstSight, markActive, normalizeCohort, normalizeUserRow, reachMilestone, recentDays, TRACKED_DAYS } from './analytics';
import { DEFAULT_CONFIG, mergeConfig } from './remote_config';

const DAY = 86_400_000;
const INSTALL = Date.parse('2026-10-02T09:00:00Z');

describe('retention', () => {
  it('counts an install on first sight and D1 / D7 on those days only', () => {
    const first = firstSight(INSTALL, INSTALL + 3_600_000);
    expect(first.delta).toEqual({ installs: 1 });
    expect(first.row).toMatchObject({ installDay: '2026-10-02', days: [0], legacy: false });
    const sameDay = markActive(first.row, INSTALL + 5 * 3_600_000);
    expect(sameDay.changed).toBe(false);
    const d1 = markActive(first.row, INSTALL + DAY);
    expect(d1.delta).toEqual({ d1: 1 });
    expect(markActive(d1.row, INSTALL + DAY + 1000).changed).toBe(false);
    const d3 = markActive(d1.row, INSTALL + 3 * DAY);
    expect(d3.changed).toBe(true);
    expect(d3.delta).toBeNull();
    expect(markActive(d3.row, INSTALL + 7 * DAY).delta).toEqual({ d7: 1 });
  });

  it('uses UTC calendar days, not 24 hours since install', () => {
    const lateNight = Date.parse('2026-10-02T23:30:00Z');
    const row = firstSight(lateNight, lateNight).row;
    expect(markActive(row, lateNight + 3_600_000).delta).toEqual({ d1: 1 });
  });

  it('first seen a day after install still counts the install and D1', () => {
    expect(firstSight(INSTALL, INSTALL + DAY).delta).toEqual({ installs: 1, d1: 1 });
  });

  it('ignores accounts that predate tracking and stops after the tracked window', () => {
    const old = firstSight(INSTALL - 90 * DAY, INSTALL);
    expect(old.row.legacy).toBe(true);
    expect(old.delta).toBeNull();
    expect(markActive(old.row, INSTALL + DAY).changed).toBe(false);
    const row = firstSight(INSTALL, INSTALL).row;
    expect(markActive(row, INSTALL + (TRACKED_DAYS + 1) * DAY).changed).toBe(false);
  });
});

describe('funnel milestones', () => {
  it('count once per player', () => {
    const row = firstSight(INSTALL, INSTALL).row;
    const t = reachMilestone(row, 'tutorial', INSTALL);
    expect(t.delta).toEqual({ tutorial: 1 });
    expect(t.row.milestones).toEqual({ tutorial: 0 });
    expect(reachMilestone(t.row, 'tutorial', INSTALL + DAY).changed).toBe(false);
    expect(reachMilestone(t.row, 'firstGame', INSTALL + DAY).row.milestones).toEqual({ tutorial: 0, firstGame: 1 });
  });
});

describe('storage normalisation', () => {
  it('rejects junk rows and cleans fields', () => {
    expect(normalizeUserRow(null)).toBeNull();
    expect(normalizeUserRow({ installDay: 'soon' })).toBeNull();
    expect(normalizeUserRow({ installDay: '2026-10-02', days: [0, 0, -1, 99, 'x', 3], milestones: { tutorial: 0, bogus: 2 } })).toEqual({
      installDay: '2026-10-02',
      legacy: false,
      days: [0, 3],
      milestones: { tutorial: 0 },
    });
    expect(normalizeCohort({ installs: 3, d1: -2, d7: 'x' })).toEqual({ ...emptyCohort(), installs: 3 });
  });

  it('adds deltas and reports rates', () => {
    const c = applyDelta(applyDelta(emptyCohort(), { installs: 4 }), { d1: 1, firstGame: 3 });
    expect(cohortReport('2026-10-02', c)).toMatchObject({ installs: 4, d1: 1, firstGame: 3, d1Rate: 0.25, d7Rate: 0 });
    expect(cohortReport('2026-10-02', emptyCohort()).d1Rate).toBeNull();
  });

  it('lists recent install days newest first', () => {
    expect(recentDays(INSTALL, 3)).toEqual(['2026-10-02', '2026-10-01', '2026-09-30']);
    expect(dayOffset('2026-09-30', INSTALL)).toBe(2);
  });
});

describe('remote config', () => {
  it('keeps known keys of the right type and clamps numbers', () => {
    const next = mergeConfig(DEFAULT_CONFIG, { shopEnabled: false, pushEnabled: 'no', quickPlayWaitSeconds: 999, pushCooldownMinutes: 2.6, extra: 1 });
    expect(next).toEqual({ ...DEFAULT_CONFIG, shopEnabled: false, quickPlayWaitSeconds: 60, pushCooldownMinutes: 3 });
    expect(Object.keys(next)).not.toContain('extra');
  });

  it('falls back to the base for junk', () => {
    expect(mergeConfig(DEFAULT_CONFIG, null)).toEqual(DEFAULT_CONFIG);
    expect(mergeConfig(DEFAULT_CONFIG, [1, 2])).toEqual(DEFAULT_CONFIG);
  });
});
