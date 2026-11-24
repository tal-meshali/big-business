import { describe, expect, it } from 'vitest';
import { applyAction, autoAction, createGame, type GameState } from '../engine';
import { apply } from './actions';
import { awardProgress, settleGame, type SeatResult } from './awards';
import { loadProfile, saveProfile } from './profile';
import { DEFAULT_PARAMS, OP_EARNINGS, type EarningsMessage } from './protocol';
import type { MatchState } from './state';
import { ALICE, BOB, fakeNk, logger } from './test_support';
import { sendEarnings } from './views';
import { DEFAULT_XP_RATES, emptyProgress, levelForXp, xpForLevel, type Progress } from './progression';
import { dailyQuests, questView, type GameStats, type LogEntry } from './quests';

const t0 = Date.UTC(2026, 8, 28, 12); // Monday 2026-09-28

function stats(over: Partial<GameStats> = {}): GameStats {
  return { games: 1, wins: 0, marketTakes: 0, marketCoins: 0, tokensEnd: 0, goldEnd: 0, majorities: 0, withPeople: 1, humans: 3, rank: 2, ...over };
}

function seat(over: Partial<SeatResult> = {}): SeatResult {
  return { rank: 1, seats: 4, capital: 21, humans: 3, ...over };
}

describe('the earnings receipt', () => {
  it('pays capital times the rate plus the finishing XP, and says so line by line', () => {
    const { progress, earnings } = settleGame(emptyProgress(), seat(), null, DEFAULT_XP_RATES, t0);
    expect(earnings.lines).toEqual([
      { kind: 'capital', xp: 42 },
      { kind: 'finish', xp: 20 },
    ]);
    expect([earnings.capital, earnings.rate, earnings.botsOnly]).toEqual([21, 2, false]);
    expect(earnings.xp).toBe(62);
    expect([earnings.xpBefore, earnings.xpAfter]).toEqual([0, 62]);
    expect([earnings.levelBefore, earnings.levelAfter]).toEqual([1, 2]);
    expect(progress.xp).toBe(62);
    expect(progress.trackXp).toBe(62);
    expect([progress.gamesPlayed, progress.wins, progress.bestRank]).toEqual([1, 1, 1]);
    // Beat three players and won: 3 x 3 + 5.
    expect(earnings.seasonPoints).toBe(14);
  });

  it('adds up: the lines sum to the XP gained, whatever happens', () => {
    for (const capital of [0, 1, 7, 15, 30, 44]) {
      for (const humans of [1, 2, 5]) {
        const before = { ...emptyProgress(), xp: 690, level: levelForXp(690), trackXp: 300 };
        const { progress, earnings } = settleGame(before, seat({ capital, humans, rank: 2 }), stats({ wins: 1, marketTakes: 9, marketCoins: 9, tokensEnd: 2, goldEnd: 9, majorities: 3 }), DEFAULT_XP_RATES, t0);
        const sum = earnings.lines.reduce((n, l) => n + l.xp, 0);
        expect(sum).toBe(earnings.xp);
        expect(progress.xp - before.xp).toBe(earnings.xp);
        expect(progress.trackXp - before.trackXp).toBe(earnings.xp);
        expect(earnings.xpAfter).toBe(progress.xp);
        expect(earnings.levelAfter).toBe(progress.level);
      }
    }
  });

  it('pays half against only bots and earns no season points', () => {
    const { earnings } = settleGame(emptyProgress(), seat({ humans: 1 }), null, DEFAULT_XP_RATES, t0);
    expect(earnings.botsOnly).toBe(true);
    expect(earnings.rate).toBe(1);
    expect(earnings.lines).toEqual([
      { kind: 'capital', xp: 21 },
      { kind: 'finish', xp: 10 },
    ]);
    expect(earnings.seasonPoints).toBe(0);
  });

  it('collects the quests this game finished and lists them after the game lines', () => {
    const today = dailyQuests('2026-09-28');
    const big = stats({ wins: 1, marketTakes: 20, marketCoins: 30, tokensEnd: 3, goldEnd: 9, majorities: 3, rank: 1 });
    const { progress, earnings } = settleGame(emptyProgress(), seat(), big, DEFAULT_XP_RATES, t0);
    const questLines = earnings.lines.filter((l) => l.kind === 'quest');
    expect(questLines.length).toBeGreaterThan(0);
    expect(earnings.lines.slice(0, 2).map((l) => l.kind)).toEqual(['capital', 'finish']);
    for (const line of questLines) expect(typeof line.text).toBe('string');
    // Each finished daily is on the receipt with its own XP, and is now marked collected.
    const view = questView(progress.quests, t0);
    for (const row of view.daily) {
      const def = today.find((d) => d.id === row.id)!;
      if (row.claimed) expect(questLines.some((l) => l.text === def.text && l.xp === def.xp)).toBe(true);
      expect(row.claimable).toBe(false);
    }
    // Nothing left to collect when the next game ends.
    const second = settleGame(progress, seat(), stats(), DEFAULT_XP_RATES, t0 + 60_000);
    expect(second.earnings.lines.filter((l) => l.kind === 'quest').map((l) => l.text)).not.toContain(questLines[0]!.text);
  });

  it('gives no quest credit without game stats (tutorial, or a seat a bot finished)', () => {
    const { progress, earnings } = settleGame(emptyProgress(), seat(), null, DEFAULT_XP_RATES, t0);
    expect(earnings.quests).toEqual([]);
    expect(progress.quests.day).toBe('');
  });

  it('shows at most two open quests, each unfinished', () => {
    const { earnings } = settleGame(emptyProgress(), seat({ rank: 3 }), stats({ marketTakes: 1 }), DEFAULT_XP_RATES, t0);
    expect(earnings.quests.length).toBeLessThanOrEqual(2);
    for (const q of earnings.quests) expect(q.progress).toBeLessThan(q.target);
  });

  it('reports a level-up and a track cosmetic the game unlocked', () => {
    const before: Progress = { ...emptyProgress(), xp: xpForLevel(5) - 10, level: 4, trackXp: 350 };
    const { earnings } = settleGame(before, seat(), null, DEFAULT_XP_RATES, t0);
    expect([earnings.levelBefore, earnings.levelAfter]).toEqual([4, 5]);
    expect(earnings.unlocked).toEqual(['back_midnight']);
    const calm = settleGame({ ...before, trackXp: 400 }, seat({ capital: 0 }), null, DEFAULT_XP_RATES, t0);
    expect(calm.earnings.unlocked).toEqual([]);
  });

  it('follows the operator rates', () => {
    const { earnings } = settleGame(emptyProgress(), seat({ capital: 10 }), null, { base: 5, perCoin: 4 }, t0);
    expect(earnings.lines).toEqual([
      { kind: 'capital', xp: 40 },
      { kind: 'finish', xp: 5 },
    ]);
  });
});

/** A finished game: ALICE and BOB (and a bot when `withBot`), played out by the timeout policy. */
function endedMatch(over: { tutorial?: boolean; withBot?: boolean } = {}): MatchState {
  const seats = [
    { id: ALICE, name: 'Alice', isBot: false },
    { id: BOB, name: 'Bob', isBot: false },
    { id: 'bot:0', name: 'Ivy', isBot: true },
  ];
  let g: GameState = createGame(seats, 11, { stepSeconds: 0 });
  const log: LogEntry[] = [];
  let guard = 0;
  while (g.phase !== 'ended' && guard++ < 800) {
    const seat = g.active;
    const action = autoAction(g);
    const r = applyAction(g, seat, action);
    let coins = 0;
    for (const e of r.events) if (e.type === 'took_market') coins = e.coins;
    g = r.state;
    log.push({ seq: g.seq, seat, action, source: 'bot', coins });
  }
  expect(g.phase).toBe('ended');
  return {
    params: { ...DEFAULT_PARAMS, tutorial: !!over.tutorial },
    presences: { [ALICE]: { userId: ALICE } as nkruntime.Presence, [BOB]: { userId: BOB } as nkruntime.Presence },
    pendingJoins: {},
    lobby: [],
    seatByUser: { [ALICE]: 0, [BOB]: 1 },
    game: g,
    playStartsAt: 0,
    forfeited: {},
    lastActivity: 0,
    startsAt: 0,
    endedAt: 0,
    botActAt: 0,
    awarded: false,
    earnings: {},
    log,
  } as unknown as MatchState;
}

/** fakeNk plus the calls the awards step makes outside storage. */
function awardsNk() {
  const { nk, rows } = fakeNk();
  const board: Array<{ id: string; owner: string; score: number }> = [];
  Object.assign(nk, {
    leaderboardRecordWrite: (id: string, owner: string, _name: string, score: number) => { board.push({ id, owner, score }); },
    usersGetId: (ids: string[]) => ids.map((userId) => ({ userId, username: 'u', createTime: 0 })),
  });
  return { nk, rows, board };
}

function scoreOf(s: MatchState, userId: string): { rank: number; score: number } {
  const game = s.game as GameState;
  const seat = game.seats.findIndex((x) => x.id === userId);
  return (game.result as NonNullable<GameState['result']>).scores.find((x) => x.seat === seat) as { rank: number; score: number };
}

describe('awardProgress', () => {
  it('pays every seated person once, keeps their receipt and reports the write', () => {
    const { nk, board } = awardsNk();
    const s = endedMatch();
    expect(awardProgress(s, nk, logger)).toBe(true);
    expect(Object.keys(s.earnings).sort()).toEqual([ALICE, BOB].sort());
    for (const id of [ALICE, BOB]) {
      const e = s.earnings[id] as EarningsMessage;
      const mine = scoreOf(s, id);
      const saved = loadProfile(nk, id).progress;
      expect([e.rank, e.seats, e.capital, e.botsOnly, e.rate]).toEqual([mine.rank, 3, mine.score, false, 2]);
      expect(e.lines[0]).toEqual({ kind: 'capital', xp: mine.score * 2 });
      expect(e.lines[1]).toEqual({ kind: 'finish', xp: 20 });
      // The receipt is the saved profile, to the point.
      expect([saved.xp, saved.trackXp, saved.gamesPlayed]).toEqual([e.xpAfter, e.xp, 1]);
      expect(e.lines.reduce((n, l) => n + l.xp, 0)).toBe(e.xp);
    }
    expect(board.every((r) => r.id === 'season')).toBe(true);
    // A second call (the loop runs every tick) writes nothing more.
    expect(awardProgress(s, nk, logger)).toBe(false);
    expect(loadProfile(nk, ALICE).progress.gamesPlayed).toBe(1);
  });

  it('gives a forfeited seat nothing and counts the game as solo for the one who stayed', () => {
    const { nk } = awardsNk();
    const s = endedMatch();
    s.forfeited[BOB] = true;
    awardProgress(s, nk, logger);
    expect(s.earnings[BOB]).toBeUndefined();
    expect(loadProfile(nk, BOB).progress.xp).toBe(0);
    const e = s.earnings[ALICE] as EarningsMessage;
    expect([e.botsOnly, e.rate, e.seasonPoints, e.lines[1]?.xp]).toEqual([true, 1, 0, 10]);
  });

  it('records a seat a bot had to finish like a forfeit: no XP, win, season points or receipt', () => {
    const { nk, board, rows } = awardsNk();
    const s = endedMatch();
    ((s.game as GameState).seats.find((x) => x.id === BOB) as { isBot: boolean }).isBot = true;
    awardProgress(s, nk, logger);
    const bob = loadProfile(nk, BOB).progress;
    expect([bob.xp, bob.trackXp, bob.gamesPlayed, bob.wins, bob.streak]).toEqual([0, 0, 1, 0, 0]);
    expect(bob.quests.daily).toEqual({});
    expect(s.earnings[BOB]).toBeUndefined();
    // Nothing the bot did reaches the season table or the statistics.
    expect(board.filter((r) => r.owner === BOB)).toEqual([]);
    expect(Object.keys(rows).filter((k) => k.indexOf(BOB) >= 0 && k.indexOf('stats') >= 0)).toEqual([]);
    // The one who stayed still played with a person: full rate, season points.
    const e = s.earnings[ALICE] as EarningsMessage;
    expect([e.botsOnly, e.rate]).toEqual([false, 2]);
    expect(e.seasonPoints).toBeGreaterThan(0);
  });

  it('pays the tutorial at the solo rate with no quest credit', () => {
    const { nk } = awardsNk();
    const s = endedMatch({ tutorial: true });
    s.forfeited[BOB] = true;
    awardProgress(s, nk, logger);
    const e = s.earnings[ALICE] as EarningsMessage;
    expect(e.lines.map((l) => l.kind)).toEqual(['capital', 'finish']);
    expect(e.quests).toEqual([]);
    expect(loadProfile(nk, ALICE).progress.quests.daily).toEqual({});
  });

  it('keeps a claim that lands while the game is being settled', () => {
    const { nk } = awardsNk();
    const s = endedMatch();
    saveProfile(nk, ALICE, { ...loadProfile(nk, ALICE).progress, xp: 100, level: 2, trackXp: 100 });
    // A gift claim commits between the award's read and its write, once.
    const write = nk.storageWrite;
    let raced = false;
    (nk as { storageWrite: typeof nk.storageWrite }).storageWrite = (reqs) => {
      const first = reqs[0] as nkruntime.StorageWriteRequest;
      if (!raced && first.collection === 'profile' && first.userId === ALICE && first.version) {
        raced = true;
        const row = loadProfile(nk, ALICE);
        write([{ collection: 'profile', key: 'progress', userId: ALICE, value: { ...row.progress, xp: row.progress.xp + 15, trackXp: row.progress.trackXp + 15 }, permissionRead: 1, permissionWrite: 0 }]);
      }
      return write(reqs);
    };
    awardProgress(s, nk, logger);
    const e = s.earnings[ALICE] as EarningsMessage;
    expect(raced).toBe(true);
    expect(e.xpBefore).toBe(115);
    expect(loadProfile(nk, ALICE).progress.xp).toBe(115 + e.xp);
  });

  it('sends no receipt when the profile cannot be written', () => {
    const { nk } = awardsNk();
    const s = endedMatch();
    const write = nk.storageWrite;
    (nk as { storageWrite: typeof nk.storageWrite }).storageWrite = (reqs) => {
      if ((reqs[0] as nkruntime.StorageWriteRequest).userId === ALICE && (reqs[0] as nkruntime.StorageWriteRequest).collection === 'profile') throw new Error('storage down');
      return write(reqs);
    };
    expect(awardProgress(s, nk, logger)).toBe(true);
    expect(s.earnings[ALICE]).toBeUndefined();
    expect(s.earnings[BOB]).toBeDefined();
  });
});

describe('sendEarnings', () => {
  function sent() {
    const out: Array<{ op: number; data: EarningsMessage; to: string[] }> = [];
    const dispatcher = {
      broadcastMessage: (op: number, data: string, to: nkruntime.Presence[] | null) => { out.push({ op, data: JSON.parse(data), to: (to || []).map((p) => p.userId) }); },
    } as unknown as nkruntime.MatchDispatcher;
    return { out, dispatcher };
  }

  it('sends each present player their own receipt, and nobody else one', () => {
    const { nk } = awardsNk();
    const s = endedMatch();
    const WATCHER = '3f8fad5b-d9cb-469f-a165-70867728950e';
    s.presences[WATCHER] = { userId: WATCHER } as nkruntime.Presence;
    delete s.presences[BOB];
    awardProgress(s, nk, logger);
    const { out, dispatcher } = sent();
    sendEarnings(s, dispatcher);
    expect(out.map((m) => [m.op, m.to])).toEqual([[OP_EARNINGS, [ALICE]]]);
    expect(out[0]?.data).toEqual(s.earnings[ALICE]);
  });

  it('resends only to the player who came back', () => {
    const { nk } = awardsNk();
    const s = endedMatch();
    awardProgress(s, nk, logger);
    const { out, dispatcher } = sent();
    sendEarnings(s, dispatcher, [{ userId: BOB } as nkruntime.Presence]);
    expect(out.map((m) => m.to)).toEqual([[BOB]]);
    expect(out[0]?.data.xp).toBe((s.earnings[BOB] as EarningsMessage).xp);
  });
});

describe('a seat left to time out', () => {
  /** A game in play with ALICE to act, and a dispatcher that swallows everything. */
  function inPlay() {
    const s = endedMatch();
    s.game = createGame((s.game as GameState).seats.map((x) => ({ id: x.id, name: x.name, isBot: x.id.startsWith('bot:') })), 11, { stepSeconds: 0 });
    const dispatcher = { broadcastMessage: () => {}, matchLabelUpdate: () => {} } as unknown as nkruntime.MatchDispatcher;
    return { s, dispatcher };
  }

  function playUntil(s: MatchState, dispatcher: nkruntime.MatchDispatcher, done: (g: GameState) => boolean, source: (g: GameState) => 'player' | 'bot' | 'timeout'): void {
    let guard = 0;
    while (!done(s.game as GameState) && (s.game as GameState).phase !== 'ended' && guard++ < 400) {
      const g = s.game as GameState;
      apply(s, dispatcher, logger, g.active, autoAction(g), source(g));
    }
  }

  it('becomes a bot after three timeouts and a player again on the first turn they play', () => {
    const { s, dispatcher } = inPlay();
    const alice = () => (s.game as GameState).seats.find((x) => x.id === ALICE) as GameState['seats'][number];
    const aliceIdx = (s.game as GameState).seats.findIndex((x) => x.id === ALICE);
    // ALICE times out on every step; everyone else plays.
    playUntil(s, dispatcher, () => alice().isBot, (g) => (g.active === aliceIdx ? 'timeout' : 'player'));
    expect(alice().isBot).toBe(true);
    // The bot plays her seat until she plays a turn herself.
    playUntil(s, dispatcher, (g) => g.active === aliceIdx, () => 'bot');
    expect(apply(s, dispatcher, logger, aliceIdx, autoAction(s.game as GameState), 'player')).toBe(true);
    expect(alice().isBot).toBe(false);
    // The timeouts are forgotten once she finishes the turn (the play step).
    expect(apply(s, dispatcher, logger, aliceIdx, autoAction(s.game as GameState), 'player')).toBe(true);
    expect([alice().isBot, alice().autoMoves]).toEqual([false, 0]);
  });

  it('stays a bot after a forfeit, whatever arrives from the player', () => {
    const { s, dispatcher } = inPlay();
    const aliceIdx = (s.game as GameState).seats.findIndex((x) => x.id === ALICE);
    const alice = (s.game as GameState).seats[aliceIdx] as GameState['seats'][number];
    alice.isBot = true;
    s.forfeited[ALICE] = true;
    playUntil(s, dispatcher, (g) => g.active === aliceIdx, () => 'bot');
    apply(s, dispatcher, logger, aliceIdx, autoAction(s.game as GameState), 'player');
    expect(((s.game as GameState).seats[aliceIdx] as GameState['seats'][number]).isBot).toBe(true);
  });
});
