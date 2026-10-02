/**
 * Guarded wrappers for the club, gift and watch RPCs, registered by main.ts. Kept apart
 * from the other guarded_*.ts files so none nears the graph's god-node
 * limit (docs/conventions.md). Each is a named arrow for the reason given
 * in guarded_services.ts.
 */
import { guarded } from './input';
import { rpcClaimGifts, rpcGiftState, rpcSendGift } from './rpc_gifts';
import { rpcFriendsPlaying, rpcWatchFriend } from './rpc_watch';
import { rpcClubCreate, rpcClubJoin, rpcClubKick, rpcClubLeave, rpcClubList, rpcClubState } from './rpc_clubs';

export const guardedClubState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubState, ctx, logger, nk, payload);
export const guardedClubList: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubList, ctx, logger, nk, payload);
export const guardedClubCreate: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubCreate, ctx, logger, nk, payload);
export const guardedClubJoin: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubJoin, ctx, logger, nk, payload);
export const guardedClubLeave: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubLeave, ctx, logger, nk, payload);
export const guardedClubKick: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubKick, ctx, logger, nk, payload);
export const guardedGiftState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcGiftState, ctx, logger, nk, payload);
export const guardedSendGift: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSendGift, ctx, logger, nk, payload);
export const guardedClaimGifts: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClaimGifts, ctx, logger, nk, payload);
export const guardedFriendsPlaying: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcFriendsPlaying, ctx, logger, nk, payload);
export const guardedWatchFriend: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcWatchFriend, ctx, logger, nk, payload);
