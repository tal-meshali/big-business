/**
 * Clubs and the weekly club league (research section 7, Phase 3): the pure
 * rules. A club is a Nakama group the server creates; rpc_clubs.ts holds the
 * RPCs and storage.
 *
 * WHY names are picked from word lists, not typed (decision D4): the game is
 * for every age and has no free text, so a club name is "<adjective> <noun>
 * <number>" from the lists below. Nothing a player writes is ever shown to
 * another player, so club names need no moderation queue.
 */

export const CLUB_ADJECTIVES = [
  'Bold', 'Bright', 'Steady', 'Swift', 'Golden', 'Silver', 'Lucky', 'Clever',
  'Brave', 'Quiet', 'Northern', 'Southern', 'Eastern', 'Western', 'Rising', 'Grand',
];
export const CLUB_NOUNS = [
  'Ventures', 'Holdings', 'Partners', 'Traders', 'Capital', 'Investors', 'Founders', 'Builders',
  'Brokers', 'Owners', 'Associates', 'Collective', 'Company', 'Union', 'Guild', 'Exchange',
];
/** Crests are the six company icons (Companies in the client). */
export const CLUB_CRESTS = 6;
export const CLUB_MAX_MEMBERS = 30;
/** One club per player. */
export const CLUBS_PER_PLAYER = 1;

/** Weekly league of clubs: owner is the club (group) id, score the season points its members earned. */
export const CLUB_LEAGUE = 'club_league';
/** Each player's points for their club this week; metadata.club names the club they were earned for. */
export const CLUB_WEEK = 'club_week';
/** Both reset at 00:00 UTC on Monday, with the weekly quests. */
export const CLUB_RESET = '0 0 * * 1';
/** Clubs shown in the league table. */
export const LEAGUE_TOP = 20;

/** Nakama group user states. */
export const ROLE_SUPERADMIN = 0;
export const ROLE_ADMIN = 1;
export const ROLE_MEMBER = 2;
export const ROLE_JOIN_REQUEST = 3;

/** The name for these word picks and number, or '' when a pick is out of range. */
export function clubName(adjective: number, noun: number, number: number): string {
  const a = CLUB_ADJECTIVES[adjective];
  const n = CLUB_NOUNS[noun];
  if (!a || !n || !isWhole(number) || number < 1 || number > 999) return '';
  return `${a} ${n} ${number}`;
}

export function isCrest(v: unknown): v is number {
  return isWhole(v) && (v as number) >= 0 && (v as number) < CLUB_CRESTS;
}

/** The crest stored in a club's metadata, 0 when missing or bad. */
export function crestOf(metadata: unknown): number {
  const o = typeof metadata === 'object' && metadata !== null ? (metadata as { [k: string]: unknown }) : {};
  return isCrest(o['crest']) ? (o['crest'] as number) : 0;
}

/** True for a state that is in the club (owner, admin or member), not a request or ban. */
export function isMemberState(state: number | undefined): boolean {
  return state === ROLE_SUPERADMIN || state === ROLE_ADMIN || state === ROLE_MEMBER;
}

export function roleName(state: number | undefined): 'owner' | 'admin' | 'member' {
  return state === ROLE_SUPERADMIN ? 'owner' : state === ROLE_ADMIN ? 'admin' : 'member';
}

/** Whether `actor` may remove `target` from the club: owners remove anyone else, admins only members. */
export function mayKick(actor: number | undefined, target: number | undefined): boolean {
  if (!isMemberState(actor) || !isMemberState(target)) return false;
  if (actor === ROLE_SUPERADMIN) return target !== ROLE_SUPERADMIN;
  return actor === ROLE_ADMIN && target === ROLE_MEMBER;
}

/**
 * Who takes over when the owner leaves: the first admin, otherwise the
 * first member, in list order; '' when nobody else is left.
 */
export function nextOwner(members: ReadonlyArray<{ userId: string; state: number | undefined }>, leaving: string): string {
  const others = members.filter((m) => m.userId !== leaving && isMemberState(m.state));
  const admin = others.find((m) => m.state === ROLE_ADMIN || m.state === ROLE_SUPERADMIN);
  return admin ? admin.userId : others.length > 0 ? (others[0] as { userId: string }).userId : '';
}

/** A member's points for this club this week: only points earned while in it count. */
export function weekPoints(record: { score: number; metadata?: { [k: string]: unknown } } | undefined, clubId: string): number {
  if (!record || !record.metadata || record.metadata['club'] !== clubId) return 0;
  return record.score > 0 ? record.score : 0;
}

function isWhole(v: unknown): boolean {
  return typeof v === 'number' && isFinite(v) && Math.floor(v) === v;
}
