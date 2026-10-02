/**
 * Nakama runtime entry point. Registers the Big Business match handler, the
 * room-code, profile, moderation, social, account-link, quest, cosmetic,
 * shop, push-token, Remote Config, analytics and Designer (custom card art)
 * RPCs.
 *
 * Every RPC goes through `guardRpc` (only messages raised with `reject`
 * reach the client) and reads its payload through the validators in
 * match/input.ts: the client is untrusted.
 */
import { matchInit, matchJoin, matchJoinAttempt, matchLeave, matchLoop, matchSignal, matchTerminate } from './match/handler';
import { SEASON_LEADERBOARD } from './match/progression';
import { MATCH_MODULE } from './match/protocol';
import { beforeAddFriends, beforeDeleteStorageObjects, beforeWriteStorageObjects } from './match/reports';
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
import {
  guardedCreateRoom,
  guardedJoinRoom,
  guardedQuickPlay,
  guardedGetProfile,
  guardedClaimDaily,
  guardedClaimQuest,
  guardedEquipCosmetic,
  guardedReportPlayer,
  guardedFindPlayer,
  guardedInviteFriend,
  guardedAccountLinks,
} from './match/guarded_core';
import {
  guardedClearDeckPart,
  guardedDesignerState,
  guardedGetCardArt,
  guardedModerateCardArt,
  guardedModerationQueue,
  guardedReportCardArt,
  guardedSelectDeck,
  guardedSetAgeBracket,
  guardedUploadCardArt,
} from './match/guarded_designer';

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
  initializer.registerRpc('designer_state', guardedDesignerState);
  initializer.registerRpc('set_age_bracket', guardedSetAgeBracket);
  initializer.registerRpc('upload_card_art', guardedUploadCardArt);
  initializer.registerRpc('clear_deck_part', guardedClearDeckPart);
  initializer.registerRpc('select_deck', guardedSelectDeck);
  initializer.registerRpc('get_card_art', guardedGetCardArt);
  initializer.registerRpc('report_card_art', guardedReportCardArt);
  // Server-to-server only (runtime http_key; they refuse player sessions).
  initializer.registerRpc('revenuecat_webhook', guardedRevenueCatWebhook);
  initializer.registerRpc('set_remote_config', guardedSetRemoteConfig);
  initializer.registerRpc('analytics_report', guardedAnalyticsReport);
  initializer.registerRpc('moderation_queue', guardedModerationQueue);
  initializer.registerRpc('moderate_card_art', guardedModerateCardArt);
  initializer.registerBeforeAddFriends(beforeAddFriends);
  initializer.registerBeforeWriteStorageObjects(beforeWriteStorageObjects);
  initializer.registerBeforeDeleteStorageObjects(beforeDeleteStorageObjects);
  logger.info('Big Business runtime loaded');
}

// Reference so the bundler keeps the global entry point.
!InitModule && InitModule.bind(null);
