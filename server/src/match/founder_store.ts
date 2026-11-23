/**
 * Storage for the Founder unlock: the player's companies row and the queue
 * of reported company names. Both collections are server-only (reports.ts
 * SERVER_COLLECTIONS); founder.ts holds the rules. Logo pictures live in the
 * shared art store (designer_store.ts).
 */
import { normalizeCompaniesRow, type CompaniesRow } from './founder';
import { SYSTEM_USER } from './protocol';
import { readOwned } from './purchases';
import { FOUNDER, PLUS } from './store';

export const COMPANIES_COLLECTION = 'founder';
export const COMPANIES_KEY = 'companies';
export const COMPANY_QUEUE_COLLECTION = 'company_queue';

/** True when the player may create companies: Founder, or Plus which includes it. */
export function ownsFounder(nk: nkruntime.Nakama, userId: string): boolean {
  const owned = readOwned(nk, userId).owned;
  return owned.indexOf(FOUNDER) >= 0 || owned.indexOf(PLUS) >= 0;
}

/** The companies row with its storage version. A lost unlock hides the row without deleting it. */
export function readCompanies(nk: nkruntime.Nakama, userId: string): { row: CompaniesRow; version: string | null } {
  const r = nk.storageRead([{ collection: COMPANIES_COLLECTION, key: COMPANIES_KEY, userId }])[0];
  if (!r || r.permissionWrite !== 0) return { row: normalizeCompaniesRow(null), version: r ? r.version : null };
  return { row: normalizeCompaniesRow(r.value), version: r.version };
}

/** Writes the companies row; with a version it fails (as 'try again') when the row changed. */
export function writeCompanies(nk: nkruntime.Nakama, userId: string, row: CompaniesRow, version: string | null): void {
  nk.storageWrite([{ collection: COMPANIES_COLLECTION, key: COMPANIES_KEY, userId, value: row, version: version === null ? '*' : version, permissionRead: 1, permissionWrite: 0 }]);
}

export interface CompanyQueueRow {
  /** The names as they were when reported, so the operator sees what players saw. */
  names: string[];
  reports: number;
  at: number;
}

/** Adds a report of `owner`'s company names to the queue (one row per owner). */
export function enqueueCompanies(nk: nkruntime.Nakama, owner: string, names: string[], now: number): number {
  const prev = nk.storageRead([{ collection: COMPANY_QUEUE_COLLECTION, key: owner, userId: SYSTEM_USER }])[0];
  const before = prev && typeof (prev.value as { reports?: unknown }).reports === 'number' ? ((prev.value as { reports: number }).reports) : 0;
  const row: CompanyQueueRow = { names, reports: before + 1, at: now };
  nk.storageWrite([{ collection: COMPANY_QUEUE_COLLECTION, key: owner, userId: SYSTEM_USER, value: row, permissionRead: 0, permissionWrite: 0 }]);
  return row.reports;
}

export function dequeueCompanies(nk: nkruntime.Nakama, owner: string): void {
  nk.storageDelete([{ collection: COMPANY_QUEUE_COLLECTION, key: owner, userId: SYSTEM_USER }]);
}
