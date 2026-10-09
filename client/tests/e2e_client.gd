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
	net.display_name = "GodotBot"
	var ok: bool = await net.connect_to_server()
	if not ok:
		print("E2E CLIENT FAILED: could not connect")
		quit(1)
		return
	print("connected as ", net.display_name, " user ", net.user_id)

	# The refresh token buys a new session on the same account, and the
	# socket opens on it (what a reconnect after two hours does).
	var first_token: String = net.session.token
	if not await net.refresh_session() or net.session.user_id != net.user_id or net.session.token.is_empty():
		print("E2E CLIENT FAILED: session refresh (token changed: %s)" % [net.session.token != first_token])
		quit(1)
		return
	net._closing = true
	net.socket.close()
	net._closing = false
	if not await net._reconnect_session():
		print("E2E CLIENT FAILED: reopen the socket on the refreshed session")
		quit(1)
		return
	var restored = await net._restore_session()
	if restored == null or restored.user_id != net.user_id:
		print("E2E CLIENT FAILED: the saved session should come back for this server")
		quit(1)
		return

	# Private room through the real client: creating joins with the room code
	# (the server refuses a private join without it); leave and come back by code.
	var lobby_seen := {"code": ""}
	var on_lobby := func(l: Dictionary) -> void: lobby_seen["code"] = String(l.get("roomCode", ""))
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
