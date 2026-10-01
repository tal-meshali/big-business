/**
 * Heuristic bot for real games (rules-spec section 8). Timeouts and the
 * tutorial keep using the simple `autoAction` in auto.ts.
 *
 * The bot decides from the acting seat's PlayerView only: its own hand, every
 * portfolio, the Market and its coins, coin counts, hand counts, the Supply
 * count and the turn number. It never sees other hands, the Supply order or
 * the removed cards.
 *
 * How it decides: for every company it estimates the dividend value of
 * holding k shares at game end (3 per share owed to it as majority holder,
 * minus 1 per share it owes as a minority holder), from a probability model
 * of each opponent's final count. Every legal action is scored as coins after
 * the action plus the value of the resulting holdings; a take is scored with
 * the best play that could follow it (a draw averages over the unseen
 * shares). The best score wins, with a little noise between near-equal ones.
 * Keeping a share of any company it holds a pair of scores PAIR_BONUS higher,
 * and a bot that has kept on fewer than KEEP_PACE of its turns favours
 * keeping its focus company, so its Portfolio grows the way a player's would.
 *
 * Written for Nakama's goja runtime: ES2016 features only.
 */
import { COMPANIES, COMPANY_COUNT, GOLD_VALUE, HAND_SIZE, REMOVED_SHARES, TOTAL_SHARES, type CompanyId } from './companies';
import { RulesError } from './game';
import { playerView } from './view';
import type { Action, Card, GameState, PlayerView } from './types';

// Tuning constants, measured in simulation against autoAction (see bot.test.ts).

/**
 * Shares of a company expected to change hands in the rest of the game,
 * relative to its expected Supply share plus its Market shares. Above 1
 * because shares sold to the Market come back into play.
 */
const FUTURE_FLOW = 1.2;
/** Negative-binomial dispersion of an opponent's future gains (smaller = more spread). */
const FUTURE_DISPERSION = 0.5;
/**
 * At tables of SMALL_TABLE seats or fewer, fewer shares are expected to
 * change hands and an opponent's future gains are more spread out.
 */
const SMALL_TABLE = 4;
const SMALL_FUTURE_FLOW = 0.8;
const SMALL_FUTURE_DISPERSION = 0.25;
/** Correlation between the shares in one hidden hand (players keep pairs). */
const HAND_RHO = 0.5;
/** Uniform noise added to each action's score, in points. */
const NOISE = 0.1;
/** Terms kept in the future-gain distributions. */
const MAX_TERMS = 8;
/** Market takes beyond STALL_RATIO * draws + STALL_SLACK count as a stall. */
const STALL_RATIO = 3;
const STALL_SLACK = 15;
/** Fewest Keeps per turn played before the bot commits its focus company. */
const KEEP_PACE = 0.3;
/** Bonus, in points, for keeping a focus-company share while behind KEEP_PACE. */
const COMMIT_BONUS = 1;
/** Bonus, in points, for keeping a share of a company held at least twice (Portfolio + hand). */
const PAIR_BONUS = 0.75;

/**
 * Choose an action for the active seat. Deterministic for a given state and
 * rng sequence.
 */
export function botAction(state: GameState, rng: () => number): Action {
  // WHY: the decision is built from playerView, the same filtered data a
  // client receives, so the bot cannot use hidden information by accident.
  return botActionFromView(playerView(state, state.active), rng);
}

/** Decide from the acting seat's PlayerView. */
export function botActionFromView(view: PlayerView, rng: () => number): Action {
  const legal = view.legal;
  if (legal.length === 0) throw new RulesError('no legal action');
  if (legal.length === 1) return legal[0] as Action;
  const model = buildModel(view);
  const hand = handOf(view);
  const stalled = isStalled(view);
  const commit = behindKeepPace(view) ? COMMIT_BONUS : 0;

  const scored: Scored[] = [];
  if (view.phase === 'take') {
    const bronze = (view.seats[model.me] as { bronze: number }).bronze;
    for (const action of legal) {
      if (action.type === 'take_supply') {
        // WHY: when the table keeps cycling Market shares instead of drawing,
        // draw so the Supply (and the game) always runs out.
        if (stalled) return action;
        let ev = 0;
        for (let c = 0; c < COMPANY_COUNT; c++) {
          const p = model.unseenTotal > 0 ? (model.unseen[c] as number) / model.unseenTotal : 0;
          if (p <= 0) continue;
          const counts = model.mine.slice();
          counts[c] = (counts[c] as number) + 1;
          ev += p * bestPlay(model, hand.concat([{ id: -1, company: c as CompanyId }]), counts, c, false, commit, null);
        }
        const cost = view.drawCost === null ? 0 : view.drawCost;
        scored.push({ action, value: bronze - cost + ev });
      } else if (action.type === 'take_market') {
        let slot: { card: Card; coins: number } | null = null;
        for (const s of view.market) if (s.card.id === action.cardId) slot = s;
        if (!slot) continue;
        const counts = model.mine.slice();
        counts[slot.card.company] = (counts[slot.card.company] as number) + 1;
        const v = bestPlay(model, hand.concat([slot.card]), counts, slot.card.company, false, commit, null);
        scored.push({ action, value: bronze + slot.coins + v });
      }
    }
  } else {
    const took = view.tookCompany === null ? -1 : view.tookCompany;
    // WHY: while stalled, keep the Market from growing so a draw becomes affordable.
    bestPlay(model, hand, model.mine.slice(), took, stalled, commit, scored);
  }

  let best: Scored | null = null;
  let bestValue = -Infinity;
  for (const s of scored) {
    const v = s.value + NOISE * rng();
    if (v > bestValue) {
      bestValue = v;
      best = s;
    }
  }
  return best ? best.action : (legal[0] as Action);
}

// ---------------------------------------------------------------------------
// Model of what the seat can see
// ---------------------------------------------------------------------------

interface Model {
  n: number;
  me: number;
  /** Portfolio counts [seat][company]. */
  port: number[][];
  handCount: number[];
  /** My holdings (portfolio + hand) per company. */
  mine: number[];
  /** Shares not visible to me per company (Supply, removed, other hands). */
  unseen: number[];
  unseenTotal: number;
  /** Market shares per company. */
  market: number[];
  supply: number;
  /**
   * Dividend value by holding k, per company: [company][k]. `own` includes
   * my expected future gains (used for my focus company), `plain` does not.
   */
  own: number[][];
  plain: number[][];
}

interface Scored {
  action: Action;
  value: number;
}

function zeros(n: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < n; i++) out.push(0);
  return out;
}

function handOf(view: PlayerView): Card[] {
  const seat = view.seats[view.you as number];
  return seat && seat.hand ? seat.hand.slice() : [];
}

function buildModel(view: PlayerView): Model {
  const n = view.seats.length;
  const me = view.you as number;
  const port: number[][] = [];
  const handCount: number[] = [];
  const mine = zeros(COMPANY_COUNT);
  const seen = zeros(COMPANY_COUNT);
  const market = zeros(COMPANY_COUNT);
  for (let i = 0; i < n; i++) {
    const row = zeros(COMPANY_COUNT);
    const sv = view.seats[i];
    if (sv) {
      for (const c of sv.portfolio) row[c.company] = (row[c.company] as number) + 1;
    }
    for (let c = 0; c < COMPANY_COUNT; c++) seen[c] = (seen[c] as number) + (row[c] as number);
    port.push(row);
    handCount.push(sv ? sv.handCount : 0);
  }
  for (let c = 0; c < COMPANY_COUNT; c++) mine[c] = (port[me] as number[])[c] as number;
  for (const c of handOf(view)) {
    mine[c.company] = (mine[c.company] as number) + 1;
    seen[c.company] = (seen[c.company] as number) + 1;
  }
  for (const slot of view.market) {
    market[slot.card.company] = (market[slot.card.company] as number) + 1;
    seen[slot.card.company] = (seen[slot.card.company] as number) + 1;
  }
  const unseen = zeros(COMPANY_COUNT);
  let unseenTotal = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const company = COMPANIES[c];
    const u = Math.max(0, (company ? company.shares : 0) - (seen[c] as number));
    unseen[c] = u;
    unseenTotal += u;
  }
  const model: Model = { n, me, port, handCount, mine, unseen, unseenTotal, market, supply: view.supplyCount, own: [], plain: [] };
  for (let c = 0; c < COMPANY_COUNT; c++) {
    // A take can add one share of a company to my holdings.
    const maxK = (mine[c] as number) + 1;
    model.own.push(companyTable(model, c, maxK, true));
    model.plain.push(companyTable(model, c, maxK, false));
  }
  return model;
}

/**
 * True when Market takes far outnumber draws so far. Uses only public
 * counters: the turn number and the Supply count.
 */
function isStalled(view: PlayerView): boolean {
  const initialSupply = TOTAL_SHARES - REMOVED_SHARES - view.seats.length * HAND_SIZE;
  const draws = initialSupply - view.supplyCount;
  const takes = view.turn - 1 - draws;
  return takes > STALL_RATIO * draws + STALL_SLACK;
}

/**
 * True when the bot has kept fewer than KEEP_PACE of its turns so far. Its
 * Portfolio only grows by Keeps, so this uses public data only: its
 * Portfolio size and the turn number.
 */
function behindKeepPace(view: PlayerView): boolean {
  const me = view.you as number;
  const seat = view.seats[me];
  if (!seat) return false;
  const turnsPlayed = Math.floor((view.turn - 1 - me) / view.seats.length) + 1;
  return seat.portfolio.length < Math.floor(KEEP_PACE * turnsPlayed);
}

// ---------------------------------------------------------------------------
// Distributions
// ---------------------------------------------------------------------------

/** Binomial(k, p) as a probability array of length k + 1. */
function binomial(k: number, p: number): number[] {
  let out: number[] = [1];
  for (let t = 0; t < k; t++) {
    const next = zeros(out.length + 1);
    for (let j = 0; j < out.length; j++) {
      const v = out[j] as number;
      next[j] = (next[j] as number) + v * (1 - p);
      next[j + 1] = (next[j + 1] as number) + v * p;
    }
    out = next;
  }
  return out;
}

/**
 * Beta-binomial(k, mean p, intra-hand correlation rho) as a probability
 * array of length k + 1.
 */
function betaBinomial(k: number, p: number, rho: number): number[] {
  if (rho <= 0 || p <= 0 || p >= 1) return binomial(k, p);
  const scale = 1 / rho - 1;
  const a = p * scale;
  const b = (1 - p) * scale;
  const out: number[] = [];
  let sum = 0;
  for (let x = 0; x <= k; x++) {
    // C(k, x) * a^(x rising) * b^(k-x rising) / (a+b)^(k rising)
    let v = 1;
    for (let i = 0; i < x; i++) v *= ((a + i) * (k - i)) / (i + 1);
    for (let j = 0; j < k - x; j++) v *= b + j;
    for (let t = 0; t < k; t++) v /= a + b + t;
    out.push(v);
    sum += v;
  }
  for (let x = 0; x <= k; x++) out[x] = (out[x] as number) / sum;
  return out;
}

/** Truncated Poisson(mean); the tail mass is folded into the last term. */
function poisson(mean: number): number[] {
  const out: number[] = [];
  let term = Math.exp(-mean);
  let sum = 0;
  for (let k = 0; k < MAX_TERMS; k++) {
    if (k > 0) term = (term * mean) / k;
    out.push(term);
    sum += term;
  }
  out[MAX_TERMS - 1] = (out[MAX_TERMS - 1] as number) + Math.max(0, 1 - sum);
  return out;
}

/** Truncated negative binomial with the given mean and dispersion r. */
function negBinomial(mean: number, r: number): number[] {
  if (mean <= 0) return poisson(0);
  const out: number[] = [];
  const p = mean / (r + mean);
  let term = Math.pow(r / (r + mean), r);
  let sum = 0;
  for (let k = 0; k < MAX_TERMS; k++) {
    if (k > 0) term = (term * (k + r - 1) * p) / k;
    out.push(term);
    sum += term;
  }
  out[MAX_TERMS - 1] = (out[MAX_TERMS - 1] as number) + Math.max(0, 1 - sum);
  return out;
}

function convolve(a: number[], b: number[]): number[] {
  const out = zeros(a.length + b.length - 1);
  for (let i = 0; i < a.length; i++) {
    const ai = a[i] as number;
    if (ai === 0) continue;
    for (let j = 0; j < b.length; j++) out[i + j] = (out[i + j] as number) + ai * (b[j] as number);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Company values
// ---------------------------------------------------------------------------

/**
 * Expected dividend value of company c for each holding k of mine (index k,
 * 0..maxK). An opponent's final count is portfolio + hidden hand + future
 * gains; mine is k, plus future gains when `ownFuture` is set.
 */
function companyTable(model: Model, c: number, maxK: number, ownFuture: boolean): number[] {
  const { n, me } = model;
  const q = model.unseenTotal > 0 ? (model.unseen[c] as number) / model.unseenTotal : 0;
  // WHY: at 3 and 4 seats the large-table model overrated opponents' future
  // gains, so the bot sold shares it could have won with and kept too few.
  // Expecting less and more uneven future flow there made bots keep more, hold
  // a simple stand-in for a person to fewer wins, and beat the large-table
  // model head to head (rules-spec section 8.2). At 5 or more seats it
  // measured slightly worse.
  const small = n <= SMALL_TABLE;
  const flow = (small ? SMALL_FUTURE_FLOW : FUTURE_FLOW) * (model.supply * q + (model.market[c] as number));
  // WHY: the bot only expects to keep growing its focus company. Crediting it
  // with future gains everywhere made stray singletons look like cheap
  // lottery tickets; in play they mostly ended as minority shares or ties.
  const myMean = ownFuture ? flow / n : 0;
  const oppMean = n > 1 ? (flow - myMean) / (n - 1) : 0;
  const future = negBinomial(oppMean, small ? SMALL_FUTURE_DISPERSION : FUTURE_DISPERSION);

  // Opponent final-count distributions (index = count) and P(F < k).
  const dists: number[][] = [];
  const byHandCount: number[][] = [];
  let size = maxK + MAX_TERMS + 1;
  for (let i = 0; i < n; i++) {
    if (i === me) continue;
    const hc = model.handCount[i] as number;
    let extra = byHandCount[hc];
    if (!extra) {
      // WHY: hidden hands are not random: players sell singletons and keep
      // pairs, so a beta-binomial (correlated shares) fits far better than
      // a binomial. Measured on 7-seat games, the binomial made holding 2
      // shares look twice as likely to win the majority as it really was.
      extra = convolve(betaBinomial(hc, q, HAND_RHO), future);
      byHandCount[hc] = extra;
    }
    const d = zeros((model.port[i] as number[])[c] as number).concat(extra);
    if (d.length > size) size = d.length;
    dists.push(d);
  }
  const below: number[][] = [];
  for (const d of dists) {
    while (d.length < size) d.push(0);
    const cdf: number[] = [];
    let acc = 0;
    for (let k = 0; k < size; k++) {
      cdf.push(acc);
      acc += d[k] as number;
    }
    cdf.push(acc);
    below.push(cdf);
  }
  const opp = dists.length;

  // P(some opponent is the unique leader with more than m shares), by m.
  const uniqueMax = zeros(size);
  for (let k = 1; k < size; k++) {
    let p = 0;
    for (let i = 0; i < opp; i++) {
      let term = (dists[i] as number[])[k] as number;
      for (let j = 0; j < opp && term > 0; j++) {
        if (j !== i) term *= (below[j] as number[])[k] as number;
      }
      p += term;
    }
    uniqueMax[k] = p;
  }
  const oppLeadsAbove = zeros(size + 1);
  for (let m = size - 1; m >= 0; m--) {
    oppLeadsAbove[m] = (oppLeadsAbove[m + 1] as number) + (m + 1 < size ? (uniqueMax[m + 1] as number) : 0);
  }

  // partial[i][m] = E[F_i * 1{F_i < m}]: what opponent i pays me when I lead with m.
  const partial: number[][] = [];
  for (let i = 0; i < opp; i++) {
    const d = dists[i] as number[];
    const row: number[] = [0];
    let acc = 0;
    for (let k = 0; k < size; k++) {
      acc += k * (d[k] as number);
      row.push(acc);
    }
    partial.push(row);
  }
  const received = (m: number): number => {
    if (m <= 0) return 0;
    const mm = Math.min(m, size);
    let total = 0;
    for (let i = 0; i < opp; i++) {
      let term = (partial[i] as number[])[mm] as number;
      for (let j = 0; j < opp && term > 0; j++) {
        if (j !== i) term *= (below[j] as number[])[mm] as number;
      }
      total += term;
    }
    return total;
  };

  const mine = poisson(myMean);
  const table: number[] = [];
  for (let k = 0; k <= maxK; k++) {
    let recv = 0;
    let pay = 0;
    for (let f = 0; f < mine.length; f++) {
      const pf = mine[f] as number;
      const m = k + f;
      recv += pf * received(m);
      if (m > 0 && m < size) pay += pf * m * (oppLeadsAbove[m] as number);
    }
    table.push(GOLD_VALUE * recv - pay);
  }
  return table;
}

/** Focus company: the one I hold most of (ties: the larger company). */
function focusOf(counts: number[]): number {
  let best = 0;
  for (let c = 1; c < COMPANY_COUNT; c++) {
    if ((counts[c] as number) >= (counts[best] as number)) best = c;
  }
  return best;
}

/** Value of holding `counts` at game end. */
function holdingsValue(model: Model, counts: number[]): number {
  const focus = focusOf(counts);
  let v = 0;
  for (let c = 0; c < COMPANY_COUNT; c++) {
    const t = (c === focus ? model.own[c] : model.plain[c]) as number[];
    v += t[Math.max(0, Math.min(counts[c] as number, t.length - 1))] as number;
  }
  return v;
}

/**
 * Best play-step value for a 4-card hand. `counts` are my holdings with that
 * hand; `took` is the company taken this turn (it may not go to the Market).
 * Pushes every candidate into `collect` when given. `noSell` forbids Market
 * plays. `commit` is added to keeping a share of the focus company.
 */
function bestPlay(model: Model, hand: Card[], counts: number[], took: number, noSell: boolean, commit: number, collect: Scored[] | null): number {
  const keep = holdingsValue(model, counts);
  const focus = focusOf(counts);
  let best = -Infinity;
  for (const card of hand) {
    const c = card.company;
    const k = counts[c] as number;
    counts[c] = k - 1;
    const sold = holdingsValue(model, counts);
    counts[c] = k;
    // Portfolio keeps every share; among portfolio plays, commit the share
    // that is worth the most (a tiny tie-break) and keep doubtful ones in
    // hand, where they can still be sold later.
    // WHY: on value alone the bot kept its best shares in hand and cycled
    // Market shares for their coins (rules-spec section 9), so its Portfolio
    // barely grew: at 3 seats its longest run of sells averaged 12 turns and
    // a fifth of bots had at most one Portfolio share at mid-game, which
    // players read as bots never keeping. Committing the focus company when
    // behind KEEP_PACE halves those runs for 1 to 2 points a game.
    // WHY: even with the keep pace, bots sold on their first two or three
    // turns (only singletons looked worth a decision) and kept about a third
    // of their plays, which still read as "bots never keep". A player locks a
    // pair into the Portfolio; scoring that PAIR_BONUS higher makes bots keep
    // about half their plays from their first or second turn, and they score
    // no worse against the simple policy (rules-spec section 8.2).
    const pair = k >= 2 ? PAIR_BONUS : 0;
    const pv = keep + 0.01 * (keep - sold) + (c === focus ? commit : 0) + pair;
    if (collect) collect.push({ action: { type: 'play_portfolio', cardId: card.id }, value: pv });
    if (pv > best) best = pv;
    if (c === took || noSell) continue;
    // WHY: selling is scored on holdings alone. Charging each Market share its
    // expected future draw cost made the bot keep junk instead of selling it,
    // and lost to no charge at every table size.
    if (collect) collect.push({ action: { type: 'play_market', cardId: card.id }, value: sold });
    if (sold > best) best = sold;
  }
  return best;
}
