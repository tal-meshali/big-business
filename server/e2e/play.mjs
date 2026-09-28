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

const OP_ACTION = 1, OP_READY = 2, OP_VIEW = 10, OP_EVENTS = 11, OP_LOBBY = 12, OP_ERROR = 13;
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
  const p = { name, client, session, socket, view: null, lobby: null, errors: [], events: [], matchId: null, userId: session.user_id };
  socket.onmatchdata = (m) => {
    const data = JSON.parse(m.data instanceof Uint8Array ? new TextDecoder().decode(m.data) : m.data);
    if (m.op_code === OP_VIEW) p.view = data;
    else if (m.op_code === OP_EVENTS) p.events.push(...data.events);
    else if (m.op_code === OP_LOBBY) p.lobby = data;
    else if (m.op_code === OP_ERROR) p.errors.push(data);
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
  const final = await playOut([solo]);
  log('quick play game ended; my rank', final.result.scores.find((s) => s.seat === final.you).rank);
  solo.socket.disconnect(true);
}

try {
  await testPrivateRoom();
  await testQuickPlay();
  log('E2E OK');
  process.exit(0);
} catch (e) {
  console.error(e);
  process.exit(1);
}
