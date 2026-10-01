import { describe, expect, it } from 'vitest';
import { addReport, REPORT_ENTRIES_MAX, SERVER_COLLECTIONS, touchesServerCollection } from './reports';

describe('addReport', () => {
  const entry = (reason: string, note: string) => ({ reason, matchId: 'm', note, at: 1 });

  it('keeps every earlier report instead of overwriting it', () => {
    const first = addReport(null, 'r', 'x', entry('cheating', 'stalled the game'));
    const second = addReport(first, 'r', 'x', entry('other', ''));
    expect(second.count).toBe(2);
    expect(second.entries.map((e) => e.reason)).toEqual(['cheating', 'other']);
    expect(second.entries[0]!.note).toBe('stalled the game');
  });

  it('caps the stored entries but keeps counting', () => {
    let row: unknown = null;
    for (let i = 0; i < REPORT_ENTRIES_MAX + 5; i++) row = addReport(row, 'r', 'x', entry('other', `n${i}`));
    const r = row as ReturnType<typeof addReport>;
    expect(r.count).toBe(REPORT_ENTRIES_MAX + 5);
    expect(r.entries.length).toBe(REPORT_ENTRIES_MAX);
    expect(r.entries[0]!.note).toBe('n0');
  });

  it('treats malformed rows as empty', () => {
    expect(addReport({ count: -3, entries: 'x' }, 'r', 'x', entry('name', '')).count).toBe(1);
  });
});

describe('touchesServerCollection', () => {
  it('flags any client write or delete in a server-only collection', () => {
    for (const c of SERVER_COLLECTIONS) expect(touchesServerCollection([{ collection: 'notes' }, { collection: c }])).toBe(true);
    expect(touchesServerCollection([{ collection: 'settings' }])).toBe(false);
    expect(touchesServerCollection([])).toBe(false);
    expect(touchesServerCollection(undefined)).toBe(false);
  });

  it('covers the profile and rate-limit rows', () => {
    expect(SERVER_COLLECTIONS).toContain('profile');
    expect(SERVER_COLLECTIONS).toContain('ratelimit');
  });
});
