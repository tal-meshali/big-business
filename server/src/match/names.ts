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
export const NAME_DIGITS = 'Use letters, and no more than 6 numbers.';
export const NAME_NOT_ALLOWED = 'Pick a different name.';
export const NAME_TAKEN = 'That name is taken. Try another.';
export const NAME_LOCKED = 'A moderator set this name. It cannot be changed.';

/** What may stand between a name's letters and numbers, one mark between two of them. */
const SEPARATORS = ' _-';

/** WHY a cap: a longer run of digits is a phone number, which a name must not carry. */
const DIGITS_MAX = 6;

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
  [0xc0, 0xd6, LATIN], [0xd8, 0xf6, LATIN], [0xf8, 0x137, LATIN], [0x139, 0x148, LATIN], [0x14a, 0x17f, LATIN], [0x1a0, 0x1a1, LATIN], [0x1af, 0x1b0, LATIN], [0x218, 0x21b, LATIN], [0x1ea0, 0x1ef9, LATIN],
  [0x386, 0x386, GREEK], [0x388, 0x38a, GREEK], [0x38c, 0x38c, GREEK], [0x38e, 0x3a1, GREEK], [0x3a3, 0x3ce, GREEK],
  [0x400, 0x45f, CYRILLIC], [0x490, 0x491, CYRILLIC],
  // Hebrew, Arabic (without the tatweel), Devanagari, Thai.
  [0x5d0, 0x5ea, OTHER], [0x620, 0x63f, OTHER], [0x641, 0x64a, OTHER], [0x671, 0x6d3, OTHER], [0x901, 0x939, OTHER], [0x93c, 0x94d, OTHER], [0xe01, 0xe3a, OTHER], [0xe40, 0xe4e, OTHER],
  // Japanese kana, Chinese characters, Korean syllables.
  [0x3041, 0x3096, OTHER], [0x30a1, 0x30fa, OTHER], [0x30fc, 0x30fc, OTHER], [0x4e00, 0x9fff, OTHER], [0xac00, 0xd7a3, OTHER],
];

/**
 * Marks that sit on the letter before them (Devanagari and Thai vowel and
 * tone signs), as [first, last]. A name may not start with one or stack
 * more than two, so it cannot be drawn over the rows around it.
 */
const MARKS: number[][] = [[0x901, 0x903], [0x93c, 0x93c], [0x93e, 0x94d], [0xe31, 0xe31], [0xe34, 0xe3a], [0xe47, 0xe4e]];
const MARKS_IN_A_ROW = 2;

/**
 * Letters that read as a Latin one, for the word and staff checks only:
 * the Latin letters that lose nothing but a stroke or a dot, and the Greek
 * and Cyrillic letters whose capital or small form is drawn like a Latin
 * letter, so a refused word spelled in them is still refused.
 */
const LOOKALIKES: { [c: string]: string } = {
  '\u0131': 'i', '\u00f8': 'o', '\u0142': 'l', '\u0111': 'd', '\u0127': 'h',
  '\u03b1': 'a', '\u03b2': 'b', '\u03b5': 'e', '\u03b6': 'z', '\u03b7': 'h', '\u03b9': 'i', '\u03ba': 'k', '\u03bc': 'm', '\u03bd': 'n', '\u03bf': 'o', '\u03c1': 'p', '\u03c4': 't', '\u03c5': 'y', '\u03c7': 'x',
  '\u0430': 'a', '\u0432': 'b', '\u0435': 'e', '\u043a': 'k', '\u043c': 'm', '\u043d': 'h', '\u043e': 'o', '\u0440': 'p', '\u0441': 'c', '\u0442': 't', '\u0443': 'y', '\u0445': 'x', '\u0455': 's', '\u0456': 'i', '\u0458': 'j',
};

/** Refused anywhere in a name, however it is spaced: no ordinary name contains these. */
const BLOCKED_ANYWHERE = ['fuck', 'cunt', 'nigger', 'nigga', 'faggot', 'bitch', 'asshole', 'whore', 'pussy', 'hitler', 'shithead', 'bullshit', 'dipshit'];

/**
 * Refused as a word of the name or as the whole name, not inside a longer
 * word: "Yamashita", "Nazir", "Therapist" and "Swank" are names.
 */
const BLOCKED_WORDS = ['shit', 'bastard', 'slut', 'penis', 'vagina', 'porn', 'wank', 'twat', 'retard', 'kike', 'chink', 'rapist', 'nazi'];

/** Refused anywhere in a name: it would pass for the game's staff. */
const STAFF_ANYWHERE = ['admin', 'moderator', 'official', 'support'];

/** Ordinary words that only contain one of those. */
const NOT_STAFF = ['badminton'];

/** Words that would pass for the game's staff or its bots on their own ("Stafford" and "Botanist" are names). */
const STAFF_WORDS = ['mod', 'mods', 'staff', 'system', 'bot', 'owner'];

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

function isMark(c: number): boolean {
  for (const range of MARKS) {
    if (c >= (range[0] as number) && c <= (range[1] as number)) return true;
  }
  return false;
}

/** Lower case without accents, look-alike letters as the Latin ones they copy. */
function plainLower(text: string): string {
  const bare = text.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  let out = '';
  for (let i = 0; i < bare.length; i++) {
    const ch = bare.charAt(i);
    out += LOOKALIKES[ch] || ch;
  }
  return out;
}

/** Lower case, look-alike digits as letters, and nothing but letters: "F-u_c K" and "sh1t" fold to the stem. */
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
  return name.replace(/([a-z\u00df-\u00ff])([A-Z])/g, '$1 $2').split(/[ _-]+/).filter((w) => w.length > 0);
}

/** True when one reading of a word, or of the whole name, is a refused or reserved word. */
function refusedReading(reading: string, whole: boolean): boolean {
  for (const stem of BLOCKED_WORDS) if (reading === stem || reading === stem + 's') return true;
  if (STAFF_WORDS.indexOf(reading) >= 0) return true;
  if (!whole) return false;
  let rest = reading;
  for (const word of NOT_STAFF) rest = rest.split(word).join(' ');
  for (const stem of STAFF_ANYWHERE) if (rest.indexOf(stem) >= 0) return true;
  if (reading.indexOf(GAME_NAME) >= 0) return true;
  for (const stem of BLOCKED_ANYWHERE) if (reading.indexOf(stem) >= 0) return true;
  for (const bot of BOT_NAMES) if (reading === fold(bot)) return true;
  return false;
}

/** True when the characters of a cleaned name are ones a name may be made of, in an order it may have. */
function wellFormed(name: string): boolean {
  let marks = 0;
  // 0 a separator (or the start), 1 a letter or digit, 2 a mark.
  let before = 0;
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    if (SEPARATORS.indexOf(name.charAt(i)) >= 0) {
      // One separator between two words, none first or last.
      if (before === 0 || i === name.length - 1) return false;
      before = 0;
      continue;
    }
    if (c >= 0x30 && c <= 0x39) {
      before = 1;
      continue;
    }
    if (alphabetOf(c) === 0) return false;
    if (isMark(c)) {
      marks = before === 2 ? marks + 1 : 1;
      if (before === 0 || marks > MARKS_IN_A_ROW) return false;
      before = 2;
      continue;
    }
    before = 1;
  }
  return name.length > 0;
}

/**
 * Why a cleaned name cannot be used, as a sentence for the player, or null
 * when it can. Pass the result of `cleanName`.
 */
export function nameProblem(name: string): string | null {
  const length = nameLength(name);
  if (length < NAME_MIN) return NAME_TOO_SHORT;
  if (length > NAME_MAX) return NAME_TOO_LONG;
  if (!wellFormed(name)) return NAME_BAD_CHARACTERS;
  const seen: { [alphabet: number]: boolean } = {};
  let digits = 0;
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    if (c >= 0x30 && c <= 0x39) digits++;
    else if (SEPARATORS.indexOf(name.charAt(i)) < 0) seen[alphabetOf(c)] = true;
  }
  // WHY: a name of digits is a phone number or nothing a player can say.
  if (digits > DIGITS_MAX || !(seen[LATIN] || seen[GREEK] || seen[CYRILLIC] || seen[OTHER])) return NAME_DIGITS;
  // WHY: a Cyrillic or Greek letter inside a Latin name reads as the Latin
  // one, which would get round the word list and copy another player's name.
  if ((seen[LATIN] ? 1 : 0) + (seen[GREEK] ? 1 : 0) + (seen[CYRILLIC] ? 1 : 0) > 1) return NAME_MIXED;
  // Digits are read both as the letters they stand for and as nothing.
  if (refusedReading(fold(name), true) || refusedReading(foldBare(name), true)) return NAME_NOT_ALLOWED;
  for (const word of wordsOf(name)) {
    if (refusedReading(fold(word), false) || refusedReading(foldBare(word), false)) return NAME_NOT_ALLOWED;
    // "porn4u": the letters on each side of a number are words too.
    for (const part of plainLower(word).split(/[0-9]+/)) if (refusedReading(part, false)) return NAME_NOT_ALLOWED;
  }
  return null;
}

/** True once the player picked the account's name (false for the random one Nakama made). */
export function isNamed(account: { user?: { metadata?: { [key: string]: unknown } | null } | null }): boolean {
  const meta = account.user && account.user.metadata;
  return !!meta && meta['named'] === true;
}
