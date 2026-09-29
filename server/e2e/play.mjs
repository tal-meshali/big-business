/**
 * End-to-end test against a running Nakama (see README). Drives real matches
 * through the public API with the Nakama JS client:
 *   1. private room: 3 humans, ready-up, random legal play until dividend day
 *   2. illegal action is rejected with OP_ERROR
 *   3. leave and rejoin mid-game restores a view
 *   4. quick play: 1 human, lobby wait, bots fill, game completes
 * Exit code 0 on success.
 */
import WebSocket from 'ws';
import { Client } from '@heroiclabs/nakama-js';

globalThis.WebSocket = WebSocket;

const HOST = process.env.NAKAMA_HOST || '127.0.0.1';
const PORT = process.env.NAKAMA_PORT || '7350';
const KEY = process.env.NAKAMA_KEY || 'defaultkey';

const OP_ACTION = 1, OP_READY = 2, OP_EMOTE = 3, OP_VIEW = 10, OP_EVENTS = 11, OP_LOBBY = 12, OP_ERROR = 13, OP_EMOTE_SHOWN = 14;
const STARTING_COINS = 10;

const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const fail = (msg) => { console.error('FAIL:', msg); process.exit(1); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let seed = 12345;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };

async function makePlayer(name) {
  const client = new Client(KEY, HOST, PORT, false);
  const session = await client.authenticateDevice(`e2e-${name}-${Date.now()}`, true, `${name}${Date.now() % 100000}`);
  const socket = client.createSocket(false, false);
  await socket.connect(session, true);
  const p = { name, client, session, socket, view: null, lobby: null, errors: [], events: [], emotes: [], matchId: null, userId: session.user_id };
  socket.onmatchdata = (m) => {
    const data = JSON.parse(m.data instanceof Uint8Array ? new TextDecoder().decode(m.data) : m.data);
    if (m.op_code === OP_VIEW) p.view = data;
    else if (m.op_code === OP_EVENTS) p.events.push(...data.events);
    else if (m.op_code === OP_LOBBY) p.lobby = data;
    else if (m.op_code === OP_ERROR) p.errors.push(data);
    else if (m.op_code === OP_EMOTE_SHOWN) p.emotes.push(data);
  };
  socket.ondisconnect = () => { p.disconnected = true; };
  return p;
}

async function rpc(p, id, payload) {
  const r = await p.client.rpc(p.session, id, payload || {});
  return typeof r.payload === 'string' ? JSON.parse(r.payload) : r.payload;
}

async function join(p, matchId) {
  await p.socket.joinMatch(matchId);
  p.matchId = matchId;
}

function send(p, op, obj) {
  return p.socket.sendMatchState(p.matchId, op, JSON.stringify(obj || {}));
}

function totalCoins(view) {
  let n = 0;
  for (const s of view.seats) n += s.bronze + s.gold;
  for (const m of view.market) n += m.coins;
  return n;
}

/** Play until the game ends. Each player acts when its view says it is active. */
async function playOut(players, { maxMs = 120000, onTurn } = {}) {
  const start = Date.now();
  let lastSeq = -1;
  while (Date.now() - start < maxMs) {
    let ended = null;
    for (const p of players) {
      const v = p.view;
      if (!v) continue;
      if (v.phase === 'ended') { ended = v; break; }
      if (v.you !== null && v.active === v.you && v.legal.length > 0 && v.seq !== p.actedSeq) {
        if (onTurn) await onTurn(p, v);
        const action = v.legal[Math.floor(rnd() * v.legal.length)];
        p.actedSeq = v.seq;
        await send(p, OP_ACTION, action);
      }
      if (v.seq !== lastSeq) {
        lastSeq = v.seq;
        if (totalCoins(v) !== v.seats.length * STARTING_COINS) fail(`coins not conserved at seq ${v.seq}`);
      }
    }
    if (ended) return ended;
    await sleep(60);
  }
  fail('game did not end in time');
}

async function testPrivateRoom() {
  log('--- private room: 3 humans');
  const [a, b, c] = await Promise.all([makePlayer('Alice'), makePlayer('Bob'), makePlayer('Cara')]);
  const created = await rpc(a, 'create_room', { stepSeconds: 5, maxSeats: 4 });
  if (!/^[A-Z2-9]{6}$/.test(created.code)) fail(`bad room code ${created.code}`);
  await join(a, created.matchId);
  const resolved = await rpc(b, 'join_room', { code: created.code.toLowerCase() });
  if (resolved.matchId !== created.matchId) fail('join_room resolved a different match');
  await join(b, resolved.matchId);
  await join(c, resolved.matchId);
  await sleep(600);
  if (!a.lobby || a.lobby.seats.length !== 3) fail(`lobby should list 3 seats, got ${JSON.stringify(a.lobby)}`);
  if (a.lobby.roomCode !== created.code) fail('lobby should carry the room code');

  await send(a, OP_READY); await send(b, OP_READY);
  await sleep(600);
  if (a.view) fail('game must not start until everyone is ready');
  await send(c, OP_READY);
  await sleep(800);
  if (!a.view || !b.view || !c.view) fail('all players should have a view after start');
  if (a.view.seats.length !== 3) fail('3 seats expected');
  if (a.view.seats.some((s) => s.isBot)) fail('no bots expected with 3 humans');
  // Hidden information: only own hand is visible.
  for (const p of [a, b, c]) {
    const v = p.view;
    v.seats.forEach((s, i) => {
      if (i === v.you && (!s.hand || s.hand.length !== 3)) fail('own hand missing');
      if (i !== v.you && s.hand) fail('other hand leaked');
      if (s.handCount !== 3) fail('handCount wrong');
    });
    if ('supply' in v || 'seed' in v) fail('secret state leaked');
  }

  // Illegal action: a non-active player tries to draw.
  const inactive = [a, b, c].find((p) => p.view.active !== p.view.you);
  await send(inactive, OP_ACTION, { type: 'take_supply' });
  await sleep(500);
  if (inactive.errors.length === 0) fail('illegal action should produce OP_ERROR');
  log('illegal action rejected:', inactive.errors[0].message);

  // Timeout: nobody acts for > 5s, the server auto-moves the active seat.
  const seqBefore = a.view.seq;
  await sleep(6500);
  if (a.view.seq === seqBefore) fail('server should auto-move after the step deadline');
  log('timeout auto-move observed, seq', seqBefore, '->', a.view.seq);

  // Emotes: valid ids relay to everyone, unknown ids are dropped, and a
  // second emote inside the cooldown is dropped.
  await send(a, OP_EMOTE, { emote: 'wave' });
  await send(a, OP_EMOTE, { emote: 'laugh' });
  await send(b, OP_EMOTE, { emote: 'not_an_emote' });
  await sleep(600);
  if (c.emotes.length !== 1 || c.emotes[0].emote !== 'wave' || c.emotes[0].seat !== a.view.you) fail(`emote relay wrong: ${JSON.stringify(c.emotes)}`);
  log('emote relayed with cooldown');

  // Report: files into the moderation queue; self-report rejected.
  const rep = await rpc(a, 'report_player', { userId: b.userId, reason: 'behaviour', matchId: a.matchId, note: 'e2e test report' });
  if (!rep.ok) fail('report_player should succeed');
  let selfRejected = false;
  try { await rpc(a, 'report_player', { userId: a.userId, reason: 'other' }); } catch (e) { selfRejected = true; }
  if (!selfRejected) fail('self report should be rejected');

  // Leave and rejoin mid-game.
  const leaver = b;
  await leaver.socket.leaveMatch(leaver.matchId);
  await sleep(400);
  const seatIdx = a.view.seats.findIndex((s) => s.id === leaver.userId);
  if (a.view.seats[seatIdx].connected) fail('left seat should show disconnected');
  await join(leaver, created.matchId);
  await sleep(600);
  if (!leaver.view || leaver.view.you !== seatIdx) fail('rejoin should restore the same seat');
  if (!a.view.seats[seatIdx].connected) fail('rejoined seat should show connected');
  log('rejoin restored seat', seatIdx);

  const final = await playOut([a, b, c]);
  log('private game ended after', final.turn, 'turns; scores', final.result.scores.map((s) => `${final.seats[s.seat].name}:${s.score}(#${s.rank})`).join(' '));
  if (final.result.companies.length !== 6) fail('6 company dividends expected');
  if (final.supplyCount !== 0) fail('supply should be empty at the end');
  for (const s of final.seats) if (!s.hand || s.hand.length !== 0) fail('hands should be merged into portfolios');
  if (!a.events.some((e) => e.type === 'game_ended')) fail('game_ended event missing');

  // Progression: XP and a season record for a game with humans.
  await sleep(800);
  const prof = await rpc(a, 'get_profile');
  if (prof.progress.gamesPlayed !== 1 || prof.progress.xp <= 0) fail(`profile not awarded: ${JSON.stringify(prof)}`);
  const winner = final.result.scores.find((s) => s.rank === 1);
  const winnerPlayer = [a, b, c].find((p) => p.userId === final.seats[winner.seat].id);
  const wp = await rpc(winnerPlayer, 'get_profile');
  if (wp.progress.wins !== 1 || wp.progress.bestRank !== 1) fail('winner should have a win');
  // Last place earns no season points, so a 3-seat game writes 2 records; the winner leads.
  const lb = await a.client.listLeaderboardRecords(a.session, 'season', [a.userId, b.userId, c.userId], 10);
  const mine = (lb.records || []).filter((r) => [a.userId, b.userId, c.userId].includes(r.owner_id));
  if (mine.length !== 2) fail(`season leaderboard should have 2 records for this game, got ${JSON.stringify(lb.records)}`);
  const top = mine.sort((x, y) => Number(y.score) - Number(x.score))[0];
  if (top.owner_id !== winnerPlayer.userId || Number(top.subscore) !== 1) fail('winner should lead the season records with a win');
  // The season resets at 00:00 UTC on the 1st (cron '0 0 1 * *'), so every record expires then.
  const now = new Date();
  const nextReset = Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1);
  for (const r of mine) {
    if (Date.parse(r.expiry_time || '') !== nextReset) {
      fail(`season record should expire at the monthly reset ${new Date(nextReset).toISOString()}, got ${r.expiry_time}`);
    }
  }
  log('progression: xp', prof.progress.xp, 'level', prof.progress.level, '; season records', lb.records.length, '; season resets', new Date(nextReset).toISOString());

  // Daily bonus: once per day, streak starts at 1.
  const d1 = await rpc(a, 'claim_daily');
  if (!d1.claimed || d1.progress.streak !== 1 || d1.xpAwarded !== 15) fail(`daily claim wrong: ${JSON.stringify(d1)}`);
  const d2 = await rpc(a, 'claim_daily');
  if (d2.claimed) fail('daily claim should be once per day');
  const prof2 = await rpc(a, 'get_profile');
  if (prof2.dailyAvailable) fail('dailyAvailable should be false after claiming');
  log('daily bonus claimed, streak', d1.progress.streak);
  for (const p of [a, b, c]) p.socket.disconnect(true);
}

async function testQuickPlay() {
  log('--- quick play: 1 human, bots fill after the lobby wait');
  const solo = await makePlayer('Solo');
  const t0 = Date.now();
  const { matchId } = await rpc(solo, 'quick_play');
  await join(solo, matchId);
  await sleep(1000); // match label indexing is asynchronous
  const again = await rpc(solo, 'quick_play');
  if (again.matchId !== matchId) fail('quick_play should return the open lobby, not create another');
  while (!solo.view && Date.now() - t0 < 40000) await sleep(250);
  if (!solo.view) fail('quick play game did not start');
  log('quick play started after', ((Date.now() - t0) / 1000).toFixed(1), 's with', solo.view.seats.length, 'seats,', solo.view.seats.filter((s) => s.isBot).length, 'bots');
  if (solo.view.seats.length < 3) fail('bots should fill to 3 seats');
  // WHY: two heuristic bots favour Market shares over drawing, so this game runs
  // about 70 turns (100 s of bot think time) against about 50 with the old policy.
  const final = await playOut([solo], { maxMs: 240000 });
  log('quick play game ended; my rank', final.result.scores.find((s) => s.seat === final.you).rank);
  solo.socket.disconnect(true);
}

async function testTutorial() {
  log('--- tutorial: solo, starts immediately, no timer, deterministic');
  const learner = await makePlayer('Learner');
  const t0 = Date.now();
  const created = await rpc(learner, 'quick_play', { tutorial: true });
  if (!created.tutorial) fail('quick_play {tutorial:true} should return a tutorial match');
  await join(learner, created.matchId);
  while (!learner.view && Date.now() - t0 < 8000) await sleep(100);
  if (!learner.view) fail('tutorial did not start');
  const v = learner.view;
  log('tutorial started after', ((Date.now() - t0) / 1000).toFixed(1), 's');
  if (Date.now() - t0 > 5000) fail('tutorial should start within a few seconds');
  if (v.seats.length !== 3 || v.seats.filter((s) => s.isBot).length !== 2) fail('tutorial needs 1 human + 2 bots');
  if (v.you !== 0 || v.active !== 0) fail('the learner should take the first turn');
  if (v.deadline !== 0) fail('tutorial must have no turn timer');
  // Deterministic: a second tutorial deals the same opening hand.
  const other = await makePlayer('Learner2');
  const created2 = await rpc(other, 'quick_play', { tutorial: true });
  await join(other, created2.matchId);
  while (!other.view && Date.now() - t0 < 12000) await sleep(100);
  if (JSON.stringify(other.view.seats[0].hand) !== JSON.stringify(v.seats[0].hand)) fail('tutorial seed should be fixed');
  // Public quick play must never land in a tutorial match.
  const pub = await rpc(learner, 'quick_play');
  if (pub.matchId === created.matchId || pub.matchId === created2.matchId) fail('public quick play joined a tutorial match');
  const final = await playOut([learner], { maxMs: 360000 }); // tutorial bots think slowly on purpose
  log('tutorial game ended after', final.turn, 'turns');
  learner.socket.disconnect(true);
  other.socket.disconnect(true);
}

try {
  await testPrivateRoom();
  await testQuickPlay();
  await testTutorial();
  log('E2E OK');
  process.exit(0);
} catch (e) {
  console.error(e);
  process.exit(1);
}
