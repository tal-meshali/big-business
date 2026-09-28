class_name Protocol
## Opcodes shared with server/src/match/protocol.ts.

const OP_ACTION := 1
const OP_READY := 2
const OP_EMOTE := 3

const OP_VIEW := 10
const OP_EVENTS := 11
const OP_LOBBY := 12
const OP_ERROR := 13
const OP_EMOTE_SHOWN := 14

## Preset emotes and phrases: the only chat there is (all-ages decision D4).
## Ids must match EMOTE_IDS in server/src/match/protocol.ts.
## Icon emotes have no text: the client draws them (EmoteIcon), because no
## emoji font is bundled and the fallback font shows placeholder glyphs.
const EMOTES := [
	{"id": "wave", "text": "", "icon": true},
	{"id": "think", "text": "", "icon": true},
	{"id": "laugh", "text": "", "icon": true},
	{"id": "wow", "text": "", "icon": true},
	{"id": "cry", "text": "", "icon": true},
	{"id": "clap", "text": "", "icon": true},
	{"id": "hello", "text": "Hello!"},
	{"id": "good_move", "text": "Good move"},
	{"id": "oops", "text": "Oops"},
	{"id": "thanks", "text": "Thanks"},
	{"id": "gg", "text": "Good game"},
	{"id": "hurry_up", "text": "Your turn!"},
	{"id": "nice", "text": "Nice"},
	{"id": "no_way", "text": "No way!"},
]


static func emote_text(id: String) -> String:
	for e in EMOTES:
		if e["id"] == id:
			return e["text"]
	return ""


## True for the six drawn emotes; false for phrases and unknown ids.
static func is_icon(id: String) -> bool:
	for e in EMOTES:
		if e["id"] == id:
			return bool(e.get("icon", false))
	return false


## True for any known emote id (icon or phrase).
static func is_emote(id: String) -> bool:
	for e in EMOTES:
		if e["id"] == id:
			return true
	return false


static func take_supply() -> Dictionary:
	return {"type": "take_supply"}


static func take_market(card_id: int) -> Dictionary:
	return {"type": "take_market", "cardId": card_id}


static func play_portfolio(card_id: int) -> Dictionary:
	return {"type": "play_portfolio", "cardId": card_id}


static func play_market(card_id: int) -> Dictionary:
	return {"type": "play_market", "cardId": card_id}
