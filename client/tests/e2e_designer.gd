extends SceneTree
## Headless end-to-end check of the Designer through the real client stack
## against a running Nakama at 127.0.0.1:7350: a picture rendered and encoded
## by CardArt must pass the server's checks, come back pending, and once the
## operator approves it, load through Net's art fetch into a texture.
## The unlock is seeded through the console API, as no store is configured.
## Run: godot --headless --path client --script res://tests/e2e_designer.gd

const CONSOLE := "http://127.0.0.1:7351"
const API := "http://127.0.0.1:7350"
const HTTP_KEY := "defaulthttpkey"


func _init() -> void:
	_run.call_deferred()


func _fail(msg: String) -> void:
	print("E2E DESIGNER FAILED: ", msg)
	quit(1)


func _http(url: String, method: HTTPClient.Method, body: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request(url, headers, method, body)
	var res: Array = await req.request_completed
	req.queue_free()
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"code": int(res[1]), "body": parsed if parsed != null else {}}


func _run() -> void:
	var net: Node = root.get_node("Net")
	net.host = "127.0.0.1"
	net.display_name = "GodotDesigner"
	if not await net.connect_to_server():
		_fail("could not connect")
		return
	var api = load("res://scripts/net/designer_api.gd")

	# The device id persists in user://, so a local re-run may find the unlock
	# already seeded; a fresh account must report it missing.
	var before: Dictionary = await api.state()
	if before.is_empty() or (not before.get("owned", false) and before.get("blocker") != "not_owned"):
		_fail("designer_state before the unlock: %s %s" % [before, api.last_error])
		return
	var auth := await _http(CONSOLE + "/v2/console/authenticate", HTTPClient.METHOD_POST, JSON.stringify({"username": "admin", "password": "password"}))
	var token := String(auth["body"].get("token", ""))
	var seed_body := JSON.stringify({"value": JSON.stringify({"owned": ["designer"], "syncedAt": 1}), "permission_read": 1, "permission_write": 0})
	var seeded := await _http("%s/v2/console/storage/purchases/owned/%s" % [CONSOLE, net.user_id], HTTPClient.METHOD_PUT, seed_body, PackedStringArray(["Authorization: Bearer " + token]))
	if seeded["code"] != 200:
		_fail("console seed answered %d" % seeded["code"])
		return
	if (await api.set_age("16plus")).get("blocker", "x") != "":
		_fail("age answer: %s" % api.last_error)
		return

	# A new picture every run, so it is never one an earlier run had approved.
	var salt := randi() % 1000
	var picture := Image.create(1024, 768, false, Image.FORMAT_RGBA8)
	for y in 768:
		for x in 1024:
			picture.set_pixel(x, y, Color(float(x) / 1024.0, float(y) / 768.0, float((x * y + salt) % 97) / 97.0))
	var results := {}
	for part in ["back", "c3"]:
		var bytes := CardArt.encode(CardArt.render(picture, part, 1.2, Vector2(0.45, 0.55)))
		var up: Dictionary = await api.upload(1, part, bytes)
		if String(up.get("status", "")) != "pending":
			_fail("upload %s (%d bytes): %s %s" % [part, bytes.size(), up, api.last_error])
			return
		results[part] = String(up["hash"])
	print("uploaded back and art window: ", results.values())

	for part in results:
		var verdict := await _http("%s/v2/rpc/moderate_card_art?http_key=%s&unwrap" % [API, HTTP_KEY], HTTPClient.METHOD_POST, JSON.stringify({"hash": results[part], "verdict": "approve"}))
		if verdict["code"] != 200 or verdict["body"].get("status") != "approved":
			_fail("approve %s: %s" % [part, verdict])
			return
	if not await api.select_deck(1):
		_fail("select_deck: " + api.last_error)
		return
	var after: Dictionary = await api.state()
	if int(after.get("active", -1)) != 1 or after["decks"][1].get("backStatus") != "approved":
		_fail("designer_state after approval: %s" % after)
		return

	# Fresh cache: the pictures must come back from the server and decode.
	for h in results.values():
		DirAccess.remove_absolute("%s/%s.webp" % [CardArt.CACHE_DIR, h])
	CardArt._textures.clear()
	var hashes: Array[String] = []
	hashes.assign(results.values())
	var got: int = await net.fetch_card_art(hashes)
	if got != 2 or CardArt.texture(results["back"]) == null:
		_fail("fetch_card_art got %d" % got)
		return
	print("approved, selected, fetched and decoded")
	print("E2E DESIGNER OK")
	quit(0)
