/**
 * Moderation of custom company names, for the operator (server-to-server
 * with the runtime http_key, like moderate_card_art). Players report a
 * host's names with report_companies (rpc_founder.ts); a reset puts the six
 * standard companies back and gives a strike, which counts toward the same
 * STRIKES_TO_BAN as refused pictures.
 */
import { STRIKES_TO_BAN } from './designer';
import { readStanding, writeStanding } from './designer_store';
import { emptyRow } from './founder';
import { COMPANY_QUEUE_COLLECTION, dequeueCompanies, readCompanies, writeCompanies } from './founder_store';
import { isUserId, parseBody, readInt, readString, refuse, requireServer } from './input';
import { SYSTEM_USER } from './protocol';

/** RPC company_queue {limit?, cursor?}: reported company names, with the owner's current names. */
export const rpcCompanyQueue: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  requireServer(ctx);
  const req = parseBody(payload);
  const limit = readInt(req, 'limit', 1, 50, 20);
  const cursor = readString(req, 'cursor', 512);
  const page = nk.storageList(SYSTEM_USER, COMPANY_QUEUE_COLLECTION, limit, cursor || undefined);
  const items = (page.objects || []).map((o) => ({
    userId: o.key,
    ...(o.value as object),
    current: readCompanies(nk, o.key).row.companies.map((c) => (c ? c.name : null)),
  }));
  return JSON.stringify({ items, cursor: page.cursor || '' });
};

/** Adds one strike to `owner`; two decisions at once retry once on the newer row. */
function addStrike(nk: nkruntime.Nakama, owner: string): number {
  for (let attempt = 0; ; attempt++) {
    const s = readStanding(nk, owner);
    const strikes = s.standing.strikes + 1;
    try {
      writeStanding(nk, owner, { ...s.standing, strikes }, s.version);
      return strikes;
    } catch (e) {
      if (attempt >= 1) throw e;
    }
  }
}

/**
 * RPC moderate_companies {userId, verdict: "keep" | "reset", strike?, note?}:
 * "reset" puts all six standard companies back and, unless `strike` is
 * false, adds a strike (at STRIKES_TO_BAN the player's companies and decks
 * stop showing to others).
 */
export const rpcModerateCompanies: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  requireServer(ctx);
  const req = parseBody(payload);
  const owner = req['userId'];
  const verdict = req['verdict'];
  refuse(!isUserId(owner) ? 'invalid user' : verdict !== 'keep' && verdict !== 'reset' ? 'invalid verdict' : '');
  const userId = owner as string;
  let strikes = readStanding(nk, userId).standing.strikes;
  if (verdict === 'reset') {
    const current = readCompanies(nk, userId);
    writeCompanies(nk, userId, { companies: emptyRow().companies, active: current.row.active }, current.version);
    if (req['strike'] !== false) strikes = addStrike(nk, userId);
  }
  dequeueCompanies(nk, userId);
  logger.info('companies of %s: %s (%s); strikes %d', userId, verdict, readString(req, 'note', 200) || '-', strikes);
  return JSON.stringify({ userId, verdict, strikes, banned: strikes >= STRIKES_TO_BAN });
};
