/**
 * Designer unlock (decision D5, research 05): custom card art for private
 * rooms. Pure rules only: the age gate, the art templates and their image
 * checks, the deck row, and the automated scan verdict. Storage is in
 * designer_store.ts, the RPCs in rpc_designer.ts and rpc_moderation.ts.
 *
 * WHY the client renders and the server only checks: Nakama's JavaScript
 * runtime cannot decode or resize images. The client crops the player's
 * picture to a fixed template size and encodes it as WebP; the server
 * checks the format, the exact size and the byte budget from the header,
 * hashes it, and never composites anything. The card frame, company name
 * and share count stay drawn by the client around the art window, so a
 * custom design can never hide what a card is.
 */

/** Deck parts: the card back and one art window per company (0..5). */
export const PARTS = ['back', 'c0', 'c1', 'c2', 'c3', 'c4', 'c5'];
export type Part = string;

/** Template size of each part's image in pixels. */
export interface Template {
  width: number;
  height: number;
}

/**
 * The back is the whole card face at 5:7; a company's art window is the
 * 88 x 46 box on the card face (client/scripts/ui/card_view.gd) at 4x.
 */
export const BACK_TEMPLATE: Template = { width: 250, height: 350 };
export const WINDOW_TEMPLATE: Template = { width: 352, height: 184 };

export function templateFor(part: Part): Template {
  return part === 'back' ? BACK_TEMPLATE : WINDOW_TEMPLATE;
}

/** Largest encoded image accepted; a lossy WebP at these sizes is 10 to 40 KB. */
export const ART_MAX_BYTES = 64 * 1024;

/** Deck slots the Designer unlock gives. */
export const DESIGNER_SLOTS = 3;

/** Upload strikes (rejected by a moderator, or a takedown) before uploads stop for good. */
export const STRIKES_TO_BAN = 3;

// ---- Age gate (decision D4) ------------------------------------------------

export const AGE_BRACKETS = ['under13', '13to15', '16plus'];

/**
 * EEA countries, where the age of digital consent is up to 16. WHY all of
 * them at 16: the age differs per member state (13 to 16) and the client's
 * region is only a hint, so the strictest value is the safe default.
 */
const EEA = [
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL',
  'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE', 'IS', 'LI', 'NO',
];

/** A two-letter region code, upper-cased, or '' when it is not one. */
export function normalizeRegion(v: unknown): string {
  if (typeof v !== 'string') return '';
  const r = v.trim().toUpperCase();
  return /^[A-Z]{2}$/.test(r) ? r : '';
}

/** Youngest bracket allowed to upload pictures in this region. */
export function minUploadBracket(region: string): string {
  return EEA.indexOf(region) >= 0 ? '16plus' : '13to15';
}

/** True when a player of `bracket` in `region` may upload pictures. */
export function ageAllowsUpload(bracket: string, region: string): boolean {
  const have = AGE_BRACKETS.indexOf(bracket);
  return have >= 0 && have >= AGE_BRACKETS.indexOf(minUploadBracket(region));
}

/** The server-only standing row: age bracket, region and moderation strikes. */
export interface Standing {
  ageBracket: string;
  region: string;
  strikes: number;
}

export function normalizeStanding(raw: unknown): Standing {
  const o = (typeof raw === 'object' && raw !== null ? raw : {}) as { [k: string]: unknown };
  const ageBracket = typeof o['ageBracket'] === 'string' && AGE_BRACKETS.indexOf(o['ageBracket'] as string) >= 0 ? (o['ageBracket'] as string) : '';
  const strikes = typeof o['strikes'] === 'number' && isFinite(o['strikes'] as number) && (o['strikes'] as number) > 0 ? Math.floor(o['strikes'] as number) : 0;
  return { ageBracket, region: normalizeRegion(o['region']), strikes };
}

/**
 * Applies an age answer. The first answer is stored; later answers may only
 * move to a younger bracket. WHY: a neutral age screen is easy to answer
 * again with an older age, so only the more protective change is taken.
 * Returns null when the answer is refused.
 */
export function answerAge(prev: Standing, bracket: unknown, region: unknown): Standing | null {
  if (typeof bracket !== 'string' || AGE_BRACKETS.indexOf(bracket) < 0) return null;
  if (prev.ageBracket && AGE_BRACKETS.indexOf(bracket) > AGE_BRACKETS.indexOf(prev.ageBracket)) return null;
  const r = normalizeRegion(region);
  return { ageBracket: bracket, region: prev.region || r, strikes: prev.strikes };
}

/** Why this player may not upload, or '' when they may. */
export function uploadBlocker(owned: boolean, standing: Standing): string {
  if (!owned) return 'not_owned';
  if (!standing.ageBracket) return 'age_unknown';
  if (!ageAllowsUpload(standing.ageBracket, standing.region)) return 'too_young';
  if (standing.strikes >= STRIKES_TO_BAN) return 'banned';
  return '';
}

// ---- Images ----------------------------------------------------------------

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

/** Decoded byte length of a padded base64 string. */
export function base64Length(s: string): number {
  const pad = s.endsWith('==') ? 2 : s.endsWith('=') ? 1 : 0;
  return (s.length / 4) * 3 - pad;
}

/** The first `count` bytes of a base64 string (enough to read a header). */
export function base64Prefix(s: string, count: number): number[] {
  const out: number[] = [];
  for (let i = 0; i + 3 < s.length && out.length < count; i += 4) {
    const n = (B64.indexOf(s.charAt(i)) << 18) | (B64.indexOf(s.charAt(i + 1)) << 12) | ((B64.indexOf(s.charAt(i + 2)) & 63) << 6) | (B64.indexOf(s.charAt(i + 3)) & 63);
    out.push((n >> 16) & 255, (n >> 8) & 255, n & 255);
  }
  return out.slice(0, count);
}

function ascii(b: number[], at: number, len: number): string {
  let s = '';
  for (let i = 0; i < len; i++) s += String.fromCharCode(b[at + i] || 0);
  return s;
}

function le(b: number[], at: number, len: number): number {
  let n = 0;
  for (let i = len - 1; i >= 0; i--) n = n * 256 + (b[at + i] || 0);
  return n;
}

/** Width and height from a WebP header (lossy, lossless or extended), or null. */
export function webpSize(b: number[]): Template | null {
  if (b.length < 30 || ascii(b, 0, 4) !== 'RIFF' || ascii(b, 8, 4) !== 'WEBP') return null;
  const chunk = ascii(b, 12, 4);
  if (chunk === 'VP8 ') {
    if (b[23] !== 0x9d || b[24] !== 0x01 || b[25] !== 0x2a) return null;
    return { width: le(b, 26, 2) & 0x3fff, height: le(b, 28, 2) & 0x3fff };
  }
  if (chunk === 'VP8L') {
    if (b[20] !== 0x2f) return null;
    const bits = le(b, 21, 4);
    return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
  }
  if (chunk === 'VP8X') return { width: le(b, 24, 3) + 1, height: le(b, 27, 3) + 1 };
  return null;
}

/**
 * Checks an uploaded part: base64 WebP, at most ART_MAX_BYTES, the RIFF
 * length matching the data, and exactly the part's template size. Returns
 * the reason it is refused, or ''.
 */
export function checkArt(part: Part, image: unknown): string {
  if (PARTS.indexOf(part) < 0) return 'bad part';
  if (typeof image !== 'string' || image.length < 40 || image.length % 4 !== 0 || !B64_RE.test(image)) return 'bad image';
  const bytes = base64Length(image);
  if (bytes > ART_MAX_BYTES) return 'image too large';
  const head = base64Prefix(image, 32);
  const size = webpSize(head);
  if (!size) return 'image must be WebP';
  if (le(head, 4, 4) + 8 !== bytes) return 'bad image';
  const t = templateFor(part);
  if (size.width !== t.width || size.height !== t.height) return `image must be ${t.width}x${t.height}`;
  return '';
}

// ---- Decks -----------------------------------------------------------------

/** One deck: an art hash (or null for the default drawing) per part. */
export interface Deck {
  back: string | null;
  art: Array<string | null>;
}

export interface DeckRow {
  decks: Deck[];
  /** Deck shown in the player's private rooms, -1 for none. */
  active: number;
}

const HASH_RE = /^[0-9a-f]{64}$/;

export function isArtHash(v: unknown): v is string {
  return typeof v === 'string' && HASH_RE.test(v);
}

export function emptyDeck(): Deck {
  return { back: null, art: [null, null, null, null, null, null] };
}

export function normalizeDeckRow(raw: unknown, slots: number): DeckRow {
  const o = (typeof raw === 'object' && raw !== null ? raw : {}) as { decks?: unknown; active?: unknown };
  const decks: Deck[] = [];
  const list = Array.isArray(o.decks) ? o.decks : [];
  for (let i = 0; i < slots; i++) {
    const d = (typeof list[i] === 'object' && list[i] !== null ? list[i] : {}) as { back?: unknown; art?: unknown };
    const art: Array<string | null> = [];
    const rawArt = Array.isArray(d.art) ? d.art : [];
    for (let c = 0; c < 6; c++) art.push(isArtHash(rawArt[c]) ? (rawArt[c] as string) : null);
    decks.push({ back: isArtHash(d.back) ? d.back : null, art });
  }
  const a = typeof o.active === 'number' && isFinite(o.active) ? Math.floor(o.active) : -1;
  return { decks, active: a >= 0 && a < slots ? a : -1 };
}

/** The deck row with `part` of deck `slot` set to `hash` (or cleared with null). */
export function setPart(row: DeckRow, slot: number, part: Part, hash: string | null): DeckRow {
  const decks = row.decks.map((d) => ({ back: d.back, art: d.art.slice() }));
  const deck = decks[slot];
  if (!deck) return row;
  if (part === 'back') deck.back = hash;
  else deck.art[PARTS.indexOf(part) - 1] = hash;
  return { decks, active: row.active };
}

/** Every hash a deck uses, once each. */
export function deckHashes(deck: Deck): string[] {
  const out: string[] = [];
  for (const h of [deck.back].concat(deck.art)) if (h && out.indexOf(h) < 0) out.push(h);
  return out;
}

/**
 * What the table shows for a deck: approved art only. A part whose art is
 * pending, rejected or taken down shows the default drawing. Null when
 * nothing in the deck is approved.
 */
export function deckManifest(deck: Deck, approved: (hash: string) => boolean): Deck | null {
  const back = deck.back && approved(deck.back) ? deck.back : null;
  const art = deck.art.map((h) => (h && approved(h) ? h : null));
  if (!back && art.every((h) => h === null)) return null;
  return { back, art };
}

// ---- Moderation ------------------------------------------------------------

export type ArtStatus = 'pending' | 'approved' | 'rejected';

/** Google Cloud Vision SafeSearch likelihoods, least to most likely. */
const LIKELIHOOD = ['UNKNOWN', 'VERY_UNLIKELY', 'UNLIKELY', 'POSSIBLE', 'LIKELY', 'VERY_LIKELY'];

function level(v: unknown): number {
  const i = typeof v === 'string' ? LIKELIHOOD.indexOf(v) : -1;
  return i < 0 ? 0 : i;
}

/**
 * The automated verdict from a Vision `images:annotate` SafeSearch answer.
 * High-confidence adult or violent content is refused; anything uncertain
 * (POSSIBLE, UNKNOWN or an unreadable answer) waits for a person; clearly
 * clean pictures go live. Research 05 section 4: block on high confidence,
 * queue on medium.
 */
export function scanVerdict(body: unknown): ArtStatus {
  const root = (typeof body === 'object' && body !== null ? body : {}) as { responses?: unknown };
  const first = Array.isArray(root.responses) ? root.responses[0] : null;
  const ann = (typeof first === 'object' && first !== null ? (first as { safeSearchAnnotation?: unknown }).safeSearchAnnotation : null) as { [k: string]: unknown } | null;
  if (!ann || typeof ann !== 'object') return 'pending';
  const adult = level(ann['adult']);
  const violence = level(ann['violence']);
  const racy = level(ann['racy']);
  const unknown = adult === 0 || violence === 0 || racy === 0;
  if (adult >= 4 || violence >= 4 || racy >= 5) return 'rejected';
  if (unknown || adult >= 3 || violence >= 3 || racy >= 4) return 'pending';
  return 'approved';
}
