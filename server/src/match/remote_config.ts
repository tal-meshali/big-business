/**
 * Remote Config: a few switches the operator can change without a release.
 * Pure: the defaults, the allowed keys and their ranges. Storage and the
 * RPCs are in rpc_config.ts.
 *
 * WHY in Nakama and not Firebase Remote Config: the server reads some of
 * these values itself (the push kill switch, the quick-play wait), so they
 * must live where the server can read them; the client gets the same values
 * over the session it already has, with no extra SDK.
 */

export const CONFIG_COLLECTION = 'config';
export const CONFIG_KEY = 'remote';

export interface RemoteConfig {
  /** Show the skin shop in the lobby. */
  shopEnabled: boolean;
  /** Send "your turn" pushes at all. */
  pushEnabled: boolean;
  /** Fewest minutes between two "your turn" pushes to one player in one match. */
  pushCooldownMinutes: number;
  /** Send a brand-new player's first "Play now" to the tutorial (TODO-local B2). */
  tutorialAutoRoute: boolean;
  /** Seconds a new quick-play lobby waits for people before bots fill it. */
  quickPlayWaitSeconds: number;
  /** Designer unlock: uploads and custom decks in private rooms (kill switch). */
  designerEnabled: boolean;
  /**
   * Offer the Plus subscription in the shop. Off by default: decision D5
   * launches without a subscription. Members keep their benefits either way.
   */
  plusEnabled: boolean;
}

export const DEFAULT_CONFIG: RemoteConfig = {
  shopEnabled: true,
  pushEnabled: true,
  pushCooldownMinutes: 10,
  tutorialAutoRoute: false,
  quickPlayWaitSeconds: 20,
  designerEnabled: true,
  plusEnabled: false,
};

/** Integer keys and their allowed range; values outside are clamped. */
const RANGES: { [key: string]: [number, number] } = {
  pushCooldownMinutes: [1, 1440],
  quickPlayWaitSeconds: [5, 60],
};

/**
 * Layers `patch` over `base`, keeping only known keys with the right type.
 * Used both to read a stored row (base = defaults) and to apply an
 * operator's update (base = current), so a bad value never gets stored.
 */
export function mergeConfig(base: RemoteConfig, patch: unknown): RemoteConfig {
  const out: RemoteConfig = { ...base };
  if (typeof patch !== 'object' || patch === null || Array.isArray(patch)) return out;
  const p = patch as { [key: string]: unknown };
  const target = out as unknown as { [key: string]: unknown };
  for (const key of Object.keys(DEFAULT_CONFIG)) {
    const v = p[key];
    const def = (DEFAULT_CONFIG as unknown as { [key: string]: unknown })[key];
    if (typeof def === 'boolean' && typeof v === 'boolean') target[key] = v;
    if (typeof def === 'number' && typeof v === 'number' && isFinite(v)) {
      const range = RANGES[key] || [0, Number.MAX_SAFE_INTEGER];
      target[key] = Math.min(range[1], Math.max(range[0], Math.round(v)));
    }
  }
  return out;
}
