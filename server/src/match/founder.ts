/**
 * Founder unlock: the player's own companies (name, colour and logo) for the
 * private rooms they host. Pure rules only: the colour and logo lists, the
 * company-name check, the stored row and what a table shows. Storage is in
 * founder_store.ts, the RPCs in rpc_founder.ts.
 *
 * WHY a custom company reskins one of the six fixed companies instead of
 * adding a new one: the rules (share counts 5 to 10, majorities, tokens)
 * depend on exactly these six. A custom company keeps its slot's share
 * count, so the game plays the same and only the look changes, like a
 * Designer deck (decision D11).
 *
 * WHY colours and drawn logos come from fixed lists: a free colour could be
 * one another company already uses or one the card text cannot be read on,
 * and a drawn logo needs no review. An uploaded logo picture goes through the
 * Designer art pipeline (designer.ts part 'logo') and shows to others only
 * once approved; until then they see the drawn logo.
 */

/** Colour ids a company may use, in the order the picker shows them. The client maps them to colours (companies.gd). */
export const COLORS = ['yellow', 'green', 'blue', 'orange', 'purple', 'red', 'teal', 'pink', 'navy', 'brown', 'lime', 'slate'];

/** Drawn logo ids, in the order the picker shows them. The first six are the standard companies' art. */
export const LOGOS = ['sun', 'pine', 'anchor', 'gear', 'cloud', 'bolt', 'rocket', 'crown', 'leaf', 'diamond', 'heart', 'star', 'chart', 'flame', 'key', 'mountain', 'cup', 'globe'];

/** The standard companies' look, by company id (engine/companies.ts). */
export const DEFAULT_NAMES = ['Sunny Side Solar', 'Pinecone Foods', 'Tidewater Freight', 'Cogwheel Robotics', 'Nimbus Air', 'Redline Motors'];
export const DEFAULT_COLORS = ['yellow', 'green', 'blue', 'orange', 'purple', 'red'];
export const DEFAULT_LOGOS = ['sun', 'pine', 'anchor', 'gear', 'cloud', 'bolt'];

export const COMPANY_SLOTS = 6;
export const NAME_MIN = 2;
export const NAME_MAX = 18;
/** At most this many digits in a name (no phone numbers). */
const DIGITS_MAX = 4;

export const NAME_LENGTH = `Use ${NAME_MIN} to ${NAME_MAX} characters.`;
export const NAME_CHARACTERS = "Use letters, numbers, spaces and & ' - . only.";
export const NAME_SHAPE = 'Start with a letter or number and use one space or mark between words.';
export const NAME_DIGITS = `Use letters, and no more than ${DIGITS_MAX} numbers.`;
export const NAME_NOT_ALLOWED = 'Pick a different name.';
export const NAME_SAME = 'Another of your companies already has that name.';
export const COLOR_SAME = 'Another of your companies already has that colour, or one too like it.';
export const LOGO_SAME = 'Another of your companies already has that logo, or one too like it.';
export const SHORT_SAME = 'Another of your companies would show the same name on its band. Change the first word.';

/** One custom company: its typed name, colour id, drawn logo id and optional logo picture (art hash). */
export interface Company {
  name: string;
  color: string;
  logo: string;
  picture: string | null;
}

export interface CompaniesRow {
  /** One entry per company id; null keeps the standard company. */
  companies: Array<Company | null>;
  /** Show these companies in the private rooms the player hosts. */
  active: boolean;
}

const HASH_RE = /^[0-9a-f]{64}$/;

// ---- Names -----------------------------------------------------------------

/**
 * Letters a name may use: Latin (with accents), Greek, Cyrillic and Hebrew.
 * WHY ranges instead of \p{L}: Nakama's JavaScript runtime (goja) does not
 * support Unicode property escapes.
 */
const LETTER_RANGES: number[][] = [
  [0x41, 0x5a], [0x61, 0x7a], [0xc0, 0xd6], [0xd8, 0xf6], [0xf8, 0x17f],
  [0x386, 0x386], [0x388, 0x3ce], [0x400, 0x45f], [0x5d0, 0x5ea],
];
const MARKS = "&'-.";

function isLetter(c: number): boolean {
  for (const r of LETTER_RANGES) if (c >= (r[0] as number) && c <= (r[1] as number)) return true;
  return false;
}

function isDigit(c: number): boolean {
  return c >= 0x30 && c <= 0x39;
}

/** The name as stored: trimmed, or '' when it is not a string. */
export function cleanName(raw: unknown): string {
  return typeof raw === 'string' ? raw.trim() : '';
}

function codePoints(s: string): number[] {
  const out: number[] = [];
  for (const ch of Array.from(s)) out.push(ch.codePointAt(0) as number);
  return out;
}

/**
 * Look-alikes read as the Latin letters they imitate: digits, and Greek and
 * Cyrillic letters that look Latin ("Fuсk" with a Cyrillic с).
 */
const LOOKALIKE: { [c: string]: string } = {
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't',
  'а': 'a', 'в': 'b', 'е': 'e', 'к': 'k', 'м': 'm', 'н': 'h', 'о': 'o', 'р': 'p', 'с': 'c', 'т': 't', 'у': 'y', 'х': 'x', 'і': 'i', 'ѕ': 's',
  'α': 'a', 'β': 'b', 'ε': 'e', 'ι': 'i', 'κ': 'k', 'ν': 'v', 'ο': 'o', 'ρ': 'p', 'τ': 't', 'υ': 'u', 'χ': 'x',
};

/** Words refused anywhere inside one word of a name ("Fuckco"). */
const BLOCKED_INSIDE = ['fuck', 'cunt', 'nigger', 'nigga', 'faggot', 'bitch', 'asshole', 'whore', 'pussy', 'hitler', 'shit', 'porn', 'dildo', 'penis', 'vagina'];
/** Ordinary words that contain a blocked one. */
const ALLOWED_INSIDE = ['scunthorpe', 'shiitake', 'shitake', 'badminton', 'cockpit', 'peacock', 'hancock', 'woodcock', 'shuttlecock', 'cocktail', 'dickens', 'snigger', 'sniggers'];
/** Words refused as a whole word, or as two words run together ("Fu Ck"), plurals included. */
const BLOCKED_WORDS = ['ass', 'sex', 'cum', 'tit', 'tits', 'nazi', 'kkk', 'rape', 'slut', 'wank', 'twat', 'retard', 'kike', 'chink', 'bastard', 'dick', 'cock', 'fuk', 'fuc', 'phuck'].concat(BLOCKED_INSIDE);
/** Names that could pass for the game or its staff. */
const STAFF_INSIDE = ['admin', 'moderator', 'official', 'bigbusiness'];

/** Lower case, look-alikes replaced, everything but letters dropped. */
export function fold(name: string): string {
  let out = '';
  for (const ch of Array.from(name.toLowerCase())) {
    const mapped = LOOKALIKE[ch] !== undefined ? LOOKALIKE[ch] : ch;
    if (isLetter(mapped.codePointAt(0) as number)) out += mapped;
  }
  return out;
}

/** The ways a folded word may be read: as written, "ph" as "f", "v" as "u", plural dropped. */
function readings(word: string): string[] {
  const out = [word, word.replace(/ph/g, 'f'), word.replace(/v/g, 'u')];
  for (const w of out.slice()) {
    if (w.length > 3 && w.endsWith('es')) out.push(w.slice(0, -2));
    if (w.length > 2 && w.endsWith('s')) out.push(w.slice(0, -1));
  }
  return out;
}

/** True when a folded word is refused on its own. */
function refusedWord(word: string): boolean {
  for (const r of readings(word)) {
    if (BLOCKED_WORDS.indexOf(r) >= 0) return true;
    if (ALLOWED_INSIDE.indexOf(r) >= 0 || ALLOWED_INSIDE.indexOf(word) >= 0) continue;
    for (const b of BLOCKED_INSIDE.concat(STAFF_INSIDE)) if (r.indexOf(b) >= 0) return true;
  }
  return false;
}

/**
 * True when a name holds a refused word: inside any one word, or as two
 * neighbouring words read together ("Fu Ck"). WHY not the whole name run
 * together: that refuses ordinary names ("Push It Co", "Bit Chain").
 */
function refusedName(name: string): boolean {
  const words = name.split(/[ &'.-]+/).map(fold).filter((w) => w !== '');
  for (let i = 0; i < words.length; i++) {
    if (refusedWord(words[i] as string)) return true;
    const pair = (words[i] as string) + (words[i + 1] || '');
    if (i + 1 < words.length && readings(pair).some((r) => BLOCKED_WORDS.indexOf(r) >= 0)) return true;
  }
  return fold(name).indexOf('bigbusiness') >= 0;
}

/**
 * One word of a name: "&" alone, or a letter or digit followed by letters,
 * digits and single marks (' - .), not ending in ' or -. So "Smith & Co.",
 * "O'Neil" and "Up-Start" pass; "--", "Co..", "A-" do not.
 */
function wordShapeOk(word: string): boolean {
  if (word === '&') return true;
  const cps = codePoints(word);
  let prevMark = true;
  for (let k = 0; k < cps.length; k++) {
    const c = cps[k] as number;
    const ch = String.fromCodePoint(c);
    if (isLetter(c) || isDigit(c)) {
      prevMark = false;
    } else if (ch === "'" || ch === '-' || ch === '.') {
      if (prevMark) return false;
      prevMark = true;
    } else {
      return false;
    }
  }
  const last = word.charAt(word.length - 1);
  return last !== "'" && last !== '-';
}

/** The reason a company name is refused, or null when it is fine. */
export function nameProblem(raw: unknown): string | null {
  const name = cleanName(raw);
  const cps = codePoints(name);
  if (cps.length < NAME_MIN || cps.length > NAME_MAX) return NAME_LENGTH;
  let letters = 0;
  let digits = 0;
  for (const c of cps) {
    if (isLetter(c)) letters++;
    else if (isDigit(c)) digits++;
    else if (c !== 0x20 && MARKS.indexOf(String.fromCodePoint(c)) < 0) return NAME_CHARACTERS;
  }
  const words = name.split(' ');
  if (words[0] === '&') return NAME_SHAPE;
  for (const w of words) if (w === '' || !wordShapeOk(w)) return NAME_SHAPE;
  if (letters === 0 || digits > DIGITS_MAX) return NAME_DIGITS;
  return refusedName(name) ? NAME_NOT_ALLOWED : null;
}

// ---- The row ---------------------------------------------------------------

export function isColor(v: unknown): v is string {
  return typeof v === 'string' && COLORS.indexOf(v) >= 0;
}

export function isLogo(v: unknown): v is string {
  return typeof v === 'string' && LOGOS.indexOf(v) >= 0;
}

/** A stored or sent company, or null when any part of it is not valid. */
export function normalizeCompany(raw: unknown): Company | null {
  const o = (typeof raw === 'object' && raw !== null ? raw : null) as { [k: string]: unknown } | null;
  if (!o) return null;
  const name = cleanName(o['name']);
  if (nameProblem(name) !== null || !isColor(o['color']) || !isLogo(o['logo'])) return null;
  const pic = o['picture'];
  return { name, color: o['color'] as string, logo: o['logo'] as string, picture: typeof pic === 'string' && HASH_RE.test(pic) ? pic : null };
}

export function emptyRow(): CompaniesRow {
  return { companies: [null, null, null, null, null, null], active: false };
}

export function normalizeCompaniesRow(raw: unknown): CompaniesRow {
  const o = (typeof raw === 'object' && raw !== null ? raw : {}) as { companies?: unknown; active?: unknown };
  const list = Array.isArray(o.companies) ? o.companies : [];
  const companies: Array<Company | null> = [];
  for (let i = 0; i < COMPANY_SLOTS; i++) companies.push(normalizeCompany(list[i]));
  return { companies, active: o.active === true };
}

/** What company `i` looks like at the table with this row: the custom one or the standard. */
export function effective(row: CompaniesRow, i: number): { name: string; color: string; logo: string } {
  const c = row.companies[i];
  return c ? { name: c.name, color: c.color, logo: c.logo } : { name: DEFAULT_NAMES[i] as string, color: DEFAULT_COLORS[i] as string, logo: DEFAULT_LOGOS[i] as string };
}

/**
 * Why `company` cannot go in slot `i` of `row`, or ''. The six companies at
 * the table must differ in name, colour and logo, counting the standard
 * companies the player did not replace.
 * WHY: colour and silhouette together are how players (colourblind ones
 * too) tell the companies apart at a glance.
 */
export function clashWith(row: CompaniesRow, i: number, company: Company): string {
  const lower = company.name.toLowerCase();
  const short = shortName(company.name, i).toLowerCase();
  for (let j = 0; j < COMPANY_SLOTS; j++) {
    if (j === i) continue;
    const other = effective(row, j);
    if (other.name.toLowerCase() === lower) return NAME_SAME;
    if (shortName(other.name, j).toLowerCase() === short) return SHORT_SAME;
    if (family(COLOR_FAMILIES, other.color) === family(COLOR_FAMILIES, company.color)) return COLOR_SAME;
    if (family(LOGO_FAMILIES, other.logo) === family(LOGO_FAMILIES, company.logo)) return LOGO_SAME;
  }
  return '';
}

/**
 * Colours and logos too alike to sit at one table: a pair counts as one.
 * WHY: chips on the felt show only the colour, and a mini logo shows only
 * its outline; these pairs are hard to tell apart there.
 */
export const COLOR_FAMILIES = [['green', 'lime'], ['blue', 'navy'], ['orange', 'brown']];
export const LOGO_FAMILIES = [['pine', 'mountain'], ['bolt', 'globe']];

function family(families: string[][], id: string): string {
  for (const f of families) if (f.indexOf(id) >= 0) return f[0] as string;
  return id;
}

/** Words skipped when a long name is cut to its band name. Must match companies.gd STOP_WORDS. */
const STOP_WORDS = ['the', 'a', 'an', 'my', 'our', 'big', 'little', 'new', 'old', 'el', 'la', 'le', 'los', 'las', 'les', 'de', 'di', 'da', 'and', '&', 'of'];
/** The standard companies' band names, by company id. */
const DEFAULT_SHORT = ['Solar', 'Foods', 'Freight', 'Robotics', 'Air', 'Motors'];

/**
 * The name on the share's colour band: the whole name when it is 10
 * characters or fewer, else its first word that is not a stop word.
 * Must match companies.gd `short_of_name`.
 */
export function shortName(name: string, i: number): string {
  if (name === DEFAULT_NAMES[i]) return DEFAULT_SHORT[i] as string;
  if (Array.from(name).length <= 10) return name;
  const words = name.split(' ').filter((w) => w !== '');
  for (const w of words) if (STOP_WORDS.indexOf(w.toLowerCase()) < 0) return w;
  return words[0] || name;
}

/** The row with slot `i` set to `company` (or back to standard with null). */
export function setCompany(row: CompaniesRow, i: number, company: Company | null): CompaniesRow {
  const companies = row.companies.slice();
  companies[i] = company;
  return { companies, active: row.active };
}

/** Every logo picture hash the row uses, once each. */
export function pictureHashes(row: CompaniesRow): string[] {
  const out: string[] = [];
  for (const c of row.companies) if (c && c.picture && out.indexOf(c.picture) < 0) out.push(c.picture);
  return out;
}

/**
 * What a table shows: the custom companies with only approved logo
 * pictures (others fall back to the drawn logo). Null when the row is off
 * or has no custom company.
 */
export function companiesManifest(row: CompaniesRow, approved: (hash: string) => boolean): Array<Company | null> | null {
  if (!row.active || row.companies.every((c) => c === null)) return null;
  return row.companies.map((c) => (c ? { name: c.name, color: c.color, logo: c.logo, picture: c.picture && approved(c.picture) ? c.picture : null } : null));
}
