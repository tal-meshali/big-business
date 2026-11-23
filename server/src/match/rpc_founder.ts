/**
 * Founder RPCs for players: the Founder screen's state, saving or resetting
 * one company, its logo picture, switching the companies on for the rooms
 * the player hosts, and reporting a host's company names. founder.ts holds
 * the rules, founder_store.ts the storage; the operator's moderation RPCs
 * are in rpc_founder_moderation.ts.
 */
import { storeArt } from './art_upload';
import { LOGO_PART, LOGO_TEMPLATE, STRIKES_TO_BAN, uploadBlocker, type ArtStatus } from './designer';
import { readArt, readStanding } from './designer_store';
import { clashWith, cleanName, COLORS, COMPANY_SLOTS, emptyRow, LOGOS, nameProblem, normalizeCompany, pictureHashes, setCompany, type Company, type CompaniesRow } from './founder';
import { enqueueCompanies, ownsFounder, readCompanies, writeCompanies } from './founder_store';
import { isUserId, MATCH_ID_MAX, parseBody, readString, refuse, required, requireUser, type Body } from './input';
import { checkRate } from './ratelimit';
import { BLOCKER_TEXT } from './rpc_designer';
import { readRemoteConfig } from './rpc_config';
import { FOUNDER, UNLOCKS } from './store';

/** A logo upload: a 64 KB image in base64 plus a few fields. */
const UPLOAD_MAX_CHARS = 90_000;
const NOT_OWNED = 'Founder is not unlocked';

/** Why this player may not change their companies now, or ''. */
function editBlocker(nk: nkruntime.Nakama, userId: string): string {
  if (!readRemoteConfig(nk).companiesEnabled) return 'Custom companies are switched off';
  return ownsFounder(nk, userId) ? '' : NOT_OWNED;
}

/** The company index in `req`, or -1 when it is not one. */
function companyIndex(req: Body): number {
  const v = req['company'];
  return typeof v === 'number' && Math.floor(v) === v && v >= 0 && v < COMPANY_SLOTS ? v : -1;
}

function productId(): string {
  for (const u of UNLOCKS) if (u.id === FOUNDER) return u.productId;
  return '';
}

/** Writes the row; a row changed since it was read refuses as 'try again'. */
function saveRow(nk: nkruntime.Nakama, userId: string, row: CompaniesRow, version: string | null): void {
  let problem = '';
  try {
    writeCompanies(nk, userId, row, version);
  } catch (e) {
    problem = 'try again';
  }
  refuse(problem);
}

/** RPC founder_state: everything the Founder screen shows. */
export const rpcFounderState: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger; void payload;
  const userId = requireUser(ctx);
  const owned = ownsFounder(nk, userId);
  const standing = readStanding(nk, userId).standing;
  const row = readCompanies(nk, userId).row;
  const arts = readArt(nk, pictureHashes(row));
  const status = (h: string | null): ArtStatus | null => (h ? (arts[h] ? arts[h].art.status : 'rejected') : null);
  return JSON.stringify({
    enabled: readRemoteConfig(nk).companiesEnabled,
    owned,
    productId: productId(),
    ageBracket: standing.ageBracket,
    // Why a logo picture cannot be uploaded ('' when it can); drawn logos are always allowed.
    uploadBlocker: uploadBlocker(owned, standing),
    banned: standing.strikes >= STRIKES_TO_BAN,
    companies: owned ? row.companies.map((c) => (c ? { ...c, pictureStatus: status(c.picture) } : null)) : emptyRow().companies,
    active: owned && row.active,
    colors: COLORS,
    logos: LOGOS,
    logoTemplate: LOGO_TEMPLATE,
  });
};

/**
 * RPC save_company {company, name, color, logo} or {company, reset: true}:
 * sets one of the six companies, or puts the standard one back. The six at
 * the table must differ in name, colour and logo. A saved company keeps its
 * logo picture unless the request clears it with `picture: null`.
 */
export const rpcSaveCompany: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  refuse(editBlocker(nk, userId));
  const req = parseBody(payload);
  checkRate(nk, userId, 'save_company', Date.now());
  const i = companyIndex(req);
  refuse(i < 0 ? 'invalid company' : '');
  const current = readCompanies(nk, userId);
  let company: Company | null = null;
  if (req['reset'] !== true) {
    refuse(nameProblem(req['name']));
    const prev = current.row.companies[i];
    const keepPicture = req['picture'] === null ? null : prev ? prev.picture : null;
    company = normalizeCompany({ name: cleanName(req['name']), color: req['color'], logo: req['logo'], picture: keepPicture });
    required(company, 'invalid company');
    refuse(clashWith(current.row, i, company));
  }
  saveRow(nk, userId, setCompany(current.row, i, company), current.version);
  return JSON.stringify({ company });
};

/**
 * RPC upload_company_logo {company, image}: a logo picture for a company the
 * player already saved. `image` is a base64 WebP at the logo template size.
 * It shows to others only once approved; until then they see the drawn logo.
 * Returns {hash, status}.
 */
export const rpcUploadCompanyLogo: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const userId = requireUser(ctx);
  refuse(readRemoteConfig(nk).companiesEnabled ? '' : 'Custom companies are switched off');
  const req = parseBody(payload, UPLOAD_MAX_CHARS);
  const now = Date.now();
  checkRate(nk, userId, 'upload_company_logo', now);
  const blocker = uploadBlocker(ownsFounder(nk, userId), readStanding(nk, userId).standing);
  refuse(blocker === 'not_owned' ? NOT_OWNED : blocker ? BLOCKER_TEXT[blocker] || 'not allowed' : '');
  const i = companyIndex(req);
  refuse(i < 0 ? 'invalid company' : '');
  required(readCompanies(nk, userId).row.companies[i], 'save the company first');
  const { hash, status } = storeArt(nk, logger, ctx.env, userId, LOGO_PART, req['image'], now);
  const current = readCompanies(nk, userId);
  const prev = current.row.companies[i];
  required(prev, 'save the company first');
  saveRow(nk, userId, setCompany(current.row, i, { ...prev, picture: hash }), current.version);
  return JSON.stringify({ hash, status });
};

/** RPC set_companies_active {on}: show the companies in the private rooms this player hosts. */
export const rpcSetCompaniesActive: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  void logger;
  const userId = requireUser(ctx);
  const on = parseBody(payload)['on'] === true;
  if (on) refuse(editBlocker(nk, userId));
  const current = readCompanies(nk, userId);
  saveRow(nk, userId, { companies: current.row.companies, active: on }, current.version);
  return JSON.stringify({ active: on });
};

/**
 * RPC report_companies {userId, matchId?}: puts a host's company names in
 * front of a moderator. Logo pictures are reported through report_card_art
 * like any custom art.
 */
export const rpcReportCompanies: nkruntime.RpcFunction = (ctx, logger, nk, payload) => {
  const reporter = requireUser(ctx);
  const req = parseBody(payload);
  const owner = req['userId'];
  refuse(!isUserId(owner) || owner === reporter ? 'invalid user' : '');
  const matchId = readString(req, 'matchId', MATCH_ID_MAX);
  const now = Date.now();
  checkRate(nk, reporter, 'report_companies', now);
  const row = readCompanies(nk, owner as string).row;
  const names = row.companies.filter((c): c is Company => c !== null).map((c) => c.name);
  // Only names other players can see: switched on and still unlocked.
  if (names.length === 0 || !row.active || !ownsFounder(nk, owner as string)) return JSON.stringify({ ok: true });
  const reports = enqueueCompanies(nk, owner as string, names, now);
  logger.info('companies of %s reported by %s in %s (x%d)', owner, reporter, matchId || '-', reports);
  return JSON.stringify({ ok: true });
};
