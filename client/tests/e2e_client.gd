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
