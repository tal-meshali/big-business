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
const EMOTES := [
	{"id": "wave", "text": "👋"},
	{"id": "think", "text": "🤔"},
	{"id": "laugh", "text": "😄"},
	{"id": "wow", "text": "😮"},
	{"id": "cry", "text": "😢"},
	{"id": "clap", "text": "👏"},
	{"id": "hello", "text": "Hello!"},
	{"id": "good_move", "text": "Good move"},
	{"id": "oops", "text": "Oops"},
	{"id": "thanks", "text": "Thanks"},
	{"id": "gg", "text": "Good game"},
	{"id": "hurry_up", "text": "Your turn!"},
	{"id": "nice", "text": "Nice"},
	{"id": "no_way", "text": "No way!"},
]


const EMOJI_COUNT := 6


static func emote_text(id: String) -> String:
	for e in EMOTES:
		if e["id"] == id:
			return e["text"]
	return ""


## The first six presets are pictures; the rest are phrases.
static func is_emoji(id: String) -> bool:
	for i in EMOJI_COUNT:
		if EMOTES[i]["id"] == id:
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
