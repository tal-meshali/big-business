/**
 * Storage for the Designer unlock: the player's deck row and standing row,
 * the shared art rows and the moderation queue. Every collection here is
 * server-only (reports.ts SERVER_COLLECTIONS); designer.ts holds the rules.
 *
 * WHY art rows are keyed by content hash under the system user: identical
 * uploads share one stored image and one moderation verdict, so a picture
 * refused once is refused for everyone, and a hash is an immutable name the
 * client can cache forever (research 05 section 3).
 */
import { DESIGNER_SLOTS, normalizeDeckRow, normalizeStanding, type ArtStatus, type DeckRow, type Standing } from './designer';
import { SYSTEM_USER } from './protocol';
import { readOwned } from './purchases';
import { DESIGNER } from './store';

export const DECK_COLLECTION = 'designer';
export const DECK_KEY = 'decks';
export const STANDING_COLLECTION = 'standing';
export const STANDING_KEY = 'account';
export const ART_COLLECTION = 'card_art';
export const ART_QUEUE_COLLECTION = 'art_queue';

export interface ArtRow {
  /** User who first uploaded this picture. */
  owner: string;
  part: string;
  /** Base64 WebP; emptied once the picture is refused, to keep no copy. */
  data: string;
  status: ArtStatus;
  createdAt: number;
  /** Reports from players since the last review. */
  reports: number;
}

export interface QueueRow {
  /** 'unscanned' (no scanner configured), 'scan' (uncertain verdict) or 'report'. */
  reason: string;
  owner: string;
  at: number;
  reports: number;
}

export function ownsDesigner(nk: nkruntime.Nakama, userId: string): boolean {
  return readOwned(nk, userId).owned.indexOf(DESIGNER) >= 0;
}

/** Deck slots for this player; 0 without the unlock. */
export function deckSlots(nk: nkruntime.Nakama, userId: string): number {
  return ownsDesigner(nk, userId) ? DESIGNER_SLOTS : 0;
}

/**
 * The deck row with its storage version. Read at the full Designer slot
 * count so a lost entitlement (refund) hides decks without deleting them.
 */
export function readDecks(nk: nkruntime.Nakama, userId: string): { row: DeckRow; version: string | null } {
  const r = nk.storageRead([{ collection: DECK_COLLECTION, key: DECK_KEY, userId }])[0];
  if (!r || r.permissionWrite !== 0) return { row: normalizeDeckRow(null, DESIGNER_SLOTS), version: r ? r.version : null };
  return { row: normalizeDeckRow(r.value, DESIGNER_SLOTS), version: r.version };
}

/** Writes the deck row; with a version it fails (as 'try again') when the row changed. */
export function writeDecks(nk: nkruntime.Nakama, userId: string, row: DeckRow, version: string | null): void {
  nk.storageWrite([{ collection: DECK_COLLECTION, key: DECK_KEY, userId, value: row, version: version === null ? '*' : version, permissionRead: 1, permissionWrite: 0 }]);
}

export function readStanding(nk: nkruntime.Nakama, userId: string): { standing: Standing; version: string | null } {
  const r = nk.storageRead([{ collection: STANDING_COLLECTION, key: STANDING_KEY, userId }])[0];
  if (!r || r.permissionWrite !== 0) return { standing: normalizeStanding(null), version: r ? r.version : null };
  return { standing: normalizeStanding(r.value), version: r.version };
}

export function writeStanding(nk: nkruntime.Nakama, userId: string, standing: Standing, version?: string | null): void {
  const req: nkruntime.StorageWriteRequest = { collection: STANDING_COLLECTION, key: STANDING_KEY, userId, value: standing, permissionRead: 1, permissionWrite: 0 };
  if (version !== undefined) req.version = version === null ? '*' : version;
  nk.storageWrite([req]);
}

export function normalizeArtRow(raw: unknown): ArtRow | null {
  const o = (typeof raw === 'object' && raw !== null ? raw : null) as { [k: string]: unknown } | null;
  if (!o || typeof o['owner'] !== 'string' || typeof o['part'] !== 'string') return null;
  const status = o['status'] === 'approved' || o['status'] === 'rejected' ? (o['status'] as ArtStatus) : 'pending';
  return {
    owner: o['owner'] as string,
    part: o['part'] as string,
    data: typeof o['data'] === 'string' ? (o['data'] as string) : '',
    status,
    createdAt: typeof o['createdAt'] === 'number' ? (o['createdAt'] as number) : 0,
    reports: typeof o['reports'] === 'number' && (o['reports'] as number) > 0 ? Math.floor(o['reports'] as number) : 0,
  };
}

/** Art rows by hash; hashes with no row are absent from the result. */
export function readArt(nk: nkruntime.Nakama, hashes: ReadonlyArray<string>): { [hash: string]: { art: ArtRow; version: string } } {
  const out: { [hash: string]: { art: ArtRow; version: string } } = {};
  if (hashes.length === 0) return out;
  const rows = nk.storageRead(hashes.map((key) => ({ collection: ART_COLLECTION, key, userId: SYSTEM_USER })));
  for (const r of rows) {
    const art = normalizeArtRow(r.value);
    if (art) out[r.key] = { art, version: r.version };
  }
  return out;
}

/** Writes an art row; `version` '*' only creates it, so a racing first upload loses cleanly. */
export function writeArt(nk: nkruntime.Nakama, hash: string, art: ArtRow, version: string): void {
  nk.storageWrite([{ collection: ART_COLLECTION, key: hash, userId: SYSTEM_USER, value: art, version, permissionRead: 0, permissionWrite: 0 }]);
}

export function enqueueArt(nk: nkruntime.Nakama, hash: string, row: QueueRow): void {
  nk.storageWrite([{ collection: ART_QUEUE_COLLECTION, key: hash, userId: SYSTEM_USER, value: row, permissionRead: 0, permissionWrite: 0 }]);
}

export function dequeueArt(nk: nkruntime.Nakama, hash: string): void {
  nk.storageDelete([{ collection: ART_QUEUE_COLLECTION, key: hash, userId: SYSTEM_USER }]);
}
