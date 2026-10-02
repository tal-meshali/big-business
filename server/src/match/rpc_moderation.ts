/**
 * Moderation of custom card art, for the operator (server-to-server with the
 * runtime http_key, like set_remote_config). The queue holds pictures the
 * scan was unsure about, pictures uploaded while no scanner is configured,
 * and reported ones. A refusal (or a DMCA takedown) gives the uploader a
 * strike; at STRIKES_TO_BAN their uploads stop (repeat-infringer policy).
 */
import { isArtHash, STRIKES_TO_BAN, type ArtStatus } from './designer';
import { ART_QUEUE_COLLECTION, dequeueArt, readArt, readStanding, writeArt, writeStanding } from './designer_store';
import { parseBody, readInt, readString, reject, requireServer } from './input';
import { SYSTEM_USER } from './protocol';

/** RPC moderation_queue {limit?, cursor?}: queued pictures, oldest first, with their image data. */
export const rpcModerationQueue: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  requireServer(ctx);
  const req = parseBody(payload);
  const limit = readInt(req, 'limit', 1, 50, 20);
  const cursor = readString(req, 'cursor', 512);
  const page = nk.storageList(SYSTEM_USER, ART_QUEUE_COLLECTION, limit, cursor || undefined);
  const objects = page.objects || [];
  const arts = readArt(nk, objects.map((o) => o.key));
  const items = objects.map((o) => {
    const a = arts[o.key];
    return { hash: o.key, ...(o.value as object), part: a ? a.art.part : '', status: a ? a.art.status : 'rejected', data: a ? a.art.data : '' };
  });
  return JSON.stringify({ items, cursor: page.cursor || '' });
};

/**
 * RPC moderate_card_art {hash, verdict: "approve" | "reject", strike?, note?}:
 * decides a queued picture. A refusal deletes the image data and, unless
 * `strike` is false, adds a strike to the uploader. Decks that use a refused
 * picture show the default drawing for that part from then on.
 */
export const rpcModerateCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  requireServer(ctx);
  const req = parseBody(payload);
  const hash = req['hash'];
  const verdict = req['verdict'];
  if (!isArtHash(hash)) reject('invalid art');
  if (verdict !== 'approve' && verdict !== 'reject') reject('invalid verdict');
  const found = readArt(nk, [hash])[hash];
  if (!found) reject('art not found');
  const status: ArtStatus = verdict === 'approve' ? 'approved' : 'rejected';
  writeArt(nk, hash, { ...found.art, status, reports: 0, data: status === 'rejected' ? '' : found.art.data }, found.version);
  dequeueArt(nk, hash);
  let strikes = 0;
  if (status === 'rejected' && req['strike'] !== false) {
    // Two decisions on one uploader at once: retry once on the newer row.
    for (let attempt = 0; attempt < 2; attempt++) {
      const s = readStanding(nk, found.art.owner);
      strikes = s.standing.strikes + 1;
      try {
        writeStanding(nk, found.art.owner, { ...s.standing, strikes }, s.version);
        break;
      } catch (e) {
        if (attempt === 1) throw e;
      }
    }
  }
  logger.info('card art %s %s (%s); owner %s strikes %d', hash.slice(0, 12), status, readString(req, 'note', 200) || '-', found.art.owner, strikes);
  return JSON.stringify({ hash, status, strikes, banned: strikes >= STRIKES_TO_BAN });
};
