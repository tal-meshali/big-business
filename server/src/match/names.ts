/**
 * Player names: the rules a typed name must pass before other players see
 * it. Pure; the RPC and the hooks that apply them are in rpc_names.ts.
 *
 * WHY (decision D4, every age): a name is the first free text one player
 * shows another, so it is short, has no symbols a link or a handle needs,
 * cannot hide a different reading behind invisible characters, and goes
 * through a word list. The list is a first line only; report_player and the
 * moderation queue handle what it misses.
 */

export const NAME_MIN = 3;
export const NAME_MAX = 16;

/** Messages are shown to the player as they are. */
export const NAME_TOO_SHORT = `Use at least ${NAME_MIN} characters.`;
export const NAME_TOO_LONG = `Use at most ${NAME_MAX} characters.`;
export const NAME_BAD_CHARACTERS = 'Use letters, numbers and spaces only.';
export const NAME_NOT_ALLOWED = 'Pick a different name.';
export const NAME_TAKEN = 'That name is taken. Try another.';

/** ASCII punctuation a name may contain between its letters and numbers. */
const ALLOWED_PUNCTUATION = ' _-.';

/**
 * Stems refused anywhere in a name, compared after `fold`. Only stems that
 * do not occur inside ordinary names and words are listed, so "Cassandra",
 * "Dickens" and "Analyst" pass.
 */
const BLOCKED_STEMS = [
  'fuck', 'shit', 'bitch', 'cunt', 'asshole', 'bastard', 'whore', 'slut', 'pussy', 'penis', 'vagina', 'porn', 'wank', 'twat',
  'nigger', 'nigga', 'faggot', 'retard', 'kike', 'chink', 'rapist', 'nazi', 'hitler',
];

/** Names that would pass for the game itself, its staff or its bots. */
const RESERVED = [
  'admin', 'administrator', 'moderator', 'support', 'official', 'system', 'bigbusiness', 'bot',
  'internivy', 'analystavi', 'brokerbo', 'auditorada', 'ceocal', 'investorines',
];

/** Digits that read as letters. */
const LEET: { [c: string]: string } = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't' };

/** Trims a typed name and collapses runs of spaces; '' when it is not a string. */
export function cleanName(raw: unknown): string {
  if (typeof raw !== 'string') return '';
  return raw.replace(/\s+/g, ' ').trim();
}

/** Code points in a string (an emoji or a letter outside the BMP counts once). */
export function nameLength(name: string): number {
  let n = 0;
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < name.length) i++;
    n++;
  }
  return n;
}

/** True for a character a name may not contain. */
function badCharacter(c: number, ch: string): boolean {
  // Control characters and DEL.
  if (c < 0x20 || c === 0x7f) return true;
  if (c < 0x80) {
    const letter = (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
    const digit = c >= 0x30 && c <= 0x39;
    return !letter && !digit && ALLOWED_PUNCTUATION.indexOf(ch) < 0;
  }
  // C1 controls, no-break and other odd spaces, zero-width and direction
  // marks, line and paragraph separators, and the byte-order mark.
  // WHY: these make two different names look the same, or reorder a name.
  if (c <= 0x9f || c === 0xa0 || c === 0xad || c === 0x1680 || c === 0x3000 || c === 0xfeff) return true;
  if (c >= 0x2000 && c <= 0x200f) return true;
  if (c >= 0x2028 && c <= 0x202f) return true;
  if (c >= 0x205f && c <= 0x206f) return true;
  return false;
}

/** Lower case, look-alike digits as letters, and nothing but letters: "F.u_c-K" and "sh1t" fold to the stem. */
export function fold(name: string): string {
  let out = '';
  const lower = name.toLowerCase();
  for (let i = 0; i < lower.length; i++) {
    const ch = lower.charAt(i);
    const mapped = LEET[ch] || ch;
    if (ALLOWED_PUNCTUATION.indexOf(mapped) < 0) out += mapped;
  }
  return out;
}

/**
 * Why a cleaned name cannot be used, as a sentence for the player, or null
 * when it can. Pass the result of `cleanName`.
 */
export function nameProblem(name: string): string | null {
  const length = nameLength(name);
  if (length < NAME_MIN) return NAME_TOO_SHORT;
  if (length > NAME_MAX) return NAME_TOO_LONG;
  for (let i = 0; i < name.length; i++) {
    if (badCharacter(name.charCodeAt(i), name.charAt(i))) return NAME_BAD_CHARACTERS;
  }
  const folded = fold(name);
  // Punctuation alone is not a name.
  if (folded.length === 0) return NAME_BAD_CHARACTERS;
  if (RESERVED.indexOf(folded) >= 0) return NAME_NOT_ALLOWED;
  // The digits-as-digits reading catches a reserved word behind a number.
  const plain = name.toLowerCase().replace(/[ _.-]/g, '');
  if (RESERVED.indexOf(plain) >= 0) return NAME_NOT_ALLOWED;
  for (const stem of BLOCKED_STEMS) {
    if (folded.indexOf(stem) >= 0 || plain.indexOf(stem) >= 0) return NAME_NOT_ALLOWED;
  }
  return null;
}

/** True once the player picked the account's name (false for the random one Nakama made). */
export function isNamed(account: { user?: { metadata?: { [key: string]: unknown } | null } | null }): boolean {
  const meta = account.user && account.user.metadata;
  return !!meta && meta['named'] === true;
}
