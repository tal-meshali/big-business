class_name Protocol
## Opcodes shared with server/src/match/protocol.ts.

const OP_ACTION := 1
const OP_READY := 2

const OP_VIEW := 10
const OP_EVENTS := 11
const OP_LOBBY := 12
const OP_ERROR := 13


static func take_supply() -> Dictionary:
	return {"type": "take_supply"}


static func take_market(card_id: int) -> Dictionary:
	return {"type": "take_market", "cardId": card_id}


static func play_portfolio(card_id: int) -> Dictionary:
	return {"type": "play_portfolio", "cardId": card_id}


static func play_market(card_id: int) -> Dictionary:
	return {"type": "play_market", "cardId": card_id}
