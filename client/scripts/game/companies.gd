class_name Companies
## Company identities and the visual palette. Must match
## server/src/engine/companies.ts for ids, names and share counts.
##
## Look: "title deed" cards. Off-white card with a black border, a solid
## colour band naming the company, black text on the body, on a pale
## board-green table. Six saturated band colours, each paired with a
## distinct icon silhouette for colourblind players.

const DATA := [
	{"id": 0, "key": "solar", "name": "Sunny Side Solar", "short": "Solar", "shares": 5, "color": Color("#F2C230"), "tint": Color("#FCEFC4")},
	{"id": 1, "key": "foods", "name": "Pinecone Foods", "short": "Foods", "shares": 6, "color": Color("#3F9E4F"), "tint": Color("#D9EEDC")},
	{"id": 2, "key": "freight", "name": "Tidewater Freight", "short": "Freight", "shares": 7, "color": Color("#2E6FD8"), "tint": Color("#DCE7F9")},
	{"id": 3, "key": "robotics", "name": "Cogwheel Robotics", "short": "Robotics", "shares": 8, "color": Color("#F07A1E"), "tint": Color("#FDE4D0")},
	{"id": 4, "key": "air", "name": "Nimbus Air", "short": "Air", "shares": 9, "color": Color("#7B4FC6"), "tint": Color("#E7DEF5")},
	{"id": 5, "key": "motors", "name": "Redline Motors", "short": "Motors", "shares": 10, "color": Color("#D6262C"), "tint": Color("#F8D9DA")},
]

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
## The design's tokens beyond the felt: the yellow "primary" button, the
## warm plate fill for the active seat, the season band, the dark room the
## table stands in, and the caption grey.
const PRIMARY := Color("#F2C230")
const PRIMARY_HOVER := Color("#F6CF52")
const PLATE_ON := Color("#FFF1C9")
const SEASON := Color("#7B4FC6")
const ROOM := Color("#22392E")
const ROOM_LIGHT := Color("#3E6450")
const ROOM_DARK := Color("#16261E")
const CAPTION := Color("#4A4A4A")


static func get_company(id: int) -> Dictionary:
	return DATA[id]


static func color_of(id: int) -> Color:
	return DATA[id]["color"]


static func name_of(id: int) -> String:
	return DATA[id]["name"]


static func short_name_of(id: int) -> String:
	return DATA[id]["short"]


## Pale version of the band colour, the art window's background.
static func tint_of(id: int) -> Color:
	return DATA[id]["tint"]


## White reads better on dark bands, ink on the yellow band.
static func band_text_color(id: int) -> Color:
	return INK if id == 0 else Color.WHITE
