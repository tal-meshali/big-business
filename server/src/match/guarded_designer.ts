/**
 * Guarded wrappers for the Designer, card-art moderation and Plus stats RPCs, registered
 * by main.ts. Kept apart from guarded_services.ts so neither file nears the
 * graph's god-node limit (docs/conventions.md). Each is a named arrow for
 * the reason given in guarded_services.ts.
 */
import { guarded } from './input';
import { rpcClearDeckPart, rpcDesignerState, rpcGetCardArt, rpcReportCardArt, rpcSelectDeck, rpcSetAgeBracket, rpcSetPublicDeck, rpcUploadCardArt } from './rpc_designer';
import { rpcModerateCardArt, rpcModerationQueue } from './rpc_moderation';
import { rpcGetStats } from './rpc_stats';

export const guardedDesignerState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcDesignerState, ctx, logger, nk, payload);
export const guardedSetAgeBracket: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSetAgeBracket, ctx, logger, nk, payload);
export const guardedUploadCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcUploadCardArt, ctx, logger, nk, payload);
export const guardedClearDeckPart: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClearDeckPart, ctx, logger, nk, payload);
export const guardedSetPublicDeck: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSetPublicDeck, ctx, logger, nk, payload);
export const guardedSelectDeck: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSelectDeck, ctx, logger, nk, payload);
export const guardedGetCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcGetCardArt, ctx, logger, nk, payload);
export const guardedReportCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcReportCardArt, ctx, logger, nk, payload);
export const guardedModerationQueue: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcModerationQueue, ctx, logger, nk, payload);
export const guardedModerateCardArt: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcModerateCardArt, ctx, logger, nk, payload);
export const guardedGetStats: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcGetStats, ctx, logger, nk, payload);
