/**
 * Cosmetics: card backs and table felts. Most are unlocked by XP on
 * the free track; a few curated skins are sold a la carte for real money
 * through the stores (store.ts maps them to RevenueCat entitlements). Ids are
 * shared with the client (client/scripts/game/cosmetics.gd). No virtual
 * currency, no loot boxes (decision D5); the free track keeps paid skins
 * optional.
 */

export type CosmeticSlot = 'cardBack' | 'table';

export interface Cosmetic {
  id: string;
  slot: CosmeticSlot;
  name: string;
  /** Sold in the shop; owned only through a purchase, never through the track. */
  paid?: boolean;
  /** Plus collection: usable while Plus is active, from this UTC month (YYYY-MM) on. */
  plusSince?: string;
}

/** Owned id of the Plus subscription (store.ts PLUS); here so this module imports nothing. */
export const PLUS_OWNED_ID = 'plus';

export interface Equipped {
  cardBack: string;
  table: string;
}

export interface TrackStep {
  /** Track XP (progression.ts trackXp) at which the cosmetic unlocks. */
  xp: number;
  cosmeticId: string;
}

export const COSMETICS: ReadonlyArray<Cosmetic> = [
  { id: 'back_classic', slot: 'cardBack', name: 'Classic' },
  { id: 'back_midnight', slot: 'cardBack', name: 'Midnight' },
  { id: 'back_sunrise', slot: 'cardBack', name: 'Sunrise' },
  { id: 'back_pinstripe', slot: 'cardBack', name: 'Pinstripe' },
  { id: 'table_green', slot: 'table', name: 'Board green' },
  { id: 'table_navy', slot: 'table', name: 'Navy felt' },
  { id: 'table_burgundy', slot: 'table', name: 'Burgundy felt' },
  { id: 'back_gilded', slot: 'cardBack', name: 'Gilded', paid: true },
  { id: 'back_blueprint', slot: 'cardBack', name: 'Blueprint', paid: true },
  { id: 'table_walnut', slot: 'table', name: 'Walnut', paid: true },
  // Plus: a new skin each month. WHY dated: members get each month's skin on
  // its month, so the collection keeps growing without a client release
  // gating it (the client still needs the drawing, shipped ahead).
  { id: 'back_ticker', slot: 'cardBack', name: 'Ticker', plusSince: '2026-10' },
  { id: 'table_slate', slot: 'table', name: 'Slate', plusSince: '2026-11' },
];

/** Plus skins released by `nowMs` (UTC month). */
export function plusCosmetics(nowMs: number): string[] {
  const month = new Date(nowMs).toISOString().slice(0, 7);
  return COSMETICS.filter((c) => c.plusSince && c.plusSince <= month).map((c) => c.id);
}

/** Everyone owns the defaults. */
export const DEFAULT_EQUIPPED: Equipped = { cardBack: 'back_classic', table: 'table_green' };

/**
 * Track thresholds in XP. A normal day of two or three games with the
 * dailies earns about 370 XP (docs/design/engagement-plan.md section 3), so
 * the whole track takes roughly ten active days. Each is a multiple of
 * TRACK_XP_PER_POINT, so a profile stored in track points (progression.ts
 * normalizeProgress) lands exactly on the step it had reached.
 */
export const TRACK: ReadonlyArray<TrackStep> = [
  { xp: 360, cosmeticId: 'back_midnight' },
  { xp: 840, cosmeticId: 'table_navy' },
  { xp: 1440, cosmeticId: 'back_sunrise' },
  { xp: 2400, cosmeticId: 'table_burgundy' },
  { xp: 3600, cosmeticId: 'back_pinstripe' },
];

export function cosmeticById(id: string): Cosmetic | null {
  for (const c of COSMETICS) if (c.id === id) return c;
  return null;
}

/** Ids owned at this much track XP: the defaults plus every reached step. */
export function unlockedCosmetics(trackXp: number): string[] {
  const out: string[] = [DEFAULT_EQUIPPED.cardBack, DEFAULT_EQUIPPED.table];
  for (const step of TRACK) {
    if (trackXp >= step.xp && out.indexOf(step.cosmeticId) < 0) out.push(step.cosmeticId);
  }
  return out;
}

/** The first step not yet reached, or null when the track is complete. */
export function nextUnlock(trackXp: number): TrackStep | null {
  for (const step of TRACK) if (trackXp < step.xp) return step;
  return null;
}

/**
 * Everything the player may equip: the track unlocks, the paid skins in
 * `owned` (purchased ids from the server's purchase row), and the released
 * Plus skins while Plus is in `owned`. Ids in `owned`
 * that are not paid skins are ignored, so a purchase row can never unlock a
 * track item early.
 */
export function availableCosmetics(trackXp: number, owned: ReadonlyArray<string>, nowMs: number = Date.now()): string[] {
  const out = unlockedCosmetics(trackXp);
  for (const id of owned) {
    const c = cosmeticById(id);
    if (c && c.paid && out.indexOf(id) < 0) out.push(id);
  }
  if (owned.indexOf(PLUS_OWNED_ID) >= 0) for (const id of plusCosmetics(nowMs)) out.push(id);
  return out;
}

/** Equips `id` into `slot` when it exists, fits the slot and is unlocked or owned. */
export function equipCosmetic(equipped: Equipped, trackXp: number, slot: string, id: string, owned: ReadonlyArray<string> = []): { ok: boolean; equipped: Equipped } {
  const c = cosmeticById(id);
  if (!c || c.slot !== slot || availableCosmetics(trackXp, owned).indexOf(id) < 0) return { ok: false, equipped };
  const next: Equipped = { cardBack: equipped.cardBack, table: equipped.table };
  next[c.slot] = id;
  return { ok: true, equipped: next };
}

/** Fills missing or unknown selections with the defaults (old stored rows). */
export function normalizeEquipped(e: Partial<Equipped> | undefined): Equipped {
  const cardBack = e && typeof e.cardBack === 'string' && cosmeticById(e.cardBack) ? e.cardBack : DEFAULT_EQUIPPED.cardBack;
  const table = e && typeof e.table === 'string' && cosmeticById(e.table) ? e.table : DEFAULT_EQUIPPED.table;
  return { cardBack, table };
}

/**
 * Puts a slot back to its default when its cosmetic is no longer available
 * (a refunded or revoked purchase). Returns the same object when nothing changed.
 */
export function dropUnavailable(equipped: Equipped, available: ReadonlyArray<string>): Equipped {
  const cardBack = available.indexOf(equipped.cardBack) >= 0 ? equipped.cardBack : DEFAULT_EQUIPPED.cardBack;
  const table = available.indexOf(equipped.table) >= 0 ? equipped.table : DEFAULT_EQUIPPED.table;
  if (cardBack === equipped.cardBack && table === equipped.table) return equipped;
  return { cardBack, table };
}
