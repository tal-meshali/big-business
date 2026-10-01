/**
 * Free cosmetic track: card backs and table felts unlocked by quest points.
 * Ids are shared with the client (client/scripts/game/cosmetics.gd). No
 * purchases here (decision D5: no virtual currency, no loot boxes); the
 * track is the free earnable path so any later paid skins feel optional.
 */

export type CosmeticSlot = 'cardBack' | 'table';

export interface Cosmetic {
  id: string;
  slot: CosmeticSlot;
  name: string;
}

export interface Equipped {
  cardBack: string;
  table: string;
}

export interface TrackStep {
  points: number;
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
];

/** Everyone owns the defaults. */
export const DEFAULT_EQUIPPED: Equipped = { cardBack: 'back_classic', table: 'table_green' };

/**
 * Track thresholds in quest points. Three dailies a day are worth about 30
 * points, so the whole track takes roughly ten active days: long enough to
 * matter, short enough that a casual player finishes it.
 */
export const TRACK: ReadonlyArray<TrackStep> = [
  { points: 30, cosmeticId: 'back_midnight' },
  { points: 70, cosmeticId: 'table_navy' },
  { points: 120, cosmeticId: 'back_sunrise' },
  { points: 200, cosmeticId: 'table_burgundy' },
  { points: 300, cosmeticId: 'back_pinstripe' },
];

export function cosmeticById(id: string): Cosmetic | null {
  for (const c of COSMETICS) if (c.id === id) return c;
  return null;
}

/** Ids owned at this many track points: the defaults plus every reached step. */
export function unlockedCosmetics(trackPoints: number): string[] {
  const out: string[] = [DEFAULT_EQUIPPED.cardBack, DEFAULT_EQUIPPED.table];
  for (const step of TRACK) {
    if (trackPoints >= step.points && out.indexOf(step.cosmeticId) < 0) out.push(step.cosmeticId);
  }
  return out;
}

/** The first step not yet reached, or null when the track is complete. */
export function nextUnlock(trackPoints: number): TrackStep | null {
  for (const step of TRACK) if (trackPoints < step.points) return step;
  return null;
}

/** Equips `id` into `slot` when it exists, fits the slot and is unlocked. */
export function equipCosmetic(equipped: Equipped, trackPoints: number, slot: string, id: string): { ok: boolean; equipped: Equipped } {
  const c = cosmeticById(id);
  if (!c || c.slot !== slot || unlockedCosmetics(trackPoints).indexOf(id) < 0) return { ok: false, equipped };
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
