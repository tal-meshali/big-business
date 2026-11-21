/**
 * Player names: the rules a typed name must pass before other players see
 * it. Pure; the RPC and the hooks that apply them are in rpc_names.ts.
 *
 * WHY (decision D17, every age): a name is the first free text one player
 * shows another, so it is short, made only of letters and digits from a
 * list of alphabets (nothing invisible, no symbols a link or a handle
 * needs, no emoji), cannot borrow look-alike letters from another alphabet,
 * and goes through a word list. The list is English and a first line only;
 * report_player and the moderation queue handle what it misses.
 */
import { BOT_NAMES } from './protocol';

export const NAME_MIN = 2;
export const NAME_MAX = 16;

/**
 * Messages are shown to the player as they are.
 * WHY none contains " at ": the client cuts a server error there to drop
 * the stack trace that follows it.
 */
export const NAME_TOO_SHORT = `Too short. Use ${NAME_MIN} to ${NAME_MAX} characters.`;
export const NAME_TOO_LONG = `Too long. Use ${NAME_MIN} to ${NAME_MAX} characters.`;
export const NAME_BAD_CHARACTERS = 'Use letters, numbers and spaces only.';
export const NAME_MIXED = 'Use letters from one alphabet.';
export const NAME_NOT_ALLOWED = 'Pick a different name.';
export const NAME_TAKEN = 'That name is taken. Try another.';
export const NAME_LOCKED = 'A moderator set this name. It cannot be changed.';

/** What may stand between a name's letters and numbers. */
const SEPARATORS = ' _-';

const LATIN = 1;
const GREEK = 2;
const CYRILLIC = 3;
const OTHER = 4;

/**
 * The letters a name may use, as [first, last, alphabet] code points.
 * WHY a list of what is allowed: a list of what is refused always misses
 * some invisible or look-alike character. Everything outside the Basic
 * Multilingual Plane (emoji, tags) is refused with the surrogates.
 */
const LETTERS: number[][] = [
  [0x41, 0x5a, LATIN], [0x61, 0x7a, LATIN],
  // Western and central European letters, Romanian, Vietnamese.
  [0xc0, 0xd6, LATIN], [0xd8, 0xf6, LATIN], [0xf8, 0x17f, LATIN], [0x1a0, 0x1a1, LATIN], [0x1af, 0x1b0, LATIN], [0x218, 0x21b, LATIN], [0x1ea0, 0x1ef9, LATIN],
  [0x386, 0x386, GREEK], [0x388, 0x38a, GREEK], [0x38c, 0x38c, GREEK], [0x38e, 0x3a1, GREEK], [0x3a3, 0x3ce, GREEK],
  [0x400, 0x45f, CYRILLIC], [0x490, 0x491, CYRILLIC],
  // Hebrew, Arabic (without the tatweel), Devanagari, Thai.
  [0x5d0, 0x5ea, OTHER], [0x620, 0x63f, OTHER], [0x641, 0x64a, OTHER], [0x671, 0x6d3, OTHER], [0x904, 0x939, OTHER], [0x93e, 0x94d, OTHER], [0xe01, 0xe3a, OTHER], [0xe40, 0xe4e, OTHER],
  // Japanese kana, Chinese characters, Korean syllables.
  [0x3041, 0x3096, OTHER], [0x30a1, 0x30fa, OTHER], [0x30fc, 0x30fc, OTHER], [0x4e00, 0x9fff, OTHER], [0xac00, 0xd7a3, OTHER],
];

/** Refused anywhere in a name, however it is spaced: no ordinary name contains these. */
const BLOCKED_ANYWHERE = ['fuck', 'cunt', 'nigger', 'nigga', 'faggot', 'bitch', 'asshole', 'whore', 'pussy', 'hitler', 'shithead', 'bullshit', 'dipshit'];

/**
 * Refused as a word of the name or as the whole name, not inside a longer
 * word: "Yamashita", "Nazir", "Therapist" and "Swank" are names.
 */
const BLOCKED_WORDS = ['shit', 'bastard', 'slut', 'penis', 'vagina', 'porn', 'wank', 'twat', 'retard', 'kike', 'chink', 'rapist', 'nazi'];

/** A word of a name may not start like the game's staff. */
const STAFF_PREFIXES = ['admin', 'moderator', 'official', 'support', 'staff'];

/** Words that would pass for the game's staff or its bots on their own. */
const STAFF_WORDS = ['mod', 'mods', 'system', 'bot', 'dev', 'owner'];

const GAME_NAME = 'bigbusiness';

/** Digits that read as letters. */
const LEET: { [c: string]: string } = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't' };

/**
 * A typed name as it will be stored: compatibility forms folded to the
 * plain ones (full-width letters, ligatures, odd spaces), trimmed, with
 * runs of spaces collapsed. '' when it is not a string.
 */
export function cleanName(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  return raw.normalize('NFKC').replace(/\s+/g, ' ').trim();
}

/** Code points in a string (a character outside the BMP counts once). */
export function nameLength(name: string): number {
  let n = 0;
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < name.length) i++;
    n++;
  }
  return n;
}

/** The alphabet of a letter a name may use; 0 for anything else. */
function alphabetOf(c: number): number {
  for (const range of LETTERS) {
    if (c >= (range[0] as number) && c <= (range[1] as number)) return range[2] as number;
  }
  return 0;
}

/** Lower case without accents: "Fück" reads as its stem. */
function plainLower(text: string): string {
  return text.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
}

/** Lower case, look-alike digits as letters, and nothing but letters: "F.u_c-K" and "sh1t" fold to the stem. */
export function fold(name: string): string {
  let out = '';
  const lower = plainLower(name);
  for (let i = 0; i < lower.length; i++) {
    const ch = lower.charAt(i);
    const mapped = LEET[ch] || ch;
    if (SEPARATORS.indexOf(mapped) < 0) out += mapped;
  }
  return out;
}

/** The same without the digits: "shit99" reads as its stem. */
function foldBare(name: string): string {
  return plainLower(name).replace(/[0-9 _-]/g, '');
}

/** The words of a name: split at separators and where a capital follows a small letter ("NaziKing"). */
function wordsOf(name: string): string[] {
  return name.replace(/([a-zß-ÿ])([A-Z])/g, '$1 $2').split(/[ _-]+/).filter((w) => w.length > 0);
}

function startsWithAny(text: string, list: string[]): boolean {
  for (const item of list) if (text.indexOf(item) === 0) return true;
  return false;
}

/** True when one reading of a word, or of the whole name, is a refused or reserved word. */
function refusedReading(reading: string, whole: boolean): boolean {
  for (const stem of BLOCKED_WORDS) if (reading === stem || reading === stem + 's') return true;
  if (startsWithAny(reading, STAFF_PREFIXES) || STAFF_WORDS.indexOf(reading) >= 0) return true;
  if (!whole) return false;
  if (reading.indexOf(GAME_NAME) >= 0) return true;
  for (const stem of BLOCKED_ANYWHERE) if (reading.indexOf(stem) >= 0) return true;
  for (const bot of BOT_NAMES) if (reading === fold(bot)) return true;
  return false;
}

/**
 * Why a cleaned name cannot be used, as a sentence for the player, or null
 * when it can. Pass the result of `cleanName`.
 */
export function nameProblem(name: string): string | null {
  const length = nameLength(name);
  if (length < NAME_MIN) return NAME_TOO_SHORT;
  if (length > NAME_MAX) return NAME_TOO_LONG;
  const seen: { [alphabet: number]: boolean } = {};
  let solid = 0;
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    if (SEPARATORS.indexOf(name.charAt(i)) >= 0) continue;
    solid++;
    if (c >= 0x30 && c <= 0x39) continue;
    const alphabet = alphabetOf(c);
    if (alphabet === 0) return NAME_BAD_CHARACTERS;
    seen[alphabet] = true;
  }
  // Punctuation alone is not a name.
  if (solid === 0) return NAME_BAD_CHARACTERS;
  // WHY: a Cyrillic or Greek letter inside a Latin name reads as the Latin
  // one, which would get round the word list and copy another player's name.
  if ((seen[LATIN] ? 1 : 0) + (seen[GREEK] ? 1 : 0) + (seen[CYRILLIC] ? 1 : 0) > 1) return NAME_MIXED;
  // Digits are read both as the letters they stand for and as nothing.
  if (refusedReading(fold(name), true) || refusedReading(foldBare(name), true)) return NAME_NOT_ALLOWED;
  for (const word of wordsOf(name)) {
    if (refusedReading(fold(word), false) || refusedReading(foldBare(word), false)) return NAME_NOT_ALLOWED;
  }
  return null;
}

/** True once the player picked the account's name (false for the random one Nakama made). */
export function isNamed(account: { user?: { metadata?: { [key: string]: unknown } | null } | null }): boolean {
  const meta = account.user && account.user.metadata;
  return !!meta && meta['named'] === true;
}
