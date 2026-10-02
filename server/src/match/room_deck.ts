/**
 * The custom deck a private room shows: the host's selected Designer deck,
 * approved art only (designer.ts `deckManifest`). Read once when the game
 * starts and sent to every seat as OP_DECK, and again to anyone rejoining.
 *
 * WHY private rooms and the host only (decision D5, research 05 section 4):
 * players there chose to play together, it keeps the moderation surface
 * small, and quick play and the tutorial always look the same for everyone.
 */
import { deckHashes, deckManifest, STRIKES_TO_BAN } from './designer';
import { ownsDesigner, readArt, readDecks, readStanding } from './designer_store';
import { OP_DECK, type DeckMessage } from './protocol';
import { readRemoteConfig } from './rpc_config';
import { send, type MatchState } from './state';

/** The host's deck as the table should show it, or null for the standard cards. */
export function hostDeck(nk: nkruntime.Nakama, hostId: string): DeckMessage | null {
  if (!readRemoteConfig(nk).designerEnabled || !ownsDesigner(nk, hostId)) return null;
  if (readStanding(nk, hostId).standing.strikes >= STRIKES_TO_BAN) return null;
  const row = readDecks(nk, hostId).row;
  const deck = row.decks[row.active];
  if (!deck) return null;
  const arts = readArt(nk, deckHashes(deck));
  const shown = deckManifest(deck, (h) => !!arts[h] && arts[h].art.status === 'approved');
  return shown ? { owner: hostId, back: shown.back, art: shown.art } : null;
}

/**
 * Picks the room's deck at game start: private rooms whose host is seated.
 * Never throws; on any failure the room plays with the standard cards.
 */
export function chooseRoomDeck(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  s.customDeck = null;
  const host = s.params.hostId;
  if (!s.params.isPrivate || s.params.tutorial || !host || s.seatByUser[host] === undefined) return;
  try {
    s.customDeck = hostDeck(nk, host);
  } catch (e) {
    logger.warn('custom deck for %s failed: %s', host, String(e));
  }
}

/** Sends the room's custom deck, when there is one, to `to` (everyone when omitted). */
export function sendDeck(s: MatchState, dispatcher: nkruntime.MatchDispatcher, to?: nkruntime.Presence[]): void {
  if (s.customDeck) send(dispatcher, OP_DECK, s.customDeck, to);
}
