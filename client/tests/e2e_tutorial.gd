extends SceneTree
## Headless end-to-end run of the tutorial through the real table scene and
## coach against a running Nakama at 127.0.0.1:7350. Dismisses each coach
## card, then plays a sensible move (the coached one while the first turns
## are restricted), until dividend day.
## Run: godot --headless --path client --script res://tests/e2e_tutorial.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var net: Node = root.get_node("Net")
	net.host = "127.0.0.1"
	net.display_name = "Learner"
	if not await net.connect_to_server():
		print("E2E TUTORIAL FAILED: could not connect")
		quit(1)
		return
	if not await net.start_tutorial():
		print("E2E TUTORIAL FAILED: start_tutorial")
		quit(1)
		return
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	if table.coach == null:
		print("E2E TUTORIAL FAILED: coach not attached in tutorial mode")
		quit(1)
		return
	var shown: Array = []
	table.coach.step_shown.connect(func(id: String) -> void: shown.append(id))
	var errors := 0
	net.server_error.connect(func(m: String) -> void:
		errors += 1
		print("server error: ", m))

	var started := Time.get_ticks_msec()
	var acted_seq := -1
	var my_plays := 0
	var forced_seen := []
	# WHY: tutorial bots think 1.8 s per step on purpose; a 60-turn game spends
	# about three minutes on them alone.
	while Time.get_ticks_msec() - started < 360000:
		await create_timer(0.15).timeout
		if table.coach.visible:
			table.coach._on_got_it()
			continue
		if table._animating:
			continue
		var v: Dictionary = table.view
		if v.is_empty():
			continue
		if v.get("phase") == "ended":
			break
		if int(v.get("active", -1)) != int(v.get("you", -2)) or int(v.get("seq", 0)) == acted_seq:
			continue
		acted_seq = int(v["seq"])
		var forced: Dictionary = table._restriction
		if not forced.is_empty():
			forced_seen.append("%d:%s" % [Coach.my_turn_index(v), forced.get("take", forced.get("play", ""))])
		if forced.get("take", "") == "supply":
			table._on_draw_pressed()
		elif v.get("phase") == "take":
			# Prefer a market share with coins, else draw, else any market share.
			var best_id := -1
			var best_coins := 0
			for slot in v.get("market", []):
				var id := int(slot["card"]["id"])
				if int(slot.get("coins", 0)) > best_coins and table._legal("take_market", id):
					best_coins = int(slot["coins"])
					best_id = id
			if best_id >= 0:
				table._on_market_card_pressed(best_id)
			elif table._legal("take_supply"):
				table._on_draw_pressed()
			else:
				for slot in v.get("market", []):
					var id := int(slot["card"]["id"])
					if table._legal("take_market", id):
						table._on_market_card_pressed(id)
						break
		else:
			var hand: Array = v["seats"][int(v["you"])].get("hand", [])
			if hand.is_empty():
				continue
			# Alternate: sell a sellable card every other turn so the Market fills up.
			my_plays += 1
			var pick := -1
			if forced.get("play", "") == "portfolio":
				pass
			elif forced.get("play", "") == "market" or my_plays % 2 == 0:
				for card in hand:
					if table._legal("play_market", int(card["id"])):
						pick = int(card["id"])
						break
			if pick >= 0:
				table._on_hand_card_pressed(pick)
				await process_frame
				table._on_sell_pressed()
			else:
				table._on_hand_card_pressed(int(hand[0]["id"]))
				await process_frame
				table._on_keep_pressed()

	var v: Dictionary = table.view
	if v.get("phase") != "ended":
		print("E2E TUTORIAL FAILED: timeout; steps %s" % [shown])
		quit(1)
		return
	# Let the dividend animation and final coach card run.
	for i in 40:
		await create_timer(0.1).timeout
		if table.coach.visible:
			table.coach._on_got_it()
	print("tutorial finished after %d turns; coach steps: %s; forced moves: %s; errors %d" % [int(v["turn"]), shown, forced_seen, errors])
	if forced_seen.size() != 4 or forced_seen[0] != "1:supply" or forced_seen[1] != "1:portfolio" or not String(forced_seen[3]).ends_with(":market"):
		print("E2E TUTORIAL FAILED: first two turns should be coached, got %s" % [forced_seen])
		quit(1)
		return
	var required := ["welcome", "first_take", "first_play", "first_sell", "dividend"]
	for id in required:
		if not shown.has(id):
			print("E2E TUTORIAL FAILED: missing step ", id)
			quit(1)
			return
	if shown.size() < 6 or errors > 0:
		print("E2E TUTORIAL FAILED: too few steps or server errors")
		quit(1)
		return
	print("E2E TUTORIAL OK")
	quit(0)
