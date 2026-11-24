/**
 * Guarded wrappers for the Founder (custom companies) RPCs, registered by
 * main.ts as a namespace import. Each is a named arrow for the reason given
 * in guarded_services.ts.
 */
import { guarded } from './input';
import { rpcFounderState, rpcReportCompanies, rpcSaveCompany, rpcSetCompaniesActive, rpcUploadCompanyLogo } from './rpc_founder';
import { rpcCompanyQueue, rpcModerateCompanies } from './rpc_founder_moderation';

export const guardedFounderState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcFounderState, ctx, logger, nk, payload);
export const guardedSaveCompany: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSaveCompany, ctx, logger, nk, payload);
export const guardedUploadCompanyLogo: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcUploadCompanyLogo, ctx, logger, nk, payload);
export const guardedSetCompaniesActive: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSetCompaniesActive, ctx, logger, nk, payload);
export const guardedReportCompanies: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcReportCompanies, ctx, logger, nk, payload);
export const guardedCompanyQueue: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcCompanyQueue, ctx, logger, nk, payload);
export const guardedModerateCompanies: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcModerateCompanies, ctx, logger, nk, payload);
