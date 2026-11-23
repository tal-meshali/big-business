class_name Companies
## Company identities and the visual palette. Must match
## server/src/engine/companies.ts for ids, names and share counts.
##
## Look: "title deed" cards. Off-white card with a black border, a solid
## colour band naming the company, black text on the body, on a pale
## board-green table. Six saturated band colours, each paired with a
## distinct icon silhouette for colourblind players.

const DATA := [
	{"id": 0, "key": "solar", "name": "Sunny Side Solar", "short": "Solar", "shares": 5, "color": Color("#F2C230")},
	{"id": 1, "key": "foods", "name": "Pinecone Foods", "short": "Foods", "shares": 6, "color": Color("#3F9E4F")},
	{"id": 2, "key": "freight", "name": "Tidewater Freight", "short": "Freight", "shares": 7, "color": Color("#2E6FD8")},
	{"id": 3, "key": "robotics", "name": "Cogwheel Robotics", "short": "Robotics", "shares": 8, "color": Color("#F07A1E")},
	{"id": 4, "key": "air", "name": "Nimbus Air", "short": "Air", "shares": 9, "color": Color("#7B4FC6")},
	{"id": 5, "key": "motors", "name": "Redline Motors", "short": "Motors", "shares": 10, "color": Color("#D6262C")},
]

## Colours a custom company may use (Founder unlock), by the id the server
## stores (server/src/match/founder.ts COLORS). The first six are the
## standard companies' colours.
const PALETTE := {
	"yellow": Color("#F2C230"), "green": Color("#3F9E4F"), "blue": Color("#2E6FD8"),
	"orange": Color("#F07A1E"), "purple": Color("#7B4FC6"), "red": Color("#D6262C"),
	"teal": Color("#119C93"), "pink": Color("#DE4F98"), "navy": Color("#28367E"),
	"brown": Color("#8A5A2E"), "lime": Color("#9BC53D"), "slate": Color("#5B6779"),
}
const PALETTE_ORDER: Array[String] = ["yellow", "green", "blue", "orange", "purple", "red", "teal", "pink", "navy", "brown", "lime", "slate"]
## Light colours carry ink text on the band instead of white.
const INK_ON := ["yellow", "lime"]
## Drawn logos (CompanyLogos), in picker order; the first six are the
## standard companies' art. Must match founder.ts LOGOS.
const LOGOS: Array[String] = ["sun", "pine", "anchor", "gear", "cloud", "bolt", "rocket", "crown", "leaf", "diamond", "heart", "star", "chart", "flame", "key", "mountain", "cup", "globe"]
const DEFAULT_COLOR_IDS: Array[String] = ["yellow", "green", "blue", "orange", "purple", "red"]
const NAME_MAX := 18

## The host's custom companies in the current private room (Founder), one
## per company id: {name, color, logo, picture} or null for the standard
## company. Empty when the room uses the standard six.
static var room_companies: Array = []

## Board-green table, like the centre of a classic property board.
const TABLE_BG := Color("#C7DFC9")
const TABLE_EDGE := Color("#9BBE9F")
## Off-white card and panel faces.
const CARD_FACE := Color("#FFFDF6")
const PANEL := Color("#FFFFFF")
## Near-black ink for text and borders.
const INK := Color("#1C1C1C")
const INK_SOFT := Color("#5A5A5A")
## Coins.
const BRONZE := Color("#B8722E")
const GOLD := Color("#E2B23A")
## Accents borrowed from the two classic card-draw piles.
const CHANCE := Color("#F7941D")
const CHEST := Color("#4FA3D8")
const ALERT := Color("#D6262C")
const HIGHLIGHT := Color("#FFF1B8")


## The company as the current room shows it: the standard entry, with the
## host's custom name and colour over it when the room has them.
static func get_company(id: int) -> Dictionary:
	var custom := custom_of(id)
	if custom.is_empty():
		return DATA[id]
	var out: Dictionary = DATA[id].duplicate()
	out["name"] = custom["name"]
	out["short"] = short_of_name(custom["name"])
	out["color"] = PALETTE.get(custom["color"], DATA[id]["color"])
	return out


## The room's custom company `id` ({name, color, logo, picture}), or {} for
## the standard one. Honours the "show custom cards" setting.
static func custom_of(id: int) -> Dictionary:
	if room_companies.is_empty() or not CardArt.show_custom or id < 0 or id >= room_companies.size():
		return {}
	var c = room_companies[id]
	return c if c is Dictionary else {}


## Takes the OP_DECK `companies` list; anything malformed keeps the standard company.
static func set_room_companies(list) -> void:
	room_companies = []
	if not (list is Array) or list.size() != DATA.size():
		return
	var any := false
	for c in list:
		if c is Dictionary and c.get("name") is String and PALETTE.has(c.get("color")) and LOGOS.has(c.get("logo")):
			var pic = c.get("picture")
			room_companies.append({"name": String(c["name"]), "color": String(c["color"]), "logo": String(c["logo"]), "picture": pic if pic is String else ""})
			any = true
		else:
			room_companies.append(null)
	if not any:
		room_companies = []


static func clear_room_companies() -> void:
	room_companies = []


## Logo picture hashes the room uses, for fetching and reporting.
static func picture_hashes() -> Array[String]:
	var out: Array[String] = []
	for c in room_companies:
		if c is Dictionary and not String(c["picture"]).is_empty() and not out.has(c["picture"]):
			out.append(String(c["picture"]))
	return out


## The short band name for a typed company name: the whole name when it is
## short, else its first word (the band shrinks it further to fit).
static func short_of_name(full: String) -> String:
	if full.length() <= 10:
		return full
	var first := full.split(" ", false)
	return first[0] if first.size() > 0 else full


## The drawn logo id of company `id` in this room.
static func logo_of(id: int) -> String:
	var custom := custom_of(id)
	return String(custom["logo"]) if not custom.is_empty() else LOGOS[id]


## The approved logo picture of company `id` in this room, or null.
static func picture_of(id: int) -> Texture2D:
	var custom := custom_of(id)
	if custom.is_empty() or String(custom["picture"]).is_empty():
		return null
	return CardArt.texture(String(custom["picture"]))


## The colour id of company `id` in this room.
static func color_id_of(id: int) -> String:
	var custom := custom_of(id)
	return String(custom["color"]) if not custom.is_empty() else DEFAULT_COLOR_IDS[id]


## Ink or white for text on a band of palette colour `color_id`.
static func text_on(color_id: String) -> Color:
	return INK if INK_ON.has(color_id) else Color.WHITE


## The companies whose regulator token a seat holds, as ints.
## WHY: JSON numbers arrive as floats, and Array.has(int) never matches a float.
static func tokens_of(seat: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for t in seat.get("tokens", []):
		out.append(int(t))
	return out


static func color_of(id: int) -> Color:
	return get_company(id)["color"]


static func name_of(id: int) -> String:
	return get_company(id)["name"]


static func short_name_of(id: int) -> String:
	return get_company(id)["short"]


## White reads better on dark bands, ink on the light (yellow, lime) ones.
static func band_text_color(id: int) -> Color:
	return text_on(color_id_of(id))
