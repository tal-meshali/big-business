/**
 * Skin shop RPCs. The purchase itself happens on the device through the
 * store plugin; these only read and refresh what the server believes the
 * player owns (store.ts, purchases.ts).
 */
import { availableCosmetics, dropUnavailable } from './cosmetics';
import { isClientError, isUserId, reject, requireServer, requireUser } from './input';
import { loadProfile, saveProfile } from './profile';
import { readOwned, revenueCatKey, syncOwned } from './purchases';
import { checkRate } from './ratelimit';
import { catalog, unlockCatalog, webhookUserIds } from './store';

/** RevenueCat webhook bodies run to a few KB; anything far larger is not one. */
const WEBHOOK_MAX_BYTES = 65536;

/**
 * After a sync, a refunded skin that is still equipped goes back to the
 * default. Best effort: a racing profile write just leaves it for the next sync.
 */
function unequipLost(nk: nkruntime.Nakama, userId: string, owned: string[]): { cardBack: string; table: string } {
  const row = loadProfile(nk, userId);
  const p = row.progress;
  const equipped = dropUnavailable(p.equipped, availableCosmetics(p.trackPoints, owned));
  if (equipped !== p.equipped) {
    try {
      saveProfile(nk, userId, { ...p, equipped }, row.version);
    } catch (e) {
      return p.equipped;
    }
  }
  return equipped;
}

/** RPC store_catalog: the skins and unlocks on sale and which ones the caller owns. */
export const rpcStoreCatalog: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const owned = readOwned(nk, userId).owned;
  return JSON.stringify({ configured: revenueCatKey(ctx.env) !== '', skins: catalog(owned), unlocks: unlockCatalog(owned), owned });
};

/**
 * RPC sync_purchases: re-reads the caller's entitlements from RevenueCat.
 * The client calls it after a purchase and for Restore Purchases (after
 * the store plugin's own restore has reached RevenueCat).
 */
export const rpcSyncPurchases: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void payload;
  const userId = requireUser(ctx);
  checkRate(nk, userId, 'sync_purchases', Date.now());
  let result;
  try {
    result = syncOwned(nk, logger, ctx.env, userId);
  } catch (e) {
    if (isClientError(e)) throw e;
    logger.warn('purchase sync failed for %s: %s', userId, String(e));
    reject('store unavailable, try again');
  }
  const equipped = unequipLost(nk, userId, result.owned);
  const p = loadProfile(nk, userId).progress;
  return JSON.stringify({ configured: result.configured, owned: result.owned, equipped, unlocked: availableCosmetics(p.trackPoints, result.owned) });
};

function header(ctx: nkruntime.Context, name: string): string {
  const headers = ctx.headers || {};
  for (const k of Object.keys(headers)) {
    if (k.toLowerCase() === name) {
      const v = headers[k];
      return v && v.length > 0 ? String(v[0]) : '';
    }
  }
  return '';
}

/**
 * RPC revenuecat_webhook (server-to-server, called by RevenueCat with the
 * http_key and `unwrap`): re-syncs every Nakama user the event names, so a
 * refund or a purchase on another device lands without the app open.
 *
 * WHY the event body is not trusted: the Authorization header proves the
 * caller knows REVENUECAT_WEBHOOK_AUTH, but entitlements are still read back
 * from RevenueCat's API, so a replayed or forged event can only trigger a sync.
 */
export const rpcRevenueCatWebhook: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  requireServer(ctx);
  const secret = ctx.env && ctx.env['REVENUECAT_WEBHOOK_AUTH'] ? ctx.env['REVENUECAT_WEBHOOK_AUTH'].trim() : '';
  if (!secret || header(ctx, 'authorization') !== secret) reject('forbidden');
  if (typeof payload !== 'string' || payload.length > WEBHOOK_MAX_BYTES) reject('bad payload');
  let body: unknown = null;
  try {
    body = JSON.parse(payload);
  } catch (e) {
    reject('bad payload');
  }
  const users = webhookUserIds(body, isUserId);
  for (const userId of users) {
    try {
      unequipLost(nk, userId, syncOwned(nk, logger, ctx.env, userId).owned);
    } catch (e) {
      logger.warn('webhook sync failed for %s: %s', userId, String(e));
    }
  }
  return JSON.stringify({ ok: true, synced: users.length });
};
