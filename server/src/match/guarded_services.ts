/**
 * Guarded wrappers for the shop, push-token, Remote Config and analytics
 * RPCs, registered by main.ts. They live here so main.ts stays under the
 * graph's god-node limit (docs/conventions.md).
 *
 * WHY each is a named arrow: Nakama resolves registerRpc arguments to named
 * function literals at the top level of the bundled module (see `guarded`
 * in input.ts); esbuild hoists these consts to that top level unchanged.
 */
import { guarded } from './input';
import { rpcAnalyticsReport, rpcGetRemoteConfig, rpcSetRemoteConfig } from './rpc_config';
import { rpcRegisterPushToken, rpcUnregisterPushToken } from './rpc_push';
import { rpcRevenueCatWebhook, rpcStoreCatalog, rpcSyncPurchases } from './rpc_store';

export const guardedStoreCatalog: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcStoreCatalog, ctx, logger, nk, payload);
export const guardedSyncPurchases: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSyncPurchases, ctx, logger, nk, payload);
export const guardedRevenueCatWebhook: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcRevenueCatWebhook, ctx, logger, nk, payload);
export const guardedGetRemoteConfig: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcGetRemoteConfig, ctx, logger, nk, payload);
export const guardedSetRemoteConfig: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSetRemoteConfig, ctx, logger, nk, payload);
export const guardedAnalyticsReport: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcAnalyticsReport, ctx, logger, nk, payload);
export const guardedRegisterPushToken: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcRegisterPushToken, ctx, logger, nk, payload);
export const guardedUnregisterPushToken: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcUnregisterPushToken, ctx, logger, nk, payload);
