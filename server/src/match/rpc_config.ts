/**
 * Remote Config storage and RPCs, plus the analytics report. `get_remote_config`
 * is for players; `set_remote_config` and `analytics_report` are
 * server-to-server only (called with the runtime http_key, see docs/deploy.md).
 */
import { parseBody, readInt, requireServer, requireUser } from './input';
import { readCohorts } from './metrics';
import { CONFIG_COLLECTION, CONFIG_KEY, DEFAULT_CONFIG, mergeConfig, type RemoteConfig } from './remote_config';
import { SYSTEM_USER } from './protocol';

/** The stored config over the defaults; the defaults when storage fails. */
export function readRemoteConfig(nk: nkruntime.Nakama): RemoteConfig {
  try {
    const row = nk.storageRead([{ collection: CONFIG_COLLECTION, key: CONFIG_KEY, userId: SYSTEM_USER }])[0];
    return mergeConfig(DEFAULT_CONFIG, row ? row.value : null);
  } catch (e) {
    return { ...DEFAULT_CONFIG };
  }
}

/** RPC get_remote_config: the current switches. */
export const rpcGetRemoteConfig: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  requireUser(ctx);
  return JSON.stringify(readRemoteConfig(nk));
};

/**
 * RPC set_remote_config (server-to-server): merges the known keys of the
 * payload into the stored config and returns the result.
 */
export const rpcSetRemoteConfig: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  requireServer(ctx);
  const next = mergeConfig(readRemoteConfig(nk), parseBody(payload));
  nk.storageWrite([{ collection: CONFIG_COLLECTION, key: CONFIG_KEY, userId: SYSTEM_USER, value: next, permissionRead: 0, permissionWrite: 0 }]);
  logger.info('remote config set: %s', JSON.stringify(next));
  return JSON.stringify(next);
};

/** RPC analytics_report {days?} (server-to-server): install cohorts with D1 / D7 and the funnel. */
export const rpcAnalyticsReport: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  requireServer(ctx);
  const days = readInt(parseBody(payload), 'days', 1, 60, 14);
  return JSON.stringify({ cohorts: readCohorts(nk, Date.now(), days) });
};
