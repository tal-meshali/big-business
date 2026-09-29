/** Relays preset emotes between seats with a per-player cooldown. */
import { MAX_EMOTE_BYTES } from './input';
import { EMOTE_COOLDOWN_MS, EMOTE_IDS, OP_EMOTE, OP_EMOTE_SHOWN } from './protocol';
import { send, type MatchState } from './state';

export function handleEmotes(
  state: MatchState,
  messages: nkruntime.MatchMessage[],
  nk: nkruntime.Nakama,
  dispatcher: nkruntime.MatchDispatcher,
  now: number,
): void {
  for (const m of messages) {
    if (m.opCode !== OP_EMOTE) continue;
    const seat = state.seatByUser[m.sender.userId];
    if (seat === undefined) continue;
    // WHY: the cooldown and size checks come before parsing so a flood of
    // emotes costs a map lookup per message, not a JSON.parse.
    const last = state.lastEmoteAt[m.sender.userId] || 0;
    if (now - last < EMOTE_COOLDOWN_MS) continue;
    if (!m.data || m.data.byteLength > MAX_EMOTE_BYTES) continue;
    let emote = '';
    try {
      const parsed = JSON.parse(nk.binaryToString(m.data)) as { emote?: unknown } | null;
      emote = parsed && typeof parsed === 'object' && typeof parsed.emote === 'string' ? parsed.emote : '';
    } catch (e) {
      continue;
    }
    if (EMOTE_IDS.indexOf(emote) < 0) continue;
    state.lastEmoteAt[m.sender.userId] = now;
    send(dispatcher, OP_EMOTE_SHOWN, { seat, emote });
  }
}
