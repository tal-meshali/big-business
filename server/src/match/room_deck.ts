/**
 * The look a room shows: custom card art (Designer), the host's own
 * companies (Founder) and, in a Plus host's
 * private room, the host's card back and table felt for every seat ("the
 * host unlocks the table"). Chosen once when the game starts and sent to the
 * seats as OP_DECK, and again to anyone rejoining.
 *
 * WHY private rooms and the host by default (decision D5, research 05
 * section 4): players there chose to play together, it keeps the moderation
 * surface small, and quick play and the tutorial look the same for everyone.
 * Plus members may also opt their deck into quick play; there it only goes
 * to players who said they are 13 or older, and the client shows it only if
 * that player turned public custom cards on.
 */
import { availableCosmetics, dropUnavailable } from './cosmetics';
import { AGE_BRACKETS, deckHashes, deckManifest, STRIKES_TO_BAN } from './designer';
import { designerAccess, readArt, readDecks, readStanding } from './designer_store';
import { companiesManifest, pictureHashes } from './founder';
import { ownsFounder, readCompanies } from './founder_store';
import { loadProfile } from './profile';
import { OP_DECK, type DeckMessage } from './protocol';
import { readOwned } from './purchases';
import { readRemoteConfig } from './rpc_config';
import { send, type MatchState } from './state';

/** The player's active deck as a table shows it (approved art only), or null. */
function activeDeck(nk: nkruntime.Nakama, userId: string, needPublic: boolean): DeckMessage | null {
  if (!designerAccess(nk, userId).designer) return null;
  if (readStanding(nk, userId).standing.strikes >= STRIKES_TO_BAN) return null;
  const row = readDecks(nk, userId).row;
  if (needPublic && !row.public) return null;
  const deck = row.decks[row.active];
  if (!deck) return null;
  const arts = readArt(nk, deckHashes(deck));
  const shown = deckManifest(deck, (h) => !!arts[h] && arts[h].art.status === 'approved');
  return shown ? { owner: userId, back: shown.back, art: shown.art } : null;
}

/** The host's deck for a private room, or null for the standard cards. */
export function hostDeck(nk: nkruntime.Nakama, hostId: string): DeckMessage | null {
  if (!readRemoteConfig(nk).designerEnabled) return null;
  return activeDeck(nk, hostId, false);
}

/**
 * The host's custom companies for a private room (Founder), with only
 * approved logo pictures, or null for the standard companies.
 */
export function hostCompanies(nk: nkruntime.Nakama, hostId: string): DeckMessage['companies'] | null {
  if (!readRemoteConfig(nk).companiesEnabled || !ownsFounder(nk, hostId)) return null;
  if (readStanding(nk, hostId).standing.strikes >= STRIKES_TO_BAN) return null;
  const row = readCompanies(nk, hostId).row;
  const arts = readArt(nk, pictureHashes(row));
  return companiesManifest(row, (h) => !!arts[h] && arts[h].art.status === 'approved');
}

/**
 * A Plus host's equipped card back and felt, so every seat sees them
 * (only skins the host may still use), or null without Plus.
 */
export function hostSkins(nk: nkruntime.Nakama, hostId: string): { cardBack: string; table: string } | null {
  if (!designerAccess(nk, hostId).plus) return null;
  const p = loadProfile(nk, hostId).progress;
  return dropUnavailable(p.equipped, availableCosmetics(p.trackPoints, readOwned(nk, hostId).owned));
}

/** The first seated Plus member (seat order) who opted their deck into quick play. */
export function publicDeck(nk: nkruntime.Nakama, seatIds: ReadonlyArray<string>): DeckMessage | null {
  if (!readRemoteConfig(nk).designerEnabled) return null;
  for (const id of seatIds) {
    if (id.startsWith('bot:') || !designerAccess(nk, id).plus) continue;
    const deck = activeDeck(nk, id, true);
    if (deck) return { ...deck, public: true };
  }
  return null;
}

/**
 * Picks the room's look at game start. Never throws; on any failure the
 * room plays with the standard cards.
 */
export function chooseRoomDeck(s: MatchState, nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  const had = s.customDeck !== null;
  s.customDeck = null;
  try {
    pickRoomDeck(s, nk);
  } catch (e) {
    logger.warn('room look failed: %s', String(e));
  }
  // WHY: a rematch in the same room whose host switched the look off (or was
  // reset by a moderator) must not keep showing the last game's look.
  s.clearLook = had && s.customDeck === null;
}

function pickRoomDeck(s: MatchState, nk: nkruntime.Nakama): void {
  if (!s.game || s.params.tutorial) return;
  if (!s.params.isPrivate) {
    s.customDeck = publicDeck(nk, s.game.seats.map((seat) => seat.id));
    return;
  }
  const host = s.params.hostId;
  if (!host || s.seatByUser[host] === undefined) return;
  const deck = hostDeck(nk, host);
  const skins = hostSkins(nk, host);
  const companies = hostCompanies(nk, host);
  if (!deck && !skins && !companies) return;
  s.customDeck = { ...(deck || { owner: host, back: null, art: [null, null, null, null, null, null] }), ...(skins || {}), ...(companies ? { companies } : {}) };
}

/** True when this player said they are 13 or older (public custom decks). */
function oldEnoughForPublic(nk: nkruntime.Nakama, userId: string): boolean {
  return AGE_BRACKETS.indexOf(readStanding(nk, userId).standing.ageBracket) >= 1;
}

/** Sends the room's look, when there is one, to `to` (every seated presence when omitted). */
export function sendDeck(s: MatchState, nk: nkruntime.Nakama, dispatcher: nkruntime.MatchDispatcher, to?: nkruntime.Presence[]): void {
  const deck = s.customDeck;
  if (!deck) {
    // An empty look tells the seats to go back to the standard one.
    // A seat rejoining after that gets it too (the client may still hold the old look).
    if (to) {
      send(dispatcher, OP_DECK, {}, to);
    } else if (s.clearLook) {
      send(dispatcher, OP_DECK, {}, Object.keys(s.presences).map((id) => s.presences[id] as nkruntime.Presence));
      s.clearLook = false;
    }
    return;
  }
  let targets = to || Object.keys(s.presences).map((id) => s.presences[id] as nkruntime.Presence);
  if (deck.public) {
    targets = targets.filter((p) => {
      try {
        return oldEnoughForPublic(nk, p.userId);
      } catch (e) {
        return false;
      }
    });
  }
  if (targets.length > 0) send(dispatcher, OP_DECK, deck, targets);
}
