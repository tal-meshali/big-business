/**
 * The server's copy of what a player bought: read from RevenueCat with the
 * secret API key and kept in a row only the server writes. store.ts holds
 * the pure parsing.
 *
 * Config (Nakama runtime env, docs/deploy.md): REVENUECAT_API_KEY is the
 * RevenueCat *secret* key (sk_...). Without it, syncing reports
 * `configured: false` and the owned list stays as stored (empty).
 */
import { trackMilestone } from './metrics';
import { newlyOwned, normalizeOwned, ownedFromSubscriber, PURCHASE_COLLECTION, PURCHASE_KEY, type OwnedRow } from './store';

const REVENUECAT_API = 'https://api.revenuecat.com/v1/subscribers/';
const HTTP_TIMEOUT_MS = 5000;

export function revenueCatKey(env: { [key: string]: string } | undefined): string {
  return env && typeof env['REVENUECAT_API_KEY'] === 'string' ? env['REVENUECAT_API_KEY'].trim() : '';
}

export function readOwned(nk: nkruntime.Nakama, userId: string): OwnedRow {
  const row = nk.storageRead([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId }])[0];
  // Same rule as the profile row: a row the client wrote itself is ignored.
  if (!row || row.permissionWrite !== 0) return normalizeOwned(null);
  return normalizeOwned(row.value);
}

export interface SyncResult {
  configured: boolean;
  owned: string[];
}

/**
 * Asks RevenueCat what `userId` owns and stores it. Throws when RevenueCat
 * cannot be reached or answers with an error, so a failed call never
 * wipes what the player already owns.
 */
export function syncOwned(nk: nkruntime.Nakama, logger: nkruntime.Logger, env: { [key: string]: string } | undefined, userId: string): SyncResult {
  const key = revenueCatKey(env);
  const before = readOwned(nk, userId);
  if (!key) return { configured: false, owned: before.owned };
  const res = nk.httpRequest(REVENUECAT_API + encodeURIComponent(userId), 'get', { Authorization: 'Bearer ' + key, Accept: 'application/json' }, undefined, HTTP_TIMEOUT_MS);
  if (res.code !== 200) throw new Error('revenuecat answered ' + res.code);
  const now = Date.now();
  const owned = ownedFromSubscriber(JSON.parse(res.body), now);
  nk.storageWrite([{ collection: PURCHASE_COLLECTION, key: PURCHASE_KEY, userId, value: { owned, syncedAt: now }, permissionRead: 1, permissionWrite: 0 }]);
  const added = newlyOwned(before.owned, owned);
  if (added.length > 0) {
    logger.info('purchases for %s: +%s', userId, added.join(','));
    trackMilestone(nk, logger, userId, 'purchase', now);
  }
  return { configured: true, owned };
}
