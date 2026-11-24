extends SceneTree
## Headless end-to-end check of the Founder unlock through the real client
## stack (FounderApi + Net) against a running Nakama at 127.0.0.1:7350.
## A host account seeds the unlock through the console API, saves companies
## (valid, clashing and refused names), switches them on, uploads a logo
## picture, creates a private room, and a guest (the Net autoload, signed in
## as a second account) must see the companies arrive in OP_DECK.
## Run: godot --headless --path client --script res://tests/e2e_founder.gd
## Use a fresh XDG_DATA_HOME: the script rewrites user://device_id.

const CONSOLE := "http://127.0.0.1:7351"
const API := "http://127.0.0.1:7350"
const HTTP_KEY := "defaulthttpkey"

var failures: Array[String] = []
var api
var designer
var net: Node


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		failures.append(what)


func _http(url: String, method: HTTPClient.Method, body: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var req := HTTPRequest.new()
	root.add_child(req)
	req.request(url, headers, method, body)
	var res: Array = await req.request_completed
	req.queue_free()
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"code": int(res[1]), "body": parsed if parsed != null else {}}


func _server_rpc(id: String, body: Dictionary) -> Dictionary:
	return await _http("%s/v2/rpc/%s?http_key=%s&unwrap" % [API, id, HTTP_KEY], HTTPClient.METHOD_POST, JSON.stringify(body))


func _console_token() -> String:
	var auth := await _http(CONSOLE + "/v2/console/authenticate", HTTPClient.METHOD_POST, JSON.stringify({"username": "admin", "password": "password"}))
	return String(auth["body"].get("token", ""))


func _seed_owned(user_id: String, owned: Array) -> int:
	var token := await _console_token()
	var seed_body := JSON.stringify({"value": JSON.stringify({"owned": owned, "syncedAt": 1}), "permission_read": 1, "permission_write": 0})
	var r := await _http("%s/v2/console/storage/purchases/owned/%s" % [CONSOLE, user_id], HTTPClient.METHOD_PUT, seed_body, PackedStringArray(["Authorization: Bearer " + token]))
	return int(r["code"])


## Signs the Net autoload in as the account behind `device_id`.
## WHY not connect_to_server: on Linux OS.get_unique_id() is the machine id,
## so every run and both players would be one account.
func _sign_in(device_id: String, display: String) -> bool:
	net.display_name = display
	net._make_client()
	net.session = await net.client.authenticate_device_async(device_id, display, true)
	if net.session.is_exception():
		print("  auth failed: ", net.session.get_exception().message)
		return false
	return await net._open_socket()


func _save(i: int, n: String, color: String, logo: String) -> String:
	var res: Dictionary = await api.save(i, n, color, logo)
	if res.is_empty() and api.last_error == "too many requests":
		# save_company allows 20 calls a minute (ratelimit.ts).
		print("  (waiting out the save_company rate limit)")
		await create_timer(61.0).timeout
		res = await api.save(i, n, color, logo)
	return "" if not res.is_empty() else String(api.last_error)


func _reset(i: int) -> bool:
	var ok: bool = await api.reset(i)
	if not ok and api.last_error == "too many requests":
		print("  (waiting out the save_company rate limit)")
		await create_timer(61.0).timeout
		ok = await api.reset(i)
	return ok


func _wait(cond: Callable, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _run() -> void:
	net = root.get_node("Net")
	net.host = "127.0.0.1"
	api = load("res://scripts/net/founder_api.gd")
	designer = load("res://scripts/net/designer_api.gd")
	var companies_script = load("res://scripts/game/companies.gd")
	var stamp := "%d%03d" % [Time.get_unix_time_from_system(), randi() % 1000]

	# ---- Host: before the unlock ---------------------------------------------
	print("host: before the unlock")
	if not await _sign_in("founder-host-" + stamp, "FHost" + stamp.right(8)):
		_finish("host could not connect")
		return
	var host_id: String = net.user_id
	var host_client = net.client
	var host_session = net.session
	var st: Dictionary = await api.state()
	_check(not st.is_empty(), "founder_state answers before the unlock (%s)" % api.last_error)
	_check(st.get("owned") == false, "founder_state owned=false before the unlock")
	_check(st.get("productId") == "bb_founder", "productId is bb_founder")
	_check(st.get("uploadBlocker") == "not_owned", "uploadBlocker not_owned before the unlock: %s" % st.get("uploadBlocker"))
	_check(st.get("companies", []).size() == 6 and st["companies"].all(func(c): return c == null), "six standard companies before the unlock")
	_check((await _save(0, "Bright Ideas", "teal", "star")) == "Founder is not unlocked", "save refused before the unlock: '%s'" % api.last_error)
	_check(not await api.set_active(true), "set_active(true) refused before the unlock")
	_check(await api.set_active(false), "set_active(false) allowed before the unlock")

	# ---- Unlock --------------------------------------------------------------
	_check(await _seed_owned(host_id, ["founder"]) == 200, "console seeds the founder unlock")
	st = await api.state()
	_check(st.get("owned") == true, "founder_state owned=true after the unlock")
	_check(st.get("uploadBlocker") == "age_unknown", "uploadBlocker age_unknown before the age answer: %s" % st.get("uploadBlocker"))
	# A Founder-only player is pointed to Designer for the age question.
	var ds: Dictionary = await designer.state()
	print("  info designer_state blocker for a Founder-only owner: '%s'" % ds.get("blocker"))

	# ---- Reset refusal: a standard company cannot come back onto a taken look --
	print("host: reset refusal")
	_check((await _save(1, "Leafline Grocers", "teal", "leaf")) == "", "company 1 custom in teal (%s)" % api.last_error)
	_check((await _save(0, "Pine Co", "green", "star")) == "", "company 0 takes the freed green (%s)" % api.last_error)
	var reset_ok: bool = await _reset(1)
	_check(not reset_ok and api.last_error.begins_with("Pinecone Foods cannot come back yet"), "reset of 1 refused while 0 holds green: '%s'" % api.last_error)
	_check(await _reset(0), "reset of 0 allowed (%s)" % api.last_error)
	_check(await _reset(1), "then reset of 1 allowed (%s)" % api.last_error)
	_check(not await api.reset(9), "reset of company 9 refused: '%s'" % api.last_error)

	# ---- Saving: valid, clashing, refused ------------------------------------
	print("host: saving companies")
	const NAME_SAME := "Another of your companies already has that name."
	const COLOR_SAME := "Another of your companies already has that colour"
	const LOGO_SAME := "Another of your companies already has that logo"
	const SHORT_SAME := "Another of your companies would show the same name on its band"
	_check((await _save(1, "Leafline Grocers", "lime", "leaf")) == "", "save valid company 1 (%s)" % api.last_error)
	_check((await _save(2, "leafline grocers", "teal", "rocket")) == NAME_SAME, "name clash, case-insensitive: '%s'" % api.last_error)
	_check((await _save(2, "Nimbus Air", "teal", "rocket")) == NAME_SAME, "name clash with a standard company: '%s'" % api.last_error)
	_check((await _save(2, "Leafline Partners", "teal", "rocket")).begins_with(SHORT_SAME), "band-name clash (Leafline): '%s'" % api.last_error)
	_check((await _save(2, "The Solar Co", "teal", "rocket")).begins_with(SHORT_SAME), "band-name clash with a standard band (Solar): '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "lime", "rocket")).begins_with(COLOR_SAME), "colour clash with a custom company: '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "yellow", "rocket")).begins_with(COLOR_SAME), "colour clash with a standard company: '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "brown", "rocket")).begins_with(COLOR_SAME), "too-alike colour (brown vs orange): '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "teal", "sun")).begins_with(LOGO_SAME), "logo clash with a standard company: '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "teal", "globe")).begins_with(LOGO_SAME), "too-alike logo (globe vs bolt): '%s'" % api.last_error)
	_check((await _save(2, "A", "teal", "rocket")) == "Use 2 to 18 characters.", "1-character name refused: '%s'" % api.last_error)
	_check((await _save(2, "Nineteen Characters", "teal", "rocket")) == "Use 2 to 18 characters.", "19-character name refused: '%s'" % api.last_error)
	_check((await _save(2, "Admin Corp", "teal", "rocket")) == "Pick a different name.", "staff name refused: '%s'" % api.last_error)
	_check((await _save(2, "Sh1t Happens", "teal", "rocket")) == "Pick a different name.", "look-alike swear refused: '%s'" % api.last_error)
	_check((await _save(2, "Phone 55512345", "teal", "rocket")) != "", "phone number refused: '%s'" % api.last_error)
	_check((await _save(2, "Bad -- Name", "teal", "rocket")) != "", "'Bad -- Name' refused: '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "black", "rocket")) != "", "unknown colour refused: '%s'" % api.last_error)
	_check((await _save(2, "Rocket Mail", "teal", "skull")) != "", "unknown logo refused: '%s'" % api.last_error)
	_check((await _save(6, "Rocket Mail", "teal", "rocket")) == "invalid company", "company 6 refused: '%s'" % api.last_error)
	for ok_name in ["Scunthorpe Steel", "Grape Assets", "Classic Cars"]:
		_check((await _save(2, ok_name, "teal", "rocket")) == "", "ordinary name '%s' allowed (%s)" % [ok_name, api.last_error])
	_check((await _save(2, "Rocket Mail", "teal", "rocket")) == "", "save valid company 2 (%s)" % api.last_error)
	_check((await _save(5, "WWWWWWWWWWWWWWWWWW", "slate", "chart")) == "", "save 18 Ws (%s)" % api.last_error)
	# Pink counts as alike with red: only free once company 5 is no longer red.
	_check((await _save(4, "Smith & Co.", "pink", "crown")) == "", "save 'Smith & Co.' (%s)" % api.last_error)
	_check((await _save(3, "שמש וירח", "brown", "cup")) == "", "save a Hebrew name (%s)" % api.last_error)
	st = await api.state()
	_check(st["companies"][0] == null and st["companies"][1] is Dictionary and st["companies"][1]["name"] == "Leafline Grocers", "row: 0 standard, 1 Leafline")
	# Inactive companies are not reported (nobody else can see them).
	var guest_probe := await _http("%s/v2/account/authenticate/device?create=true&username=FProbe%s" % [API, stamp.right(8)], HTTPClient.METHOD_POST, JSON.stringify({"id": "founder-probe-" + stamp}), PackedStringArray(["Authorization: Basic " + Marshalls.utf8_to_base64("defaultkey:")]))
	var probe_token := String(guest_probe["body"].get("token", ""))
	var rep := await _http("%s/v2/rpc/report_companies?unwrap" % API, HTTPClient.METHOD_POST, JSON.stringify({"userId": host_id}), PackedStringArray(["Authorization: Bearer " + probe_token]))
	var q0: Dictionary = await _server_rpc("company_queue", {})
	var queued0 := false
	for it in q0["body"].get("items", []):
		if it.get("userId") == host_id:
			queued0 = true
	_check(rep["code"] == 200 and not queued0, "a report of inactive companies is not queued (%d)" % rep["code"])

	_check(await api.set_active(true), "set_active(true) after the unlock (%s)" % api.last_error)
	st = await api.state()
	_check(st.get("active") == true, "founder_state active=true")

	# ---- Logo picture ----------------------------------------------------------
	print("host: logo picture")
	var salt := randi() % 1000
	var picture := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	for y in 300:
		for x in 400:
			picture.set_pixel(x, y, Color(float(x) / 400.0, float(y) / 300.0, float((x * y + salt) % 89) / 89.0))
	var bytes := CardArt.encode(CardArt.render(picture, "logo", 1.0, Vector2(0.5, 0.5)))
	_check(bytes.size() > 0 and bytes.size() <= CardArt.MAX_BYTES, "logo renders and encodes (%d bytes)" % bytes.size())
	var up: Dictionary = await api.upload_logo(1, bytes)
	_check(up.is_empty() and api.last_error == "age not set", "upload refused before the age answer: '%s'" % api.last_error)
	_check(String((await designer.set_age("16plus")).get("ageBracket", "")) == "16plus", "age answered 16plus")
	st = await api.state()
	_check(String(st.get("uploadBlocker", "x")) == "", "Founder-only owner may upload after the age answer: '%s'" % st.get("uploadBlocker"))
	up = await api.upload_logo(0, bytes)
	_check(up.is_empty() and api.last_error == "save the company first", "upload to a standard company refused: '%s'" % api.last_error)
	up = await api.upload_logo(1, bytes)
	_check(String(up.get("status", "")) == "pending", "upload pending: %s %s" % [up, api.last_error])
	var hash := String(up.get("hash", ""))
	st = await api.state()
	_check(st["companies"][1].get("picture") == hash and st["companies"][1].get("pictureStatus") == "pending", "founder_state shows the picture pending")
	# A wrong-size picture (a deck back) is refused as a logo.
	var wrong := CardArt.encode(CardArt.render(picture, "back"))
	_check((await api.upload_logo(1, wrong)).is_empty(), "a 250x350 picture is refused as a logo: '%s'" % api.last_error)

	# ---- Room 1: pending picture -----------------------------------------------
	print("room 1 (picture pending)")
	var room := await _play_room(host_client, host_session, "guest1-" + stamp, "FGst" + stamp.right(8))
	if room.is_empty():
		_finish("room 1 did not start")
		return
	var host_deck: Dictionary = room["host_deck"]
	_check(host_deck.get("companies") is Array, "host's OP_DECK carries companies")
	_check(companies_script.room_companies.size() == 6, "guest got six room companies")
	_check(companies_script.name_of(1) == "Leafline Grocers", "guest: name_of(1) = %s" % companies_script.name_of(1))
	_check(companies_script.color_of(1) == companies_script.PALETTE["lime"], "guest: color_of(1) is lime")
	_check(companies_script.logo_of(1) == "leaf", "guest: logo_of(1) = %s" % companies_script.logo_of(1))
	_check(companies_script.name_of(0) == "Sunny Side Solar", "guest: name_of(0) stays standard")
	_check(companies_script.name_of(5) == "WWWWWWWWWWWWWWWWWW", "guest: name_of(5) is the 18 Ws")
	_check(companies_script.name_of(3) == "שמש וירח", "guest: Hebrew name arrives intact")
	_check(companies_script.picture_hashes().is_empty(), "guest: pending picture not sent (%s)" % [companies_script.picture_hashes()])
	_check(companies_script.picture_of(1) == null, "guest: no picture texture while pending")
	# Report: the guest reports the host, which reports the names too.
	_check(await net.report_player(host_id, "name", "e2e"), "guest reports the host")
	var q: Dictionary = await _server_rpc("company_queue", {})
	var queued := false
	for it in q["body"].get("items", []):
		if it.get("userId") == host_id:
			queued = true
	_check(queued, "host's companies are in company_queue after the report")
	await net.leave_match()
	_check(companies_script.room_companies.is_empty(), "leaving the room clears the companies")
	_check(companies_script.name_of(1) == "Pinecone Foods", "after leaving, name_of(1) is standard")
	await room["host_socket"].leave_match_async(room["match_id"])

	# ---- Approve the picture ---------------------------------------------------
	var verdict := await _server_rpc("moderate_card_art", {"hash": hash, "verdict": "approve"})
	_check(verdict["code"] == 200 and verdict["body"].get("status") == "approved", "operator approves the logo: %s" % verdict)
	# Fresh cache: the host's upload cached it in this same process.
	DirAccess.remove_absolute("%s/%s.webp" % [CardArt.CACHE_DIR, hash])
	CardArt._textures.clear()

	# ---- Room 2: approved picture, host leaves mid-game ------------------------
	print("room 2 (picture approved)")
	room = await _play_room(host_client, host_session, "guest1-" + stamp, "")
	if room.is_empty():
		_finish("room 2 did not start")
		return
	_check(companies_script.picture_hashes().size() == 1 and companies_script.picture_hashes()[0] == hash, "guest: approved picture hash sent (%s)" % [companies_script.picture_hashes()])
	await _wait(func(): return companies_script.picture_of(1) != null, 5.0)
	_check(companies_script.picture_of(1) != null, "guest fetched and decoded the approved logo picture")
	await room["host_socket"].leave_match_async(room["match_id"])
	await create_timer(1.0).timeout
	_check(companies_script.name_of(1) == "Leafline Grocers", "host leaving mid-game: guest keeps the room's companies")
	await net.leave_match()
	_check(companies_script.room_companies.is_empty(), "guest leaving clears companies")

	# ---- Moderation: reset with a strike ----------------------------------------
	var mod := await _server_rpc("moderate_companies", {"userId": host_id, "verdict": "reset"})
	_check(mod["code"] == 200 and int(mod["body"].get("strikes", 0)) == 1, "moderate_companies reset adds a strike: %s" % mod)
	q = await _server_rpc("company_queue", {})
	queued = false
	for it in q["body"].get("items", []):
		if it.get("userId") == host_id:
			queued = true
	_check(not queued, "queue entry removed after the verdict")

	# ---- Room 3: after the reset no companies are sent ------------------------
	print("room 3 (after moderator reset)")
	room = await _play_room(host_client, host_session, "guest1-" + stamp, "")
	if room.is_empty():
		_finish("room 3 did not start")
		return
	_check(not (room["host_deck"].get("companies") is Array), "no companies after the reset: %s" % room["host_deck"])
	_check(companies_script.room_companies.is_empty(), "guest: standard companies after the reset")
	await net.leave_match()
	await room["host_socket"].leave_match_async(room["match_id"])
	_finish("")


func _uniq(a: Array) -> Array:
	var out := []
	for x in a:
		var k = String(x).to_lower()
		if not out.has(k):
			out.append(k)
	return out


## The host (raw client on its own socket) creates a private room, the guest
## (Net, signed in as `guest_device`) joins, both ready, and the game starts.
## Answers {host_deck, host_socket, match_id} once the guest has its OP_DECK
## (or the first view, when the room has no look).
func _play_room(host_client, host_session, guest_device: String, guest_display: String) -> Dictionary:
	var host_socket = root.get_node("Nakama").create_socket_from(host_client)
	var conn = await host_socket.connect_async(host_session)
	if conn.is_exception():
		print("  host socket failed: ", conn.get_exception().message)
		return {}
	var seen := {"deck": {}, "view": false}
	host_socket.received_match_state.connect(func(m) -> void:
		if m.op_code == 16:
			seen["deck"] = JSON.parse_string(m.data)
		elif m.op_code == 10:
			seen["view"] = true)
	var rpc = await host_client.rpc_async(host_session, "create_room", JSON.stringify({"stepSeconds": 30, "maxSeats": 7}))
	if rpc.is_exception():
		print("  create_room failed: ", rpc.get_exception().message)
		return {}
	var data: Dictionary = JSON.parse_string(rpc.payload)
	var match_id := String(data["matchId"])
	var code := String(data["code"])
	var joined = await host_socket.join_match_async(match_id, {"code": code})
	if joined.is_exception():
		print("  host join failed: ", joined.get_exception().message)
		return {}
	# The guest: Net signed in as the second account.
	if net.user_id == "" or net.session == host_session or not guest_display.is_empty():
		if not await _sign_in(guest_device, guest_display if not guest_display.is_empty() else net.display_name):
			print("  guest could not connect")
			return {}
	var deck_changed := {"n": 0}
	var on_deck := func() -> void: deck_changed["n"] += 1
	net.custom_deck_changed.connect(on_deck)
	var guest_view := {"v": false}
	var on_view := func(_v: Dictionary) -> void: guest_view["v"] = true
	net.view_updated.connect(on_view)
	if not await net.join_room(code):
		print("  guest join failed")
		return {}
	await create_timer(0.5).timeout
	await host_socket.send_match_state_async(match_id, 2, "{}")
	net.send_ready()
	var started := await _wait(func(): return guest_view["v"] and seen["view"], 15.0)
	# The OP_DECK handler awaits the art fetch before it signals.
	await _wait(func(): return deck_changed["n"] > 0 and not (seen["deck"] as Dictionary).is_empty(), 5.0)
	await create_timer(0.5).timeout
	net.custom_deck_changed.disconnect(on_deck)
	net.view_updated.disconnect(on_view)
	if not started:
		print("  game did not start")
		return {}
	return {"host_deck": seen["deck"], "host_socket": host_socket, "match_id": match_id}


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		failures.append(fatal)
	if failures.is_empty():
		print("E2E FOUNDER OK")
		quit(0)
	else:
		print("E2E FOUNDER FAILED (%d):" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)
