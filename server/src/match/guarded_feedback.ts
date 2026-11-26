/**
 * Guarded wrappers for the feedback RPCs (feedback.ts), registered by
 * main.ts; named arrows for the reason given in guarded_services.ts.
 */
import { guarded } from './input';
import { rpcFeedbackDone, rpcFeedbackList, rpcSendFeedback } from './feedback';

export const guardedSendFeedback: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcSendFeedback, ctx, logger, nk, payload);
export const guardedFeedbackList: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcFeedbackList, ctx, logger, nk, payload);
export const guardedFeedbackDone: nkruntime.RpcFunction = (ctx, logger, nk, payload) => guarded(rpcFeedbackDone, ctx, logger, nk, payload);
