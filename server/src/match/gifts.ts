/**
 * Friend gifting (research section 7, Phase 3): the pure rules. A gift is a
 * few points on the free cosmetic track, never anything sold and never a
 * currency (decision D5: real-money prices only, no virtual currency).
 * rpc_gifts.ts holds the RPCs and storage.
 */
import { utcDate } from './progression';

/** Server-only rows: 'inbox' (gifts waiting) and 'sent' (today's sends) per player. */
export const GIFT_COLLECTION = 'gifts';
/** Track points one gift is worth. */
export const GIFT_POINTS = 5;
/** Gifts a player may collect per UTC day; the rest wait for tomorrow. */
export const GIFTS_CLAIM_PER_DAY = 5;
/** Gifts a player may send per UTC day (one per friend). */
export const GIFTS_SEND_PER_DAY = 10;
/** Days an uncollected gift waits. */
export const GIFT_KEEP_DAYS = 7;
/** Gifts kept waiting at most; the oldest go first. */
export const INBOX_MAX = 30;

const DAY_MS = 86_400_000;

export interface Gift {
  from: string;
  name: string;
  at: number;
}

export interface GiftInbox {
  pending: Gift[];
  /** UTC day of the last collect and how many were collected that day. */
  claimDay: string;
  claimed: number;
}

export interface GiftSent {
  day: string;
  to: string[];
}

function obj(raw: unknown): { [k: string]: unknown } {
  return typeof raw === 'object' && raw !== null ? (raw as { [k: string]: unknown }) : {};
}

export function normalizeInbox(raw: unknown): GiftInbox {
  const o = obj(raw);
  const pending: Gift[] = [];
  for (const g of Array.isArray(o['pending']) ? (o['pending'] as unknown[]) : []) {
    const r = obj(g);
    if (typeof r['from'] === 'string' && typeof r['at'] === 'number') pending.push({ from: r['from'] as string, name: typeof r['name'] === 'string' ? (r['name'] as string) : '', at: r['at'] as number });
  }
  return {
    pending,
    claimDay: typeof o['claimDay'] === 'string' ? (o['claimDay'] as string) : '',
    claimed: typeof o['claimed'] === 'number' && (o['claimed'] as number) > 0 ? Math.floor(o['claimed'] as number) : 0,
  };
}

/** Today's sent list; a row from an earlier day counts as empty. */
export function normalizeSent(raw: unknown, now: number): GiftSent {
  const o = obj(raw);
  const day = utcDate(now);
  if (o['day'] !== day) return { day, to: [] };
  const to = Array.isArray(o['to']) ? (o['to'] as unknown[]).filter((x): x is string => typeof x === 'string') : [];
  return { day, to };
}

/** Why a gift to `target` cannot go today, or ''. */
export function sendBlocker(sent: GiftSent, target: string): string {
  if (sent.to.indexOf(target) >= 0) return 'already sent today';
  if (sent.to.length >= GIFTS_SEND_PER_DAY) return 'no gifts left today';
  return '';
}

function fresh(pending: Gift[], now: number): Gift[] {
  return pending.filter((g) => now - g.at < GIFT_KEEP_DAYS * DAY_MS);
}

/** The inbox with a new gift: expired ones dropped, one waiting gift per sender, the oldest dropped past INBOX_MAX. */
export function addGift(inbox: GiftInbox, gift: Gift, now: number): GiftInbox {
  const pending = fresh(inbox.pending, now).filter((g) => g.from !== gift.from);
  pending.push(gift);
  return { ...inbox, pending: pending.slice(-INBOX_MAX) };
}

/** Gifts still collectable today. */
export function claimsLeft(inbox: GiftInbox, now: number): number {
  return Math.max(0, GIFTS_CLAIM_PER_DAY - (inbox.claimDay === utcDate(now) ? inbox.claimed : 0));
}

/** Collects the oldest waiting gifts up to today's cap: the new inbox, how many and the points. */
export function claimGifts(inbox: GiftInbox, now: number): { inbox: GiftInbox; count: number; points: number } {
  const today = utcDate(now);
  const pending = fresh(inbox.pending, now);
  const count = Math.min(pending.length, claimsLeft(inbox, now));
  const already = inbox.claimDay === today ? inbox.claimed : 0;
  return {
    inbox: { pending: pending.slice(count), claimDay: today, claimed: already + count },
    count,
    points: count * GIFT_POINTS,
  };
}

/** Waiting gifts that have not expired. */
export function waiting(inbox: GiftInbox, now: number): Gift[] {
  return fresh(inbox.pending, now);
}
