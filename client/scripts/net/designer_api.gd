class_name DesignerApi
## Designer and Plus RPCs (server/src/match/rpc_designer.ts, rpc_stats.ts)
## for the Designer, shop and stats panels.
## Every call answers {} (or false) when offline or refused, with the
## server's message in `last_error`, so the panel can say what went wrong.

static var last_error: String = ""


static func _call(id: String, body: Dictionary) -> Dictionary:
	last_error = ""
	if Net.client == null or Net.session == null:
		last_error = "Not connected"
		return {}
	var rpc: NakamaAPI.ApiRpc = await Net.client.rpc_async(Net.session, id, JSON.stringify(body))
	if rpc.is_exception():
		last_error = clean_error(rpc.get_exception().message)
		return {}
	var data = JSON.parse_string(rpc.payload)
	return data if data is Dictionary else {}


## The server's own words from a refusal: "Error: x at reject (...)" -> "x".
static func clean_error(message: String) -> String:
	var m := message.trim_prefix("Error: ")
	var at := m.find(" at ")
	return m.substr(0, at) if at > 0 else m


## {enabled, owned, productId, slots, ageBracket, blocker, decks, active, templates}.
static func state() -> Dictionary:
	return await _call("designer_state", {})


## The neutral age answer: "under13", "13to15" or "16plus"; the region is
## the device's country, only to pick the right age of consent.
static func set_age(bracket: String) -> Dictionary:
	return await _call("set_age_bracket", {"bracket": bracket, "region": region()})


## Uploads a part rendered by CardArt.render and encoded by CardArt.encode:
## {hash, status} where status is "approved" or "pending".
static func upload(slot: int, part: String, webp: PackedByteArray) -> Dictionary:
	var res := await _call("upload_card_art", {"slot": slot, "part": part, "image": Marshalls.raw_to_base64(webp)})
	if res.has("hash"):
		CardArt.add_art(String(res["hash"]), Marshalls.raw_to_base64(webp))
	return res


static func clear_part(slot: int, part: String) -> bool:
	return not (await _call("clear_deck_part", {"slot": slot, "part": part})).is_empty()


## The deck shown in private rooms this player creates; -1 for none.
static func select_deck(slot: int) -> bool:
	return not (await _call("select_deck", {"slot": slot})).is_empty()


## Plus: also show the selected deck in quick play games.
static func set_public_deck(on: bool) -> bool:
	return not (await _call("set_public_deck", {"on": on})).is_empty()


## Lifetime stats: {plus: false, games, wins}, or with Plus the full
## breakdown (stats.ts on the server).
static func stats() -> Dictionary:
	return await _call("get_stats", {})


## Two-letter country from the OS locale ("en_US" -> "US"), or "".
static func region() -> String:
	var parts := OS.get_locale().split("_")
	return parts[1].substr(0, 2).to_upper() if parts.size() > 1 else ""
