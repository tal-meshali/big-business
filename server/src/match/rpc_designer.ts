/**
 * Designer RPCs for players: the Designer screen's state, the age answer,
 * uploading and clearing deck parts, picking the deck for private rooms,
 * fetching art by hash, and reporting a custom card. designer.ts holds the
 * rules, designer_store.ts the storage.
 */
import { scanArt } from './art_scan';
import {
  answerAge,
  BACK_TEMPLATE,
  checkArt,
  DESIGNER_SLOTS,
  isArtHash,
  PARTS,
  setPart,
  uploadBlocker,
  WINDOW_TEMPLATE,
  type ArtStatus,
} from './designer';
import {
  deckSlots,
  enqueueArt,
  ownsDesigner,
  readArt,
  readDecks,
  readStanding,
  writeArt,
  writeDecks,
  writeStanding,
  type ArtRow,
} from './designer_store';
import { MATCH_ID_MAX, parseBody, readString, reject, requireUser, type Body } from './input';
import { checkRate } from './ratelimit';
import { readRemoteConfig } from './rpc_config';
import { UNLOCKS } from './store';

/** An upload payload: a 64 KB image in base64 plus a few fields. */
const UPLOAD_MAX_CHARS = 90_000;
/** Hashes one get_card_art call may ask for: one deck. */
const FETCH_MAX = PARTS.length;
/** Reports that hide an approved picture until a person looks at it again. */
export const REPORTS_TO_HIDE = 3;

const BLOCKER_TEXT: { [k: string]: string } = {
  not_owned: 'Designer is not unlocked',
  age_unknown: 'age not set',
  too_young: 'uploads are not available at your age',
  banned: 'uploads are off for this account',
};

function requireEnabled(nk: nkruntime.Nakama): void {
  if (!readRemoteConfig(nk).designerEnabled) reject('Designer is switched off');
}

function readSlot(req: Body, slots: number): number {
  const v = req['slot'];
  if (typeof v !== 'number' || Math.floor(v) !== v || v < 0 || v >= slots) reject('invalid slot');
  return v;
}

function readPart(req: Body): string {
  const part = readString(req, 'part', 4);
  if (PARTS.indexOf(part) < 0) reject('invalid part');
  return part;
}

/** RPC designer_state: everything the Designer screen shows. */
export const rpcDesignerState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const owned = ownsDesigner(nk, userId);
  const standing = readStanding(nk, userId).standing;
  const row = readDecks(nk, userId).row;
  const slots = owned ? DESIGNER_SLOTS : 0;
  const decks = row.decks.slice(0, slots);
  const hashes: string[] = [];
  for (const d of decks) for (const h of [d.back].concat(d.art)) if (h && hashes.indexOf(h) < 0) hashes.push(h);
  const arts = readArt(nk, hashes);
  const status = (h: string | null): ArtStatus | null => (h ? (arts[h] ? arts[h].art.status : 'rejected') : null);
  return JSON.stringify({
    enabled: readRemoteConfig(nk).designerEnabled,
    owned,
    productId: (UNLOCKS[0] as { productId: string }).productId,
    slots,
    ageBracket: standing.ageBracket,
    blocker: uploadBlocker(owned, standing),
    decks: decks.map((d) => ({ back: d.back, backStatus: status(d.back), art: d.art, artStatus: d.art.map(status) })),
    active: row.active < slots ? row.active : -1,
    templates: { back: BACK_TEMPLATE, window: WINDOW_TEMPLATE },
  });
};

/** RPC set_age_bracket {bracket, region}: the neutral age screen's answer (decision D4). */
export const rpcSetAgeBracket: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  checkRate(nk, userId, 'set_age_bracket', Date.now());
  const current = readStanding(nk, userId);
  const next = answerAge(current.standing, req['bracket'], req['region']);
  if (!next) reject('invalid age');
  try {
    writeStanding(nk, userId, next, current.version);
  } catch (e) {
    reject('try again');
  }
  return JSON.stringify({ ageBracket: next.ageBracket, blocker: uploadBlocker(ownsDesigner(nk, userId), next) });
};

/**
 * RPC upload_card_art {slot, part, image}: stores one part of a deck.
 * `image` is a base64 WebP at the part's template size. A new picture is
 * scanned; it shows to others only once approved (by the scan or a person).
 * Returns {hash, status}.
 */
export const rpcUploadCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  requireEnabled(nk);
  const req = parseBody(payload, UPLOAD_MAX_CHARS);
  const now = Date.now();
  checkRate(nk, userId, 'upload_card_art', now);
  const blocker = uploadBlocker(ownsDesigner(nk, userId), readStanding(nk, userId).standing);
  if (blocker) reject(BLOCKER_TEXT[blocker] || 'not allowed');
  const slot = readSlot(req, deckSlots(nk, userId));
  const part = readPart(req);
  const image = req['image'];
  const problem = checkArt(part, image);
  if (problem) reject(problem);
  const data = image as string;
  const hash = nk.sha256Hash(data).toLowerCase();

  let existing = readArt(nk, [hash])[hash];
  if (!existing) {
    const scan = scanArt(nk, logger, ctx.env, data);
    const art: ArtRow = { owner: userId, part, data: scan.status === 'rejected' ? '' : data, status: scan.status, createdAt: now, reports: 0 };
    try {
      writeArt(nk, hash, art, '*');
      if (scan.status === 'pending') enqueueArt(nk, hash, { reason: scan.scanned ? 'scan' : 'unscanned', owner: userId, at: now, reports: 0 });
      existing = { art, version: '' };
    } catch (e) {
      // Someone uploaded the same picture at the same moment: use their row.
      existing = readArt(nk, [hash])[hash];
      if (!existing) reject('try again');
    }
    logger.info('card art %s by %s: %s', hash.slice(0, 12), userId, existing.art.status);
  }
  if (existing.art.status === 'rejected') reject('this picture cannot be used');

  const decks = readDecks(nk, userId);
  try {
    writeDecks(nk, userId, setPart(decks.row, slot, part, hash), decks.version);
  } catch (e) {
    reject('try again');
  }
  return JSON.stringify({ hash, status: existing.art.status });
};

/** RPC clear_deck_part {slot, part}: back to the default drawing for that part. */
export const rpcClearDeckPart: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const slot = readSlot(req, deckSlots(nk, userId));
  const part = readPart(req);
  const decks = readDecks(nk, userId);
  try {
    writeDecks(nk, userId, setPart(decks.row, slot, part, null), decks.version);
  } catch (e) {
    reject('try again');
  }
  return JSON.stringify({ ok: true });
};

/** RPC select_deck {slot}: the deck shown in rooms this player creates; -1 for none. */
export const rpcSelectDeck: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const slots = deckSlots(nk, userId);
  const slot = req['slot'] === -1 ? -1 : readSlot(req, slots);
  const decks = readDecks(nk, userId);
  try {
    writeDecks(nk, userId, { decks: decks.row.decks, active: slot }, decks.version);
  } catch (e) {
    reject('try again');
  }
  return JSON.stringify({ active: slot });
};

/**
 * RPC get_card_art {hashes}: the base64 pictures for up to one deck of
 * hashes. Approved art is served to anyone who has its hash (a 256-bit
 * name only room members receive); pending art only to its uploader, for
 * the preview. Hashes not served are left out.
 */
export const rpcGetCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const list = parseBody(payload)['hashes'];
  if (!Array.isArray(list) || list.length === 0 || list.length > FETCH_MAX) reject('invalid hashes');
  const hashes: string[] = [];
  for (const h of list as unknown[]) {
    if (!isArtHash(h)) reject('invalid hashes');
    if (hashes.indexOf(h) < 0) hashes.push(h);
  }
  checkRate(nk, userId, 'get_card_art', Date.now());
  const arts = readArt(nk, hashes);
  const out: { [hash: string]: string } = {};
  for (const h of hashes) {
    const a = arts[h];
    if (!a || !a.art.data) continue;
    if (a.art.status === 'approved' || (a.art.status === 'pending' && a.art.owner === userId)) out[h] = a.art.data;
  }
  return JSON.stringify({ art: out });
};

/**
 * RPC report_card_art {hash, matchId?}: puts a custom card in front of a
 * moderator (Apple 1.2 / Play UGC). After REPORTS_TO_HIDE reports the
 * picture stops showing until someone reviews it.
 */
export const rpcReportCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const hash = req['hash'];
  if (!isArtHash(hash)) reject('invalid art');
  const matchId = readString(req, 'matchId', MATCH_ID_MAX);
  const now = Date.now();
  checkRate(nk, userId, 'report_card_art', now);
  const found = readArt(nk, [hash])[hash];
  if (!found || found.art.status === 'rejected') return JSON.stringify({ ok: true });
  const reports = found.art.reports + 1;
  const status: ArtStatus = found.art.status === 'approved' && reports >= REPORTS_TO_HIDE ? 'pending' : found.art.status;
  try {
    writeArt(nk, hash, { ...found.art, reports, status }, found.version);
  } catch (e) {
    reject('try again');
  }
  enqueueArt(nk, hash, { reason: 'report', owner: found.art.owner, at: now, reports });
  logger.info('card art %s reported by %s in %s (x%d)', hash.slice(0, 12), userId, matchId || '-', reports);
  return JSON.stringify({ ok: true });
};
