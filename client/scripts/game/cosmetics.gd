class_name Cosmetics
## Cosmetic catalog: card backs and table felts. Most come from the free
## quest track; entries with "paid": true are curated skins sold in the shop
## (server/src/match/store.ts), and "plus": true ones come with Plus.
## Ids must match server/src/match/cosmetics.ts.
## The current selections are static so CardView, the table and the lobby
## read them without any wiring.

const CARD_BACKS := [
	{"id": "back_classic", "name": "Classic", "ink": Color("#1C1C1C"), "accent": Color("#FFFDF6")},
	{"id": "back_midnight", "name": "Midnight", "ink": Color("#EAE6DA"), "accent": Color("#1E2233")},
	{"id": "back_sunrise", "name": "Sunrise", "ink": Color("#1C1C1C"), "accent": Color("#F2C230")},
	{"id": "back_pinstripe", "name": "Pinstripe", "ink": Color("#1C1C1C"), "accent": Color("#2E6FD8")},
	{"id": "back_gilded", "name": "Gilded", "ink": Color("#D9B44A"), "accent": Color("#1F3A2E"), "paid": true},
	{"id": "back_blueprint", "name": "Blueprint", "ink": Color("#F4F8FF"), "accent": Color("#1D4E89"), "paid": true},
	{"id": "back_ticker", "name": "Ticker", "ink": Color("#7CE0A3"), "accent": Color("#14231B"), "plus": true},
]

## WHY: the felts stay pale tints (not true navy or burgundy) because every
## label on the table is ink-on-felt; a dark felt would need a second text
## palette. The names promise a mood, the colours keep the text readable.
const TABLES := [
	{"id": "table_green", "name": "Board green", "bg": Color("#C7DFC9"), "edge": Color("#9BBE9F")},
	{"id": "table_navy", "name": "Navy felt", "bg": Color("#C3D1E6"), "edge": Color("#8AA0C2")},
	{"id": "table_burgundy", "name": "Burgundy felt", "bg": Color("#E6C7CB"), "edge": Color("#BD8F96")},
	{"id": "table_walnut", "name": "Walnut", "bg": Color("#E3D2BE"), "edge": Color("#A9845F"), "paid": true},
	{"id": "table_slate", "name": "Slate", "bg": Color("#D3D8DC"), "edge": Color("#8E989F"), "plus": true},
]

const DEFAULT_CARD_BACK := "back_classic"
const DEFAULT_TABLE := "table_green"

## Current selections, applied from the profile and by the picker.
static var card_back := DEFAULT_CARD_BACK
static var table := DEFAULT_TABLE
## A Plus host's skins for the room we are in ("" for our own), so every
## seat of their private room sees them.
static var room_card_back := ""
static var room_table := ""


## The card back the table draws: the room's when a Plus host set one.
static func shown_card_back() -> String:
	return room_card_back if is_card_back(room_card_back) else card_back


static func shown_table() -> String:
	return room_table if is_table(room_table) else table


static func table_bg_color() -> Color:
	return _table_entry(shown_table())["bg"]


static func table_edge_color() -> Color:
	return _table_entry(shown_table())["edge"]


## Sets or clears ("" for both) the room's host skins; unknown ids are ignored.
static func set_room_skins(back_id: String, table_id: String) -> void:
	room_card_back = back_id if is_card_back(back_id) else ""
	room_table = table_id if is_table(table_id) else ""


static func card_back_entry(id: String = card_back) -> Dictionary:
	for e in CARD_BACKS:
		if e["id"] == id:
			return e
	return CARD_BACKS[0]


## One colour that stands for a cosmetic in a list: a card back's face, a felt's cloth.
static func swatch_color(id: String) -> Color:
	if is_card_back(id):
		return card_back_entry(id)["accent"]
	return _table_entry(id)["bg"]


static func _table_entry(id: String) -> Dictionary:
	for e in TABLES:
		if e["id"] == id:
			return e
	return TABLES[0]


static func name_of(id: String) -> String:
	for e in CARD_BACKS:
		if e["id"] == id:
			return e["name"]
	for e in TABLES:
		if e["id"] == id:
			return e["name"]
	return id


## True for the curated skins sold in the shop (never on the quest track).
static func is_paid(id: String) -> bool:
	for e in CARD_BACKS + TABLES:
		if e["id"] == id:
			return bool(e.get("paid", false))
	return false


## True for the Plus collection (usable while Plus is active).
static func is_plus(id: String) -> bool:
	for e in CARD_BACKS + TABLES:
		if e["id"] == id:
			return bool(e.get("plus", false))
	return false


static func is_card_back(id: String) -> bool:
	for e in CARD_BACKS:
		if e["id"] == id:
			return true
	return false


static func is_table(id: String) -> bool:
	for e in TABLES:
		if e["id"] == id:
			return true
	return false


## Applies a server `equipped` dictionary; unknown ids are ignored.
static func apply_equipped(equipped: Dictionary) -> void:
	var back := String(equipped.get("cardBack", ""))
	if is_card_back(back):
		card_back = back
	var felt := String(equipped.get("table", ""))
	if is_table(felt):
		table = felt


## Sets one slot ("cardBack" or "table") when the id is valid. Returns success.
static func set_slot(slot: String, id: String) -> bool:
	if slot == "cardBack" and is_card_back(id):
		card_back = id
		return true
	if slot == "table" and is_table(id):
		table = id
		return true
	return false


static func reset() -> void:
	card_back = DEFAULT_CARD_BACK
	table = DEFAULT_TABLE
	room_card_back = ""
	room_table = ""
