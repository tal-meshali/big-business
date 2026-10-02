/**
 * Guarded wrappers for the room, profile, quest, moderation and social RPCs,
 * registered by main.ts. They live here so main.ts stays under the graph's
 * god-node limit (docs/conventions.md); each is a named arrow for the reason
 * given in guarded_services.ts.
 */
import { guarded } from './input';
import { rpcReportPlayer } from './reports';
import { rpcCreateRoom, rpcJoinRoom, rpcQuickPlay } from './rooms';
import { rpcClaimDaily, rpcGetProfile } from './rpc_profile';
import { rpcClaimQuest, rpcEquipCosmetic } from './rpc_quests';
import { rpcAccountLinks, rpcFindPlayer, rpcInviteFriend } from './social';

export const guardedCreateRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcCreateRoom, ctx, logger, nk, payload);
export const guardedJoinRoom: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcJoinRoom, ctx, logger, nk, payload);
export const guardedQuickPlay: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcQuickPlay, ctx, logger, nk, payload);
export const guardedGetProfile: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcGetProfile, ctx, logger, nk, payload);
export const guardedClaimDaily: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClaimDaily, ctx, logger, nk, payload);
export const guardedClaimQuest: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClaimQuest, ctx, logger, nk, payload);
export const guardedEquipCosmetic: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcEquipCosmetic, ctx, logger, nk, payload);
export const guardedReportPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcReportPlayer, ctx, logger, nk, payload);
export const guardedFindPlayer: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcFindPlayer, ctx, logger, nk, payload);
export const guardedInviteFriend: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcInviteFriend, ctx, logger, nk, payload);
export const guardedAccountLinks: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcAccountLinks, ctx, logger, nk, payload);
