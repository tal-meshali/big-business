import WebSocket from 'ws';
import { Client } from '@heroiclabs/nakama-js';
globalThis.WebSocket = WebSocket;
const OP_ACTION = 1, OP_VIEW = 10, OP_EVENTS = 11, OP_LOBBY = 12, OP_ERROR = 13;
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let fails = 0; const bad = (m) => { fails++; console.error('FAIL:', m); };
async function makePlayer(name) {
  const client = new Client('defaultkey', '127.0.0.1', '7350', false);
  const session = await client.authenticateDevice(`scr-${name}-${Date.now()}-${Math.random()}`, true, `${name}${Date.now() % 100000}`);
  const socket = client.createSocket(false, false);
  await socket.connect(session, true);
  const p = { name, client, session, socket, view: null, errors: [], events: [] };
  socket.onmatchdata = (m) => {
    const d = JSON.parse(m.data instanceof Uint8Array ? new TextDecoder().decode(m.data) : m.data);
    if (m.op_code === OP_VIEW) p.view = d; else if (m.op_code === OP_EVENTS) p.events.push(...d.events);
    else if (m.op_code === OP_ERROR) p.errors.push(d);
  };
  return p;
}
async function game(label, payload, expectSeats, playFull) {
  const p = await makePlayer('B' + label.replace(/\W/g, ''));
  const r = await p.client.rpc(p.session, 'quick_play', payload);
  const res = typeof r.payload === 'string' ? JSON.parse(r.payload) : r.payload;
  await p.socket.joinMatch(res.matchId); p.matchId = res.matchId;
  const t0 = Date.now();
  while (!p.view && Date.now() - t0 < 8000) await sleep(100);
  if (!p.view) { bad(`${label}: no view`); return; }
  const seats = p.view.seats.length, bots = p.view.seats.filter((s) => s.isBot).length;
  log(`${label}: payload=${JSON.stringify(payload)} seats=${seats} bots=${bots} names=${p.view.seats.map((s) => s.name).join('|')} you=${p.view.you}`);
  if (seats !== expectSeats || bots !== expectSeats - 1) bad(`${label}: expected ${expectSeats} seats`);
  if (!playFull) { p.socket.disconnect(true); return; }
  let acted = -1, maxSeq = 0; const start = Date.now();
  while (Date.now() - start < 540000) {
    const v = p.view;
    if (v.phase === 'ended') break;
    if (v.you !== null && v.active === v.you && v.legal.length && v.seq !== acted) {
      acted = v.seq; await p.socket.sendMatchState(p.matchId, OP_ACTION, JSON.stringify(v.legal[Math.floor(Math.random() * v.legal.length)]));
    }
    let coins = 0; for (const s of v.seats) coins += s.bronze + s.gold; for (const m of v.market) coins += m.coins;
    if (coins !== v.seats.length * 10) bad(`${label}: coins ${coins} at seq ${v.seq}`);
    await sleep(60);
  }
  const played = {}; for (const e of p.events) if (e.type === 'played') played[e.seat] = (played[e.seat] || 0) + 1;
  log(`${label}: phase=${p.view.phase} seq=${p.view.seq} plays per seat=${JSON.stringify(played)} errors=${p.errors.length} secs=${((Date.now() - start) / 1000).toFixed(0)}`);
  if (p.view.phase !== 'ended') bad(`${label}: did not end`); else log(`${label}: result`, JSON.stringify(p.view.result.scores));
  for (let s = 0; s < seats; s++) if (!played[s]) bad(`${label}: seat ${s} never played`);
  if (p.errors.length) bad(`${label}: errors ${JSON.stringify(p.errors)}`);
  p.socket.disconnect(true);
}
const full = process.argv[2] === 'full';
const cases = full
  ? [['2', { bots: true, botCount: 2 }, 3], ['3', { bots: true, botCount: 3 }, 4], ['4', { bots: true, botCount: 4 }, 5]]
  : [['missing', { bots: true }, 3], ['1', { bots: true, botCount: 1 }, 3], ['0', { bots: true, botCount: 0 }, 3], ['-5', { bots: true, botCount: -5 }, 3],
     ['9', { bots: true, botCount: 9 }, 5], ['3.7', { bots: true, botCount: 3.7 }, 4], ['"4"str', { bots: true, botCount: '4' }, 3], ['null', { bots: true, botCount: null }, 3],
     ['1e9', { bots: true, botCount: 1e9 }, 5], ['minSeats-inject', { bots: true, minSeats: 7 }, 3], ['2b', { bots: true, botCount: 2 }, 3], ['3b', { bots: true, botCount: 3 }, 4], ['4b', { bots: true, botCount: 4 }, 5]];
await Promise.all(cases.map(([l, pl, n]) => game(l, pl, n, full).catch((e) => bad(`${l}: ${e && (e.message || e.statusText || e)}`))));
log(fails ? `${fails} FAILURES` : 'ALL OK'); process.exit(fails ? 1 : 0);
