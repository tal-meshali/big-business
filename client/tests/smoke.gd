extends SceneTree
## Headless smoke test: instantiate both scenes and render a fake view.
## Run: godot --headless --path client --script res://tests/smoke.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var table_scene: PackedScene = load("res://scenes/table.tscn")
	if main_scene == null or table_scene == null:
		push_error("scenes failed to load")
		quit(1)
		return

	var table = table_scene.instantiate()
	root.add_child(table)
	await process_frame
	var fake_view := {
		"you": 0,
		"seats": [
			{"id": "a", "name": "You", "isBot": false, "connected": true, "handCount": 3,
			 "hand": [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}],
			 "portfolio": [{"id": 9, "company": 5}], "bronze": 9, "gold": 0, "tokens": [5]},
			{"id": "b", "name": "Broker Bo", "isBot": true, "connected": false, "handCount": 3,
			 "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "c", "name": "Analyst Avi", "isBot": true, "connected": false, "handCount": 3,
			 "portfolio": [{"id": 7, "company": 2}], "bronze": 11, "gold": 0, "tokens": [2]},
		],
		"market": [{"card": {"id": 20, "company": 1}, "coins": 2}, {"card": {"id": 21, "company": 5}, "coins": 0}],
		"supplyCount": 20, "removedCount": 5, "active": 0, "phase": "take", "turn": 4,
		"tookCompany": null, "tokens": [null, null, 2, null, null, 0], "seq": 6, "deadline": 0,
		"drawCost": 1,
		"legal": [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}],
		"result": null,
	}
	table._on_view(fake_view)
	await process_frame
	if table._market_row.get_child_count() != 2:
		push_error("expected 2 market cards, got %d" % table._market_row.get_child_count())
		failures += 1
	if table._hand_cards.size() != 3:
		push_error("expected 3 hand cards, got %d" % table._hand_cards.size())
		failures += 1
	if table._seat_views.filter(func(sv): return sv.visible).size() != 3:
		push_error("expected 3 visible seat views")
		failures += 1
	if table._draw_button.disabled:
		push_error("draw button should be enabled on my take step")
		failures += 1
	var market_cards: Array = table._market_row.get_children()
	if market_cards.size() == 2 and (market_cards[0].disabled or not market_cards[1].disabled):
		push_error("market selectability wrong: token-held company 5 must be disabled")
		failures += 1

	# Play step: only non-taken company may go to the market.
	fake_view["phase"] = "play"
	fake_view["tookCompany"] = 5
	fake_view["drawCost"] = null
	fake_view["legal"] = [
		{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3},
		{"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 2},
	]
	table._on_view(fake_view)
	await process_frame
	if table._keep_button.visible:
		push_error("keep/sell buttons must stay hidden until a card is selected")
		failures += 1
	table._on_hand_card_pressed(3)  # company 5, the company just taken
	await process_frame
	if not table._keep_button.visible or table._keep_button.disabled:
		push_error("keep must be offered for the selected card")
		failures += 1
	if not table._sell_button.disabled:
		push_error("card of the company just taken must not be sellable to the market")
		failures += 1
	table._on_hand_card_pressed(1)
	await process_frame
	if table._sell_button.disabled:
		push_error("a different company must be sellable")
		failures += 1

	# Dividend day renders the result panel.
	fake_view["phase"] = "ended"
	fake_view["legal"] = []
	fake_view["result"] = {
		"companies": [{"company": 5, "majority": 0, "payments": [{"from": 1, "to": 0, "coins": 2}]}, {"company": 2, "majority": null, "payments": []}],
		"scores": [{"seat": 0, "bronze": 9, "gold": 2, "score": 15, "rank": 1}, {"seat": 1, "bronze": 8, "gold": 0, "score": 8, "rank": 3}, {"seat": 2, "bronze": 11, "gold": 0, "score": 11, "rank": 2}],
	}
	table._on_view(fake_view)
	await process_frame
	if not table._result_backdrop.visible or not table._result_label.text.contains("collects 2"):
		push_error("result panel should show the dividend breakdown")
		failures += 1

	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame

	failures += await _coach_checks()
	failures += await _social_checks()
	failures += await _juice_checks()

	if failures == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAILED: %d" % failures)
	quit(failures)


## Coach: steps fire once each, in the right situations, and skip disables it.
func _coach_checks() -> int:
	var failures := 0
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	table.enable_coach()
	await process_frame
	var shown: Array = []
	table.coach.step_shown.connect(func(id: String) -> void: shown.append(id))

	var v := {
		"you": 0,
		"seats": [
			{"id": "a", "name": "You", "isBot": false, "connected": true, "handCount": 3,
			 "hand": [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}],
			 "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "b", "name": "Broker Bo", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "c", "name": "Analyst Avi", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 31, "removedCount": 5, "active": 0, "phase": "take", "turn": 1,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 0, "deadline": 0,
		"drawCost": 0, "legal": [{"type": "take_supply"}], "result": null,
	}
	table._on_view(v)
	await process_frame
	if shown != ["welcome"]:
		push_error("coach should open with welcome, got %s" % [shown])
		failures += 1
	if not table.coach.visible:
		push_error("coach card should be visible")
		failures += 1
	table.coach._on_got_it()
	await process_frame
	if shown != ["welcome", "first_take"]:
		push_error("first_take should follow welcome on an empty market, got %s" % [shown])
		failures += 1
	table.coach._on_got_it()

	# Play step.
	v["phase"] = "play"
	v["tookCompany"] = 5
	v["drawCost"] = null
	v["legal"] = [{"type": "play_portfolio", "cardId": 1}, {"type": "play_market", "cardId": 1}]
	table._on_view(v)
	await process_frame
	if shown.back() != "first_play":
		push_error("first_play should fire on the first play step, got %s" % [shown])
		failures += 1
	table.coach._on_got_it()

	# A bot pays coins onto the market, and a token moves. Steps queue and show one at a time.
	table._on_events(2, [{"type": "took_supply", "seat": 1, "cost": 1}, {"type": "token_moved", "company": 2, "from": null, "to": 1}])
	await process_frame
	if not table.coach.seen.has("bot_paid") or not table.coach.seen.has("token_first"):
		push_error("bot_paid and token_first should fire from events, seen %s" % [table.coach.seen.keys()])
		failures += 1
	if shown.back() != "bot_paid" or not table.coach._body.text.contains("Broker Bo"):
		push_error("bot_paid should show first and name the bot")
		failures += 1
	table.coach._on_got_it()
	await process_frame
	if shown.back() != "token_first" or not table.coach._body.text.contains("Tidewater Freight"):
		push_error("token_first should follow and name the company, got %s" % [shown])
		failures += 1
	table.coach._on_got_it()

	# My take step with coins in the market and a token of mine blocking a share.
	v["phase"] = "take"
	v["active"] = 0
	v["market"] = [{"card": {"id": 20, "company": 1}, "coins": 2}, {"card": {"id": 21, "company": 5}, "coins": 0}]
	v["seats"][0]["tokens"] = [5]
	v["supplyCount"] = 2
	v["legal"] = [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}]
	table._on_view(v)
	# Queued events animate before the view renders; wait for that to finish.
	for i in 120:
		await process_frame
		if not table._animating and not table._pending_events.size():
			break
	await process_frame
	for id in ["endgame_near", "token_blocks", "take_with_coins"]:
		if not table.coach.seen.has(id):
			push_error("%s should fire, seen %s" % [id, table.coach.seen.keys()])
			failures += 1
	while table.coach.visible:
		table.coach._on_got_it()
		await process_frame
	# Same view again must not re-fire anything.
	var count_before := shown.size()
	table._on_view(v)
	await process_frame
	if shown.size() != count_before or table.coach.visible:
		push_error("steps must fire only once")
		failures += 1

	# Skip disables everything, including dividend day.
	table.coach._on_skip()
	v["phase"] = "ended"
	v["legal"] = []
	v["result"] = {"companies": [], "scores": []}
	table._on_view(v)
	await process_frame
	if shown.has("dividend") or table.coach.visible:
		push_error("skip should silence the coach")
		failures += 1
	table.queue_free()
	return failures


## Emotes render as bubbles unless the sender is muted; the profile card applies progress.
func _social_checks() -> int:
	var failures := 0
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := {
		"you": 0,
		"seats": [
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 3, "hand": [], "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "u-bo", "name": "Bo", "isBot": false, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:0", "name": "Analyst Avi", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 20, "removedCount": 5, "active": 1, "phase": "take", "turn": 2,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 3, "deadline": 0, "drawCost": null, "legal": [], "result": null,
	}
	table._on_view(v)
	await process_frame
	var before: int = table._fx_layer.get_child_count()
	table._on_emote_shown(1, "wave")
	await process_frame
	if table._fx_layer.get_child_count() != before + 1:
		push_error("an emote should add a bubble")
		failures += 1
	if table._emote_bar.visible:
		push_error("emote bar starts hidden")
		failures += 1
	table._toggle_emote_bar()
	if not table._emote_bar.visible or table._emote_bar.get_child(0).get_child_count() != Protocol.EMOTES.size():
		push_error("emote bar should list every preset")
		failures += 1
	table._toggle_emote_bar()
	var net: Node = root.get_node("Net")
	net.mute_player("u-bo", true)
	var count: int = table._fx_layer.get_child_count()
	table._on_emote_shown(1, "laugh")
	await process_frame
	if table._fx_layer.get_child_count() != count:
		push_error("muted players must not show bubbles")
		failures += 1
	net.mute_player("u-bo", false)
	table._on_emote_shown(2, "nonsense")
	await process_frame
	if table._fx_layer.get_child_count() != count:
		push_error("unknown emote ids are ignored")
		failures += 1
	table.queue_free()

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._apply_progress({"xp": 120, "level": 2, "gamesPlayed": 3, "wins": 1, "streak": 4}, true)
	if not main._profile_label.text.contains("Level 2") or main._daily_button.disabled:
		push_error("profile card should show level and enable the daily bonus")
		failures += 1
	if main._xp_bar.min_value != 50 or main._xp_bar.max_value != 200 or main._xp_bar.value != 120:
		push_error("xp bar bounds wrong: %s %s %s" % [main._xp_bar.min_value, main._xp_bar.max_value, main._xp_bar.value])
		failures += 1
	main.queue_free()
	return failures


## Juice: synthesized sounds exist, the sound toggle is a real no-op, the
## timer glow follows my deadline, and the emote bar uses drawn icons.
func _juice_checks() -> int:
	var failures := 0
	var sfx: Node = root.get_node("Sfx")
	for name in sfx.NAMES:
		var stream = sfx.streams.get(name)
		if stream == null or not (stream is AudioStreamWAV) or stream.data.size() == 0:
			push_error("Sfx stream %s should exist and be non-empty" % name)
			failures += 1
	var was_enabled: bool = sfx.enabled
	sfx.enabled = false
	var played_before: int = sfx.played_count
	if sfx.play("turn_chime") or sfx.played_count != played_before:
		push_error("Sfx.play must be a no-op while disabled")
		failures += 1
	sfx.enabled = true
	if not sfx.play("turn_chime") or sfx.played_count != played_before + 1:
		push_error("Sfx.play should accept a known sound while enabled")
		failures += 1
	sfx.enabled = was_enabled

	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := {
		"you": 0,
		"seats": [
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 3, "hand": [{"id": 1, "company": 0}], "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:0", "name": "Analyst Avi", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 20, "removedCount": 5, "active": 0, "phase": "take", "turn": 2,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 3, "deadline": 0, "drawCost": 0,
		"legal": [{"type": "take_supply"}], "result": null,
	}
	table._on_view(v)
	await process_frame
	if table._timer_glow.visible:
		push_error("timer glow must stay hidden with no deadline")
		failures += 1
	v["deadline"] = Time.get_unix_time_from_system() * 1000.0 + 3000.0
	table._on_view(v)
	await process_frame
	if not table._timer_glow.visible:
		push_error("timer glow should show when my deadline is 3 s away")
		failures += 1
	v["active"] = 1
	table._on_view(v)
	await process_frame
	if table._timer_glow.visible:
		push_error("timer glow must not show on an opponent's turn")
		failures += 1
	var icons := 0
	for node in table._emote_bar.find_children("*", "EmoteIcon", true, false):
		icons += 1
	if icons != 6:
		push_error("emote bar should hold 6 drawn icons, found %d" % icons)
		failures += 1
	if table._sound_button.button_pressed != sfx.enabled:
		push_error("sound button should mirror Sfx.enabled")
		failures += 1
	table.queue_free()
	return failures
