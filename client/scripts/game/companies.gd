class_name Companies
## Company identities. Must match server/src/engine/companies.ts.

const DATA := [
	{"id": 0, "key": "solar", "name": "Sunny Side Solar", "short": "Solar", "shares": 5, "color": Color("#F5C542")},
	{"id": 1, "key": "foods", "name": "Pinecone Foods", "short": "Foods", "shares": 6, "color": Color("#4CAF6A")},
	{"id": 2, "key": "freight", "name": "Tidewater Freight", "short": "Freight", "shares": 7, "color": Color("#3B82F6")},
	{"id": 3, "key": "robotics", "name": "Cogwheel Robotics", "short": "Robotics", "shares": 8, "color": Color("#F4813F")},
	{"id": 4, "key": "air", "name": "Nimbus Air", "short": "Air", "shares": 9, "color": Color("#8B5CF6")},
	{"id": 5, "key": "motors", "name": "Redline Motors", "short": "Motors", "shares": 10, "color": Color("#E5484D")},
]

const TABLE_BG := Color("#121826")
const CARD_FACE := Color("#F8F6F0")
const BRONZE := Color("#C8874A")
const GOLD := Color("#F2C14E")


static func get_company(id: int) -> Dictionary:
	return DATA[id]


static func color_of(id: int) -> Color:
	return DATA[id]["color"]


static func name_of(id: int) -> String:
	return DATA[id]["name"]


static func short_name_of(id: int) -> String:
	return DATA[id]["short"]
