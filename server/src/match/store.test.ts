import { describe, expect, it } from 'vitest';
import { availableCosmetics, dropUnavailable, equipCosmetic, unlockedCosmetics } from './cosmetics';
import { isUserId } from './input';
import { catalog, newlyOwned, normalizeOwned, ownedFromSubscriber, SKINS, webhookUserIds } from './store';

const NOW = Date.parse('2026-10-02T12:00:00Z');
const USER = '0f8fad5b-d9cb-469f-a165-70867728950e';

function subscriber(entitlements: { [id: string]: { expires_date: string | null } }): unknown {
  return { request_date: '2026-10-02T12:00:00Z', subscriber: { entitlements, non_subscriptions: {} } };
}

describe('skin catalog', () => {
  it('maps every paid cosmetic to a product and an entitlement', () => {
    expect(SKINS.map((s) => s.id)).toEqual(['back_gilded', 'back_blueprint', 'table_walnut']);
    expect(SKINS[0]).toMatchObject({ productId: 'bb_skin_back_gilded', entitlement: 'skin_back_gilded', slot: 'cardBack' });
  });

  it('marks owned rows in the client catalog', () => {
    const rows = catalog(['table_walnut']);
    expect(rows.find((r) => r.id === 'table_walnut')?.owned).toBe(true);
    expect(rows.find((r) => r.id === 'back_gilded')?.owned).toBe(false);
  });
});

describe('ownedFromSubscriber', () => {
  it('counts lifetime entitlements and unexpired ones', () => {
    const body = subscriber({
      skin_back_gilded: { expires_date: null },
      skin_table_walnut: { expires_date: '2026-11-01T00:00:00Z' },
      skin_back_blueprint: { expires_date: '2026-09-01T00:00:00Z' },
    });
    expect(ownedFromSubscriber(body, NOW)).toEqual(['back_gilded', 'table_walnut']);
  });

  it('ignores unknown entitlements and junk', () => {
    expect(ownedFromSubscriber(subscriber({ gold: { expires_date: null } }), NOW)).toEqual([]);
    expect(ownedFromSubscriber(null, NOW)).toEqual([]);
    expect(ownedFromSubscriber({ subscriber: { entitlements: 'x' } }, NOW)).toEqual([]);
    expect(ownedFromSubscriber(subscriber({ skin_back_gilded: { expires_date: 'not a date' } }), NOW)).toEqual([]);
  });

  it('reports only skins that are new since the last sync', () => {
    expect(newlyOwned(['back_gilded'], ['back_gilded', 'table_walnut'])).toEqual(['table_walnut']);
  });
});

describe('normalizeOwned', () => {
  it('keeps known skins once and drops track items or junk', () => {
    expect(normalizeOwned({ owned: ['back_gilded', 'back_gilded', 'back_midnight', 7, 'nope'], syncedAt: 5 })).toEqual({ owned: ['back_gilded'], syncedAt: 5, expires: {} });
    expect(normalizeOwned('x')).toEqual({ owned: [], syncedAt: 0, expires: {} });
  });
});

describe('paid skins and the cosmetic picker', () => {
  it('are never unlocked by track points', () => {
    expect(unlockedCosmetics(100000)).not.toContain('back_gilded');
  });

  it('can be equipped only when owned', () => {
    const eq = { cardBack: 'back_classic', table: 'table_green' };
    expect(equipCosmetic(eq, 0, 'cardBack', 'back_gilded').ok).toBe(false);
    expect(equipCosmetic(eq, 0, 'cardBack', 'back_gilded', ['back_gilded']).equipped.cardBack).toBe('back_gilded');
    expect(equipCosmetic(eq, 0, 'table', 'back_gilded', ['back_gilded']).ok).toBe(false);
  });

  it('cannot unlock a track item through the owned list', () => {
    expect(availableCosmetics(0, ['back_pinstripe'])).not.toContain('back_pinstripe');
  });

  it('go back to the default when the purchase is gone', () => {
    const eq = { cardBack: 'back_gilded', table: 'table_navy' };
    expect(dropUnavailable(eq, availableCosmetics(70, []))).toEqual({ cardBack: 'back_classic', table: 'table_navy' });
    const kept = { cardBack: 'back_gilded', table: 'table_green' };
    expect(dropUnavailable(kept, availableCosmetics(0, ['back_gilded']))).toBe(kept);
  });
});

describe('webhookUserIds', () => {
  it('collects Nakama user ids from an event, including transfers', () => {
    const other = '1f8fad5b-d9cb-469f-a165-70867728950e';
    const body = { event: { app_user_id: USER, original_app_user_id: '$RCAnonymousID:abc', transferred_to: [other], transferred_from: [USER] } };
    expect(webhookUserIds(body, isUserId)).toEqual([USER, other]);
  });

  it('returns nothing for junk', () => {
    expect(webhookUserIds('x', isUserId)).toEqual([]);
    expect(webhookUserIds({ event: { app_user_id: 5 } }, isUserId)).toEqual([]);
  });
});
