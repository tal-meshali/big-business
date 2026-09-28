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
	failures += await _quests_checks()

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


## Quests panel: rows from a fake profile, claim state, the cosmetic picker
## and the card back / felt selections that CardView and the tables read.
func _quests_checks() -> int:
	var failures := 0
	Cosmetics.reset()
	# Loaded by path: naming the class here would compile the panel (and its
	# Net calls) before the autoloads exist in a --script run.
	var panel = load("res://scripts/ui/quests_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var profile := {
		"trackPoints": 40,
		"unlocked": ["back_classic", "table_green", "back_midnight"],
		"equipped": {"cardBack": "back_classic", "table": "table_green"},
		"track": [
			{"points": 30, "cosmeticId": "back_midnight"}, {"points": 70, "cosmeticId": "table_navy"},
			{"points": 120, "cosmeticId": "back_sunrise"}, {"points": 200, "cosmeticId": "table_burgundy"},
			{"points": 300, "cosmeticId": "back_pinstripe"},
		],
		"quests": {
			"daily": [
				{"id": "d_play_3", "text": "Play 3 games", "target": 3, "points": 10, "progress": 3, "claimable": true, "claimed": false},
				{"id": "d_win_1", "text": "Win a game", "target": 1, "points": 15, "progress": 0, "claimable": false, "claimed": false},
				{"id": "d_people", "text": "Play a game with other people", "target": 1, "points": 10, "progress": 1, "claimable": false, "claimed": true},
			],
			"weekly": [
				{"id": "w_win_3", "text": "Win 3 games this week", "target": 3, "points": 40, "progress": 1, "claimable": false, "claimed": false},
				{"id": "w_coins_25", "text": "Collect 25 coins from Market shares", "target": 25, "points": 30, "progress": 25, "claimable": true, "claimed": false},
			],
		},
	}
	panel.apply_profile(profile)
	await process_frame
	if panel.rows.size() != 5 or panel._daily_box.get_child_count() != 3 or panel._weekly_box.get_child_count() != 2:
		push_error("quests panel should list 3 daily and 2 weekly rows, got %d" % panel.rows.size())
		failures += 1
	var by_id := {}
	for r in panel.rows:
		by_id[r["id"]] = r
	if by_id["d_play_3"]["button"].disabled or by_id["d_play_3"]["button"].text != "Claim":
		push_error("a completed quest must offer Claim")
		failures += 1
	if not by_id["d_win_1"]["button"].disabled:
		push_error("an unfinished quest must not be claimable")
		failures += 1
	if not by_id["d_people"]["button"].disabled or by_id["d_people"]["button"].text != "Claimed":
		push_error("a claimed quest shows Claimed and stays disabled")
		failures += 1
	if by_id["w_coins_25"]["bar"].value != 25 or by_id["w_coins_25"]["bar"].max_value != 25:
		push_error("progress bar should mirror progress / target")
		failures += 1
	if not panel._track_label.text.contains("Navy felt") or not panel._track_label.text.contains("70"):
		push_error("track summary should name the next unlock, got %s" % panel._track_label.text)
		failures += 1
	if panel._track_bar.min_value != 30 or panel._track_bar.max_value != 70 or panel._track_bar.value != 40:
		push_error("track bar bounds wrong: %s %s %s" % [panel._track_bar.min_value, panel._track_bar.max_value, panel._track_bar.value])
		failures += 1

	# A claim flips the row and can unlock the next step.
	panel._apply_claim("d_play_3", 70, ["back_classic", "table_green", "back_midnight", "table_navy"])
	if not by_id["d_play_3"]["button"].disabled or by_id["d_play_3"]["button"].text != "Claimed":
		push_error("claimed row should flip to Claimed")
		failures += 1
	if panel.track_points != 70 or panel._table_buttons["table_navy"].disabled:
		push_error("claim should update track points and enable the new unlock")
		failures += 1

	# Picker: locked items disabled, unlocked ones enabled, current one pressed.
	if panel._back_buttons["back_midnight"].disabled or not panel._back_buttons["back_sunrise"].disabled or not panel._back_buttons["back_pinstripe"].disabled:
		push_error("card back picker should enable only unlocked backs")
		failures += 1
	if not panel._back_buttons["back_sunrise"].text.contains("120"):
		push_error("locked items show their unlock threshold, got %s" % panel._back_buttons["back_sunrise"].text)
		failures += 1
	if not panel._back_buttons["back_classic"].button_pressed:
		push_error("the equipped back should show as pressed")
		failures += 1
	if not panel._table_buttons["table_burgundy"].disabled:
		push_error("locked felt must be disabled")
		failures += 1

	# Picking applies to Cosmetics at once (the server call fails offline and is ignored).
	var changes: Array = []
	panel.cosmetic_changed.connect(func(slot: String, id: String) -> void: changes.append([slot, id]))
	panel._on_pick("cardBack", "back_midnight")
	if Cosmetics.card_back != "back_midnight" or not panel._back_buttons["back_midnight"].button_pressed or panel._back_buttons["back_classic"].button_pressed:
		push_error("picking an unlocked back should apply it and move the pressed state")
		failures += 1
	if changes != [["cardBack", "back_midnight"]]:
		push_error("cosmetic_changed should fire once with the pick, got %s" % [changes])
		failures += 1
	panel._on_pick("cardBack", "back_pinstripe")
	if Cosmetics.card_back == "back_pinstripe":
		push_error("a locked back must not be applied")
		failures += 1
	var green := Cosmetics.table_bg_color()
	panel._on_pick("table", "table_navy")
	if Cosmetics.table != "table_navy" or Cosmetics.table_bg_color() == green:
		push_error("picking an unlocked felt should change the table colour")
		failures += 1

	# The card back drives CardView's back; the table reads the felt.
	var card := CardView.new()
	root.add_child(card)
	card.setup(1, 0, 0, false)
	await process_frame
	if card.face_up or Cosmetics.card_back_entry()["id"] != "back_midnight":
		push_error("face-down card should draw the selected back (%s)" % Cosmetics.card_back)
		failures += 1
	card.queue_free()
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var felt: ColorRect = table.get_child(0)
	if felt.color != Cosmetics.table_bg_color() or felt.color == green:
		push_error("table background should use the picked felt")
		failures += 1
	table.queue_free()

	# get_profile applies the server's equipped set; unknown ids are ignored.
	Cosmetics.apply_equipped({"cardBack": "back_sunrise", "table": "nonsense"})
	if Cosmetics.card_back != "back_sunrise" or Cosmetics.table != "table_navy":
		push_error("apply_equipped should take valid ids only")
		failures += 1

	# The lobby toggles the overlay and recolours its felt.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if main._quests_panel.visible:
		push_error("quests overlay starts hidden")
		failures += 1
	main._on_toggle_quests()
	if not main._quests_panel.visible:
		push_error("quests button should open the overlay")
		failures += 1
	main._quests_panel.apply_profile(profile)
	if main._quests_panel.rows.size() != 5:
		push_error("lobby panel should take the profile")
		failures += 1
	main._on_cosmetic_changed("table", Cosmetics.table)
	if main._felt.color != Cosmetics.table_bg_color():
		push_error("lobby felt should follow the picked table")
		failures += 1
	main.queue_free()
	panel.queue_free()
	Cosmetics.reset()
	return failures
