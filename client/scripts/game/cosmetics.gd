class_name Cosmetics
## Free cosmetic track catalog: card backs and table felts. Ids must match
## server/src/match/cosmetics.ts. The current selections are static so
## CardView, the table and the lobby read them without any wiring.

const CARD_BACKS := [
	{"id": "back_classic", "name": "Classic", "ink": Color("#1C1C1C"), "accent": Color("#FFFDF6")},
	{"id": "back_midnight", "name": "Midnight", "ink": Color("#EAE6DA"), "accent": Color("#1E2233")},
	{"id": "back_sunrise", "name": "Sunrise", "ink": Color("#1C1C1C"), "accent": Color("#F2C230")},
	{"id": "back_pinstripe", "name": "Pinstripe", "ink": Color("#1C1C1C"), "accent": Color("#2E6FD8")},
]

## WHY: the felts stay pale tints (not true navy or burgundy) because every
## label on the table is ink-on-felt; a dark felt would need a second text
## palette. The names promise a mood, the colours keep the text readable.
const TABLES := [
	{"id": "table_green", "name": "Board green", "bg": Color("#C7DFC9"), "edge": Color("#9BBE9F")},
	{"id": "table_navy", "name": "Navy felt", "bg": Color("#C3D1E6"), "edge": Color("#8AA0C2")},
	{"id": "table_burgundy", "name": "Burgundy felt", "bg": Color("#E6C7CB"), "edge": Color("#BD8F96")},
]

const DEFAULT_CARD_BACK := "back_classic"
const DEFAULT_TABLE := "table_green"

## Current selections, applied from the profile and by the picker.
static var card_back := DEFAULT_CARD_BACK
static var table := DEFAULT_TABLE


static func table_bg_color() -> Color:
	return _table_entry(table)["bg"]


static func table_edge_color() -> Color:
	return _table_entry(table)["edge"]


static func card_back_entry(id: String = card_back) -> Dictionary:
	for e in CARD_BACKS:
		if e["id"] == id:
			return e
	return CARD_BACKS[0]


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
