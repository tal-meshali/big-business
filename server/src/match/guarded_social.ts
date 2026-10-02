/**
 * Guarded wrappers for the club RPCs, registered by main.ts. Kept apart
 * from the other guarded_*.ts files so none nears the graph's god-node
 * limit (docs/conventions.md). Each is a named arrow for the reason given
 * in guarded_services.ts.
 */
import { guarded } from './input';
import { rpcClubCreate, rpcClubJoin, rpcClubKick, rpcClubLeave, rpcClubList, rpcClubState } from './rpc_clubs';

export const guardedClubState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubState, ctx, logger, nk, payload);
export const guardedClubList: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubList, ctx, logger, nk, payload);
export const guardedClubCreate: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubCreate, ctx, logger, nk, payload);
export const guardedClubJoin: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubJoin, ctx, logger, nk, payload);
export const guardedClubLeave: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubLeave, ctx, logger, nk, payload);
export const guardedClubKick: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcClubKick, ctx, logger, nk, payload);
