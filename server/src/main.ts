/**
 * Nakama runtime entry point. Registers the Big Business match handler, the
 * room-code, profile, moderation, social, account-link, quest, cosmetic,
 * shop, push-token, Remote Config, analytics and Designer (custom card art)
 * RPCs, and clubs with their weekly league.
 *
 * Every RPC goes through `guardRpc` (only messages raised with `reject`
 * reach the client) and reads its payload through the validators in
 * match/input.ts: the client is untrusted.
 */
import { matchInit, matchJoin, matchJoinAttempt, matchLeave, matchLoop, matchSignal, matchTerminate } from './match/handler';
import { createLeaderboards } from './match/boards';
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
  guardedGetStats,
  guardedSelectDeck,
  guardedSetPublicDeck,
  guardedSetAgeBracket,
  guardedUploadCardArt,
} from './match/guarded_designer';
// WHY a namespace import: esbuild turns `social.x` back into the plain
// function name in the bundle (which Nakama needs), while the graph sees one
// dependency instead of one per RPC, keeping main.ts under the god-node limit.
import * as social from './match/guarded_social';
import { beforeChannelJoin, beforeGroupChange } from './match/rpc_clubs';

function InitModule(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, initializer: nkruntime.Initializer): void {
  void ctx;
  createLeaderboards(nk, logger);
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
  initializer.registerRpc('set_public_deck', guardedSetPublicDeck);
  initializer.registerRpc('get_card_art', guardedGetCardArt);
  initializer.registerRpc('report_card_art', guardedReportCardArt);
  initializer.registerRpc('get_stats', guardedGetStats);
  initializer.registerRpc('club_state', social.guardedClubState);
  initializer.registerRpc('club_list', social.guardedClubList);
  initializer.registerRpc('club_create', social.guardedClubCreate);
  initializer.registerRpc('club_join', social.guardedClubJoin);
  initializer.registerRpc('club_leave', social.guardedClubLeave);
  initializer.registerRpc('club_kick', social.guardedClubKick);
  initializer.registerRpc('gift_state', social.guardedGiftState);
  initializer.registerRpc('send_gift', social.guardedSendGift);
  initializer.registerRpc('claim_gifts', social.guardedClaimGifts);
  initializer.registerRpc('friends_playing', social.guardedFriendsPlaying);
  initializer.registerRpc('watch_friend', social.guardedWatchFriend);
  // Server-to-server only (runtime http_key; they refuse player sessions).
  initializer.registerRpc('revenuecat_webhook', guardedRevenueCatWebhook);
  initializer.registerRpc('set_remote_config', guardedSetRemoteConfig);
  initializer.registerRpc('analytics_report', guardedAnalyticsReport);
  initializer.registerRpc('moderation_queue', guardedModerationQueue);
  initializer.registerRpc('moderate_card_art', guardedModerateCardArt);
  initializer.registerBeforeAddFriends(beforeAddFriends);
  initializer.registerBeforeWriteStorageObjects(beforeWriteStorageObjects);
  initializer.registerBeforeDeleteStorageObjects(beforeDeleteStorageObjects);
  initializer.registerBeforeCreateGroup(beforeGroupChange);
  initializer.registerBeforeUpdateGroup(beforeGroupChange);
  initializer.registerBeforeJoinGroup(beforeGroupChange);
  initializer.registerBeforeAddGroupUsers(beforeGroupChange);
  initializer.registerRtBefore('ChannelJoin', beforeChannelJoin);
  logger.info('Big Business runtime loaded');
}

// Reference so the bundler keeps the global entry point.
!InitModule && InitModule.bind(null);
