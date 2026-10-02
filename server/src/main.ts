/**
 * Nakama runtime entry point. Registers the Big Business match handler, the
 * room-code, profile, moderation, social, account-link, quest, cosmetic,
 * shop, push-token, Remote Config and analytics RPCs.
 *
 * Every RPC goes through `guardRpc` (only messages raised with `reject`
 * reach the client) and reads its payload through the validators in
 * match/input.ts: the client is untrusted.
 */
import { matchInit, matchJoin, matchJoinAttempt, matchLeave, matchLoop, matchSignal, matchTerminate } from './match/handler';
import { guarded } from './match/input';
import { SEASON_LEADERBOARD } from './match/progression';
import { MATCH_MODULE } from './match/protocol';
import { beforeAddFriends, beforeDeleteStorageObjects, beforeWriteStorageObjects, rpcReportPlayer } from './match/reports';
import { rpcCreateRoom, rpcJoinRoom, rpcQuickPlay } from './match/rooms';
import { rpcClaimDaily, rpcGetProfile } from './match/rpc_profile';
import {
  guardedAnalyticsReport,
  guardedGetRemoteConfig,
  guardedRegisterPushToken,
  guardedRevenueCatWebhook,
  guardedSetRemoteConfig,
  guardedStoreCatalog,
  guardedSyncPurchases,
  guardedUnregisterPushToken,
} from './match/guarded_services';
import { rpcClaimQuest, rpcEquipCosmetic } from './match/rpc_quests';
import { rpcAccountLinks, rpcFindPlayer, rpcInviteFriend } from './match/social';

// Nakama resolves registerRpc arguments to named function literals in this
// module (it refuses wrappers such as guardRpc(fn)), so each guarded RPC is a
// named arrow here. See `guarded` in match/input.ts.
const guardedCreateRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcCreateRoom, ctx, logger, nk, payload);
const guardedJoinRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcJoinRoom, ctx, logger, nk, payload);
const guardedQuickPlay: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcQuickPlay, ctx, logger, nk, payload);
const guardedGetProfile: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcGetProfile, ctx, logger, nk, payload);
const guardedClaimDaily: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClaimDaily, ctx, logger, nk, payload);
const guardedClaimQuest: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClaimQuest, ctx, logger, nk, payload);
const guardedEquipCosmetic: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcEquipCosmetic, ctx, logger, nk, payload);
const guardedReportPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcReportPlayer, ctx, logger, nk, payload);
const guardedFindPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcFindPlayer, ctx, logger, nk, payload);
const guardedInviteFriend: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcInviteFriend, ctx, logger, nk, payload);
const guardedAccountLinks: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcAccountLinks, ctx, logger, nk, payload);

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {
  void ctx;
  // Monthly season: authoritative, descending, points accumulate, resets on the 1st.
  try {
    // nkruntime is types only at runtime, so pass the enum string values.
    nk.leaderboardCreate(SEASON_LEADERBOARD, true, 'descending' as nkruntime.SortOrder, 'increment' as nkruntime.Operator, '0 0 1 * *');
  } catch (e) {
    logger.warn('leaderboard create: %s', String(e));
  }
  initializer.registerMatch(MATCH_MODULE, {
    matchInit,
    matchJoinAttempt,
    matchJoin,
    matchLeave,
    matchLoop,
    matchTerminate,
    matchSignal,
  });
  initializer.registerRpc('create_room', guardedCreateRoom);
  initializer.registerRpc('join_room', guardedJoinRoom);
  initializer.registerRpc('quick_play', guardedQuickPlay);
  initializer.registerRpc('get_profile', guardedGetProfile);
  initializer.registerRpc('claim_daily', guardedClaimDaily);
  initializer.registerRpc('claim_quest', guardedClaimQuest);
  initializer.registerRpc('equip_cosmetic', guardedEquipCosmetic);
  initializer.registerRpc('report_player', guardedReportPlayer);
  initializer.registerRpc('find_player', guardedFindPlayer);
  initializer.registerRpc('invite_friend', guardedInviteFriend);
  initializer.registerRpc('account_links', guardedAccountLinks);
  initializer.registerRpc('store_catalog', guardedStoreCatalog);
  initializer.registerRpc('sync_purchases', guardedSyncPurchases);
  initializer.registerRpc('get_remote_config', guardedGetRemoteConfig);
  initializer.registerRpc('register_push_token', guardedRegisterPushToken);
  initializer.registerRpc('unregister_push_token', guardedUnregisterPushToken);
  // Server-to-server only (runtime http_key; they refuse player sessions).
  initializer.registerRpc('revenuecat_webhook', guardedRevenueCatWebhook);
  initializer.registerRpc('set_remote_config', guardedSetRemoteConfig);
  initializer.registerRpc('analytics_report', guardedAnalyticsReport);
  initializer.registerBeforeAddFriends(beforeAddFriends);
  initializer.registerBeforeWriteStorageObjects(beforeWriteStorageObjects);
  initializer.registerBeforeDeleteStorageObjects(beforeDeleteStorageObjects);
  logger.info('Big Business runtime loaded');
}

// Reference so the bundler keeps the global entry point.
!InitModule && InitModule.bind(null);
