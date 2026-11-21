extends SceneTree
## Headless end-to-end check of the real client network stack against a
## running Nakama at 127.0.0.1:7350. Quick-plays, waits for bots, then plays
## the first legal action on every turn until dividend day.
## Run: godot --headless --path client --script res://tests/e2e_client.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var net: Node = root.get_node("Net")
	net.host = "127.0.0.1"
	var ok: bool = await net.connect_to_server()
	if not ok:
		print("E2E CLIENT FAILED: could not connect")
		quit(1)
		return
	print("connected as ", net.display_name, " user ", net.user_id)

	# The name step's path: a refused name says why, a good one is saved,
	# the account is marked named, and the socket is reopened under it.
	# WHY by path: NamesApi uses the Net autoload, which is not there yet
	# when this script is compiled.
	var names = load("res://scripts/net/names_api.gd")
	var refused: String = await names.save("admin")
	if refused != "Pick a different name.":
		print("E2E CLIENT FAILED: a reserved name should be refused with its sentence, got '%s'" % refused)
		quit(1)
		return
	# A sentence with " at " in it used to be cut short by the client.
	var too_long: String = await names.save("A name far too long")
	if too_long != "Too long. Use 2 to 16 characters.":
		print("E2E CLIENT FAILED: a long name should be refused with its whole sentence, got '%s'" % too_long)
		quit(1)
		return
	var wanted := "Godot %d" % (Time.get_ticks_usec() % 1000000)
	var problem: String = await names.save(wanted)
	var links: Dictionary = await net.get_account_links()
	if not problem.is_empty() or net.display_name != wanted or net.session.username != wanted \
			or links.get("named") != true or links.get("username") != wanted or not net.is_connected_to_server():
		print("E2E CLIENT FAILED: saving a name ('%s', display '%s', links %s)" % [problem, net.display_name, links])
		quit(1)
		return
	print("named ", wanted)

	# Private room through the real client: creating joins with the room code
	# (the server refuses a private join without it); leave and come back by code.
	var lobby_seen := {"code": "", "names": []}
	var on_lobby := func(l: Dictionary) -> void:
		lobby_seen["code"] = String(l.get("roomCode", ""))
		lobby_seen["names"] = l.get("seats", []).map(func(seat: Dictionary) -> String: return String(seat.get("name", "")))
	net.lobby_updated.connect(on_lobby)
	var code: String = await net.create_room()
	if code.is_empty() or net.room_code != code:
		print("E2E CLIENT FAILED: create room (code '%s', room_code '%s')" % [code, net.room_code])
		quit(1)
		return
	var waited := 0
	while lobby_seen["code"] != code and waited < 30:
		await create_timer(0.1).timeout
		waited += 1
	if lobby_seen["code"] != code:
		print("E2E CLIENT FAILED: no lobby for room ", code)
		quit(1)
		return
	if not lobby_seen["names"].has(wanted):
		print("E2E CLIENT FAILED: the room should seat the player under the new name, got ", lobby_seen["names"])
		quit(1)
		return
	await net.leave_match()
	if not await net.join_room(code.to_lower()) or net.room_code != code:
		print("E2E CLIENT FAILED: rejoin room by code")
		quit(1)
		return
	await net.leave_match()
	net.lobby_updated.disconnect(on_lobby)
	print("private room ", code, ": created, left and rejoined by code")

	var joined: bool = await net.quick_play()
	if not joined:
		print("E2E CLIENT FAILED: quick play")
		quit(1)
		return
	print("joined match ", net.match_id)

	var state := {"view": {}, "events": 0, "errors": 0}
	net.view_updated.connect(func(v: Dictionary) -> void: state["view"] = v)
	net.events_received.connect(func(_seq: int, events: Array) -> void: state["events"] += events.size())
	net.server_error.connect(func(m: String) -> void:
		state["errors"] += 1
		print("server error: ", m))

	var started := Time.get_ticks_msec()
	var acted_seq := -1
	# WHY: 20 s lobby wait plus ~70 s of bot think time leaves little slack at 120 s.
	while Time.get_ticks_msec() - started < 240000:
		await create_timer(0.1).timeout
		var v: Dictionary = state["view"]
		if v.is_empty():
			continue
		if v.get("phase") == "ended":
			var scores: Array = v["result"]["scores"]
			var me := int(v["you"])
			var mine: Dictionary = {}
			for s in scores:
				if int(s["seat"]) == me:
					mine = s
			print("game ended after %d turns; my score %d rank %d; %d events; %d errors" % [
				int(v["turn"]), int(mine.get("score", -1)), int(mine.get("rank", -1)), state["events"], state["errors"]])
			if state["errors"] > 0:
				print("E2E CLIENT FAILED: server errors")
				quit(1)
				return
			print("E2E CLIENT OK")
			quit(0)
			return
		if int(v.get("active", -1)) == int(v.get("you", -2)) and int(v.get("seq", 0)) != acted_seq:
			var legal: Array = v.get("legal", [])
			if legal.is_empty():
				continue
			acted_seq = int(v["seq"])
			net.send_action(legal[0])
	print("E2E CLIENT FAILED: timeout")
	quit(1)
