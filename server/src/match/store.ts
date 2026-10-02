/**
 * Curated skins sold a la carte: the mapping from a paid cosmetic to its
 * store product and RevenueCat entitlement, and the pure parsing of
 * RevenueCat's subscriber record into the skins a player owns.
 *
 * WHY entitlements are read on the server (decision D5): the client is
 * untrusted, so it never says what it bought. It buys through the store
 * plugin, then asks the server to sync; the server asks RevenueCat with the
 * secret key and stores the result in a row only the server writes.
 */
import { COSMETICS, PLUS_OWNED_ID, type CosmeticSlot } from './cosmetics';

export const PURCHASE_COLLECTION = 'purchases';
export const PURCHASE_KEY = 'owned';

export interface Skin {
  /** Cosmetic id (cosmetics.ts), also the client's id. */
  id: string;
  slot: CosmeticSlot;
  name: string;
  /** App Store / Play product id; the same id in both stores. */
  productId: string;
  /** RevenueCat entitlement that the product grants. */
  entitlement: string;
}

/** Product ids are `bb_skin_<cosmetic id>`, entitlements `skin_<cosmetic id>`. */
export const SKINS: ReadonlyArray<Skin> = COSMETICS.filter((c) => c.paid).map((c) => ({
  id: c.id,
  slot: c.slot,
  name: c.name,
  productId: 'bb_skin_' + c.id,
  entitlement: 'skin_' + c.id,
}));

export function skinById(id: string): Skin | null {
  for (const s of SKINS) if (s.id === id) return s;
  return null;
}

/** A one-time feature unlock (non-consumable), not a cosmetic. */
export interface Unlock {
  id: string;
  name: string;
  productId: string;
  entitlement: string;
}

/**
 * Designer (decision D5): custom card designs in private rooms. Its id
 * shares the owned list with the skins, so it must never equal a cosmetic id.
 */
export const DESIGNER = 'designer';
/**
 * Plus: a monthly subscription (plus.ts). Its entitlement expires, so the
 * owned row keeps the expiry and readers drop it once passed.
 */
export const PLUS = PLUS_OWNED_ID;
export const UNLOCKS: ReadonlyArray<Unlock> = [
  { id: DESIGNER, name: 'Designer', productId: 'bb_designer', entitlement: 'designer' },
  { id: PLUS, name: 'Plus', productId: 'bb_plus_monthly', entitlement: 'plus' },
];

/** Every product the server reads from RevenueCat: skins, then unlocks. */
const PRODUCTS: ReadonlyArray<{ id: string; entitlement: string }> = (SKINS as ReadonlyArray<{ id: string; entitlement: string }>).concat(UNLOCKS);

function isProductId(id: string): boolean {
  for (const p of PRODUCTS) if (p.id === id) return true;
  return false;
}

/** The stored purchase row. */
export interface OwnedRow {
  owned: string[];
  /** Epoch ms of the last successful sync with RevenueCat; 0 when never. */
  syncedAt: number;
  /** Expiry (epoch ms) of owned ids that expire, such as Plus; lifetime ids are absent. */
  expires: { [id: string]: number };
}

/** Keeps only known skin and unlock ids, once each; anything else in a stored row is dropped. */
export function normalizeOwned(raw: unknown): OwnedRow {
  const obj = (typeof raw === 'object' && raw !== null ? raw : {}) as { owned?: unknown; syncedAt?: unknown; expires?: unknown };
  const owned: string[] = [];
  if (Array.isArray(obj.owned)) {
    for (const id of obj.owned) {
      if (typeof id === 'string' && isProductId(id) && owned.indexOf(id) < 0) owned.push(id);
    }
  }
  const syncedAt = typeof obj.syncedAt === 'number' && isFinite(obj.syncedAt) && obj.syncedAt > 0 ? obj.syncedAt : 0;
  const expires: { [id: string]: number } = {};
  const rawExpires = (typeof obj.expires === 'object' && obj.expires !== null ? obj.expires : {}) as { [id: string]: unknown };
  for (const id of owned) {
    const t = rawExpires[id];
    if (typeof t === 'number' && isFinite(t)) expires[id] = t;
  }
  return { owned, syncedAt, expires };
}

/** Owned ids still active at `nowMs`: an expired subscription drops out without waiting for a sync. */
export function activeOwned(row: OwnedRow, nowMs: number): string[] {
  return row.owned.filter((id) => !(id in row.expires) || (row.expires[id] as number) > nowMs);
}

/**
 * Skins and unlocks owned according to a RevenueCat `GET /v1/subscribers/{id}` body.
 * An entitlement counts while it has no expiry (non-consumables) or its
 * expiry is in the future. A refunded purchase loses its entitlement in
 * RevenueCat, so it drops out here on the next sync. Never throws.
 */
export function ownedFromSubscriber(body: unknown, nowMs: number): string[] {
  return entitlementsFromSubscriber(body, nowMs).owned;
}

/** Like ownedFromSubscriber, with the expiry of every owned id that has one. */
export function entitlementsFromSubscriber(body: unknown, nowMs: number): { owned: string[]; expires: { [id: string]: number } } {
  const root = (typeof body === 'object' && body !== null ? body : {}) as { subscriber?: unknown };
  const sub = (typeof root.subscriber === 'object' && root.subscriber !== null ? root.subscriber : {}) as { entitlements?: unknown };
  const ents = (typeof sub.entitlements === 'object' && sub.entitlements !== null ? sub.entitlements : {}) as { [id: string]: unknown };
  const owned: string[] = [];
  const expiry: { [id: string]: number } = {};
  for (const product of PRODUCTS) {
    const e = ents[product.entitlement];
    if (typeof e !== 'object' || e === null) continue;
    const expires = (e as { expires_date?: unknown }).expires_date;
    if (expires === null || expires === undefined) {
      owned.push(product.id);
      continue;
    }
    const t = typeof expires === 'string' ? Date.parse(expires) : NaN;
    if (isFinite(t) && t > nowMs) {
      owned.push(product.id);
      expiry[product.id] = t;
    }
  }
  return { owned, expires: expiry };
}

/** Skins in `next` that were not in `prev`: new purchases, for analytics. */
export function newlyOwned(prev: ReadonlyArray<string>, next: ReadonlyArray<string>): string[] {
  return next.filter((id) => prev.indexOf(id) < 0);
}

/** One shop row for the client. Prices come from the store plugin, not from here. */
export interface CatalogRow {
  id: string;
  slot: CosmeticSlot;
  name: string;
  productId: string;
  owned: boolean;
}

export function catalog(owned: ReadonlyArray<string>): CatalogRow[] {
  return SKINS.map((s) => ({ id: s.id, slot: s.slot, name: s.name, productId: s.productId, owned: owned.indexOf(s.id) >= 0 }));
}

/** The unlocks on sale, for the client; prices come from the store plugin. */
export function unlockCatalog(owned: ReadonlyArray<string>): Array<{ id: string; name: string; productId: string; owned: boolean }> {
  return UNLOCKS.map((u) => ({ id: u.id, name: u.name, productId: u.productId, owned: owned.indexOf(u.id) >= 0 }));
}

/**
 * The app user ids a RevenueCat webhook event concerns. Only Nakama user
 * ids count (the client logs in to RevenueCat with its Nakama user id);
 * anonymous RevenueCat ids are ignored. TRANSFER events name both sides.
 */
export function webhookUserIds(body: unknown, isUserId: (v: unknown) => boolean): string[] {
  const root = (typeof body === 'object' && body !== null ? body : {}) as { event?: unknown };
  const ev = (typeof root.event === 'object' && root.event !== null ? root.event : {}) as { [k: string]: unknown };
  const candidates: unknown[] = [ev['app_user_id'], ev['original_app_user_id']];
  for (const key of ['transferred_from', 'transferred_to', 'aliases']) {
    const list = ev[key];
    if (Array.isArray(list)) for (const v of list) candidates.push(v);
  }
  const out: string[] = [];
  for (const c of candidates) {
    if (isUserId(c) && out.indexOf(c as string) < 0) out.push(c as string);
  }
  return out.slice(0, 10);
}
