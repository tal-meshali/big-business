/**
 * Device-token RPCs for "your turn" pushes. The token comes from the
 * Firebase Messaging plugin on the device (client/scripts/net/push_tokens.gd).
 */
import { parseBody, readString, reject, requireUser } from './input';
import { addToken, isPushToken, removeToken } from './push';
import { readTokens, writeTokens } from './push_sender';
import { checkRate } from './ratelimit';

/** RPC register_push_token {token, platform: "android" | "ios"}. */
export const rpcRegisterPushToken: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const req = parseBody(payload);
  const token = req['token'];
  const platform = readString(req, 'platform', 16);
  if (!isPushToken(token)) reject('invalid token');
  if (platform !== 'android' && platform !== 'ios') reject('invalid platform');
  checkRate(nk, userId, 'register_push_token', Date.now());
  writeTokens(nk, userId, addToken(readTokens(nk, userId), token, platform, Date.now()));
  return JSON.stringify({ ok: true });
};

/** RPC unregister_push_token {token}: the player turned notifications off on this device. */
export const rpcUnregisterPushToken: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const token = parseBody(payload)['token'];
  if (!isPushToken(token)) reject('invalid token');
  writeTokens(nk, userId, removeToken(readTokens(nk, userId), token));
  return JSON.stringify({ ok: true });
};
