/**
 * Storing one uploaded picture in the shared art store: checks it, hashes
 * it, scans a new one and queues it for review when unsure. Used by the
 * Designer (deck parts) and Founder (company logos) uploads, so both share
 * one store, one review queue and one verdict per picture.
 */
import { scanArt } from './art_scan';
import { checkArt, type ArtStatus } from './designer';
import { enqueueArt, readArt, writeArt, type ArtRow } from './designer_store';
import { refuse, required } from './input';

/**
 * Checks `image` against `part`'s template and stores it (once per content
 * hash). Rejects when the picture is malformed or was refused before.
 */
export function storeArt(nk: nkruntime.Nakama, logger: nkruntime.Logger, env: { [key: string]: string } | undefined, userId: string, part: string, image: unknown, now: number): { hash: string; status: ArtStatus } {
  refuse(checkArt(part, image));
  const data = image as string;
  const hash = nk.sha256Hash(data).toLowerCase();

  let existing = readArt(nk, [hash])[hash];
  if (!existing) {
    const scan = scanArt(nk, logger, env, data);
    const art: ArtRow = { owner: userId, part, data: scan.status === 'rejected' ? '' : data, status: scan.status, createdAt: now, reports: 0 };
    try {
      writeArt(nk, hash, art, '*');
      if (scan.status === 'pending') enqueueArt(nk, hash, { reason: scan.scanned ? 'scan' : 'unscanned', owner: userId, at: now, reports: 0 });
      existing = { art, version: '' };
    } catch (e) {
      // Someone uploaded the same picture at the same moment: use their row.
      existing = readArt(nk, [hash])[hash];
    }
    required(existing, 'try again');
    logger.info('%s art %s by %s: %s', part, hash.slice(0, 12), userId, existing.art.status);
  }
  refuse(existing.art.status === 'rejected' ? 'this picture cannot be used' : '');
  return { hash, status: existing.art.status };
}
