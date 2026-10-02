class_name ClubsApi
## Club RPCs (server/src/match/rpc_clubs.ts) for the Clubs panel. Like
## DesignerApi, every call answers {} when offline or refused, with the
## server's message in `last_error`.

## Must match CLUB_ADJECTIVES and CLUB_NOUNS in server/src/match/clubs.ts:
## a club name is picked from these words, never typed (decision D4).
const ADJECTIVES: Array[String] = [
	"Bold", "Bright", "Steady", "Swift", "Golden", "Silver", "Lucky", "Clever",
	"Brave", "Quiet", "Northern", "Southern", "Eastern", "Western", "Rising", "Grand",
]
const NOUNS: Array[String] = [
	"Ventures", "Holdings", "Partners", "Traders", "Capital", "Investors", "Founders", "Builders",
	"Brokers", "Owners", "Associates", "Collective", "Company", "Union", "Guild", "Exchange",
]

static var last_error: String = ""


static func _call(id: String, body: Dictionary) -> Dictionary:
	var res: Dictionary = await DesignerApi._call(id, body)
	last_error = DesignerApi.last_error
	return res


## {club: null | {id, name, crest, role, members: [{userId, name, role, week}], rank, score}, league: [...], max}.
static func state() -> Dictionary:
	return await _call("club_state", {})


## {clubs: [{id, name, crest, count, max}], cursor}.
static func list() -> Dictionary:
	return await _call("club_list", {})


static func create(adjective: int, noun: int, crest: int) -> Dictionary:
	return await _call("club_create", {"adjective": adjective, "noun": noun, "crest": crest})


static func join(club_id: String) -> Dictionary:
	return await _call("club_join", {"clubId": club_id})


static func leave() -> bool:
	return not (await _call("club_leave", {})).is_empty()


static func kick(user_id: String) -> bool:
	return not (await _call("club_kick", {"userId": user_id})).is_empty()
