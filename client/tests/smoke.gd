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
			 "portfolio": [{"id": 9, "company": 5}], "bronze": 9, "gold": 0, "tokens": [5.0]},
			{"id": "b", "name": "Broker Bo", "isBot": true, "connected": false, "handCount": 3,
			 "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "c", "name": "Analyst Avi", "isBot": true, "connected": false, "handCount": 3,
			 "portfolio": [{"id": 7, "company": 2}], "bronze": 11, "gold": 0, "tokens": [2.0]},
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
	# Opponents' kept shares lie on the felt, with a regulator chip on the
	# company whose token the holder has (Avi: one share of 2, token 2).
	var pfs: Array = table._board.portfolios
	if pfs.size() != 2 or not pfs.any(func(pf): return pf["stacks"] == [[2, 1, true]]):
		push_error("expected each opponent's shares on the felt with Avi's chip on company 2, got %s" % [pfs])
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
	failures += await _touch_checks()
	failures += await _help_checks()
	failures += await _feedback_checks()
	failures += await _forced_turn_checks()
	failures += await _hand_fit_checks()
	failures += await _get_ready_checks()
	failures += await _forfeit_checks()
	failures += await _peek_checks()
	failures += await _draw_landing_checks()
	failures += await _friends_checks()
	failures += await _quests_checks()
	failures += await _account_checks()
	failures += await _shop_checks()
	failures += await _designer_checks()
	failures += await _plus_checks()
	failures += await _club_checks()
	failures += await _watch_checks()

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
	# Floats, as JSON delivers them from the server.
	v["seats"][0]["tokens"] = [5.0]
	v["supplyCount"] = 2
	v["legal"] = [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}]
	table._on_view(v)
	# Queued events animate before the view renders; wait for that to finish.
	for i in 120:
		await process_frame
		if not table._animating and not table._pending_events.size():
			break
	await process_frame
	var held := {"portfolio": [{"id": 30, "company": 5}], "tokens": [5.0]}
	if not table._stacks_of(held).has([5, 1, true]):
		push_error("a float token from JSON should mark its stack: %s" % [table._stacks_of(held)])
		failures += 1
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


## Every button is at least 48 px in both directions (phone touch target),
## a tap on the seat's timer arc opens the seat menu, mutes survive a
## restart, and blocked players stay hidden.
func _touch_checks() -> int:
	var failures := 0
	# Headless windows default to 64x64; input outside the window is dropped.
	root.size = Vector2i(720, 1280)
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := {
		"you": 0,
		"seats": [
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 3,
			 "hand": [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}], "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "u-bo", "name": "Bo", "isBot": false, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "u-cy", "name": "Cy", "isBot": false, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 20, "removedCount": 5, "active": 1, "phase": "take", "turn": 2,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 3,
		"deadline": Time.get_unix_time_from_system() * 1000.0 + 20000.0, "drawCost": null, "legal": [], "result": null,
	}
	table._on_view(v)
	table._toggle_emote_bar()
	await process_frame
	await process_frame
	failures += _check_button_sizes(table, "table")
	table._toggle_emote_bar()

	# Tap the left edge of the timer arc around Bo's avatar (radius 29 px).
	var bo_view = null
	for sv in table._seat_views:
		if sv.visible and sv.seat_index == 1:
			bo_view = sv
	if bo_view == null:
		push_error("Bo's seat view should be visible")
		return failures + 1
	var at: Vector2 = bo_view.get_global_transform_with_canvas() * Vector2(34 - 29, SeatView.H / 2.0)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)
		await process_frame
	if table._seat_menu_target != 1:
		push_error("a tap on the timer arc should open the seat menu for seat 1, got %d" % table._seat_menu_target)
		failures += 1
	table._seat_menu.hide()

	# Mutes are saved and reloaded; blocks hide emotes and lock the menu.
	var net: Node = root.get_node("Net")
	net.mute_player("u-cy", true)
	net.muted.clear()
	net._load_settings()
	if not net.is_muted("u-cy"):
		push_error("a mute should survive a restart")
		failures += 1
	net.mute_player("u-cy", false)
	net.blocked["u-bo"] = true
	var count: int = table._fx_layer.get_child_count()
	table._on_emote_shown(1, "wave")
	await process_frame
	if table._fx_layer.get_child_count() != count:
		push_error("blocked players must not show bubbles")
		failures += 1
	table._on_seat_pressed(1, Vector2(100, 100))
	if not table._seat_menu.is_item_disabled(2) or table._seat_menu.get_item_text(2) != "Blocked":
		push_error("the seat menu should show a blocked player as Blocked")
		failures += 1
	table._seat_menu.hide()
	net.blocked.erase("u-bo")
	table.queue_free()

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	failures += _check_button_sizes(main, "lobby")
	main.queue_free()
	return failures


func _check_button_sizes(scene: Node, where: String) -> int:
	var failures := 0
	for b in scene.find_children("*", "Button", true, false):
		if b is CardView or not b.is_visible_in_tree():
			continue
		if b.size.x < 48 or b.size.y < 48:
			push_error("%s button '%s' is %s, under the 48 px touch target" % [where, b.text, b.size])
			failures += 1
	return failures


## Server field parsing, and the rules / help overlay from the lobby and table.
func _help_checks() -> int:
	var failures := 0
	var cases := {
		"127.0.0.1": ["http", "127.0.0.1", 7350],
		" 192.168.1.20:7351 ": ["http", "192.168.1.20", 7351],
		"https://play.example.com": ["https", "play.example.com", 443],
		"HTTPS://play.example.com:8443/": ["https", "play.example.com", 8443],
		"http://10.0.0.5": ["http", "10.0.0.5", 80],
		"": ["http", "127.0.0.1", 7350],
	}
	var net: Node = root.get_node("Net")
	for text in cases:
		var a: Dictionary = net.parse_address(text)
		var want: Array = cases[text]
		if [a["scheme"], a["host"], a["port"]] != want:
			push_error("parse_address(%s) = %s, want %s" % [text, a, want])
			failures += 1
	var saved := [net.scheme, net.host, net.port]
	for text in ["127.0.0.1", "https://play.example.com", "http://10.0.0.5:8080"]:
		net.set_server_address(text)
		if net.server_address() != text:
			push_error("server_address should round-trip %s, got %s" % [text, net.server_address()])
			failures += 1
	net.scheme = saved[0]
	net.host = saved[1]
	net.port = saved[2]

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._on_help()
	await process_frame
	await process_frame
	var helps: Array = main.find_children("*", "HelpScreen", true, false)
	if helps.size() != 1:
		push_error("Rules and help should open one help screen, got %d" % helps.size())
		return failures + 1
	var help: HelpScreen = helps[0]
	var text := ""
	for l in help.find_children("*", "Label", true, false):
		text += l.text + "\n"
	for section in HelpScreen.SECTIONS:
		if not text.contains(section["title"]):
			push_error("help is missing section %s" % section["title"])
			failures += 1
	for c in Companies.DATA:
		if not text.contains("%s: %d" % [c["name"], c["shares"]]):
			push_error("help should list %s's share count" % c["name"])
			failures += 1
	if help._email_button.disabled != AppInfo.SUPPORT_EMAIL.is_empty() or help._privacy_button.disabled != AppInfo.PRIVACY_URL.is_empty():
		push_error("contact buttons should be enabled exactly when AppInfo is filled in")
		failures += 1
	failures += _check_button_sizes(help, "help")
	help.close_help()
	await process_frame
	if main.find_children("*", "HelpScreen", true, false).size() != 0:
		push_error("Close should remove the help screen")
		failures += 1
	main.queue_free()
	return failures


## Sounds exist, the turn chime plays once per turn, the rim glows and ticks
## only on your own step under five seconds, events make sounds, and the
## help screen toggles sound.
func _feedback_checks() -> int:
	var failures := 0
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	for sound_name in Sfx.NAMES:
		var st: AudioStreamWAV = Sfx._streams.get(sound_name)
		if st == null or st.data.size() < 200:
			push_error("sound %s should be synthesised" % sound_name)
			failures += 1
	var now := Time.get_unix_time_from_system() * 1000.0
	var v := {
		"you": 0,
		"seats": [
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 3,
			 "hand": [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}], "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:0", "name": "Ivy", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:1", "name": "Avi", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [{"card": {"id": 20, "company": 1}, "coins": 0}], "supplyCount": 20, "removedCount": 5, "active": 0, "phase": "take", "turn": 4,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 9,
		"deadline": now + 20000.0, "drawCost": 1, "legal": [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}], "result": null,
	}
	table._on_view(v)
	await process_frame
	if table.sfx.history.count("turn") != 1:
		push_error("your turn should chime once, history %s" % [table.sfx.history])
		failures += 1
	table._on_view(v.duplicate(true))
	await process_frame
	if table.sfx.history.count("turn") != 1:
		push_error("the same turn must not chime twice")
		failures += 1
	if table._glow.visible:
		push_error("no glow with 20 seconds left")
		failures += 1
	v["deadline"] = Time.get_unix_time_from_system() * 1000.0 + 3500.0
	table._on_view(v.duplicate(true))
	await process_frame
	await process_frame
	if not table._glow.visible or not table.sfx.history.has("tick"):
		push_error("under five seconds on my step the rim should glow and tick")
		failures += 1
	v["active"] = 1
	v["legal"] = []
	table._on_view(v.duplicate(true))
	await process_frame
	await process_frame
	if table._glow.visible:
		push_error("no glow on someone else's step")
		failures += 1

	# A bot draws (paying a coin) and plays to its portfolio.
	table.sfx.history.clear()
	table._on_events(10, [
		{"type": "took_supply", "seat": 1, "cost": 1},
		{"type": "step", "seat": 1, "phase": "play", "turn": 4},
		{"type": "played", "seat": 1, "card": {"id": 30, "company": 2}, "to": "portfolio"},
	])
	v["seq"] = 11
	table._on_view(v.duplicate(true))
	for i in 180:
		await process_frame
		if not table._animating:
			break
	for sound_name in ["coin", "deal", "place"]:
		if not table.sfx.history.has(sound_name):
			push_error("events should play %s, history %s" % [sound_name, table.sfx.history])
			failures += 1
	table.queue_free()

	var holder := Control.new()
	root.add_child(holder)
	var help := HelpScreen.open_over(holder)
	await process_frame
	var was: bool = Sfx.sound_on
	help._on_toggle_sound()
	if Sfx.sound_on == was or not help._sound_button.text.ends_with("off" if was else "on"):
		push_error("the sound toggle should flip and relabel")
		failures += 1
	help._on_toggle_sound()
	help.close_help()
	holder.queue_free()

	# With no session the resume check must do nothing.
	root.get_node("Net").check_connection()
	return failures


## Tutorial v2: the learner's first two turns only allow the coached move.
func _forced_turn_checks() -> int:
	var failures := 0
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	table.enable_coach()
	table.coach.seen = {"welcome": true, "first_take": true, "first_play": true, "take_with_coins": true, "bot_paid": true, "endgame_near": true}
	await process_frame
	var hand := [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}, {"id": 4, "company": 5}]
	var v := {
		"you": 0,
		"seats": [
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 4, "hand": hand, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:0", "name": "Ivy", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:1", "name": "Avi", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 30, "removedCount": 5, "active": 0, "phase": "play", "turn": 1,
		"tookCompany": 5, "tokens": [null, null, null, null, null, null], "seq": 1, "deadline": 0, "drawCost": null,
		"legal": [
			{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3}, {"type": "play_portfolio", "cardId": 4},
			{"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 2},
		],
		"result": null,
	}
	# Turn 1, play: keep only.
	table._on_view(v)
	await process_frame
	table._on_hand_card_pressed(1)
	await process_frame
	if table._keep_button.disabled or not table._sell_button.disabled:
		push_error("turn 1 should allow Keep and not Sell")
		failures += 1
	if not table._prompt.text.begins_with("Tutorial: keep"):
		push_error("turn 1 prompt should carry the coach hint, got %s" % table._prompt.text)
		failures += 1

	# Turn 2 (turn 4 of a 3-seat game), take: only the Market share with coins.
	v["turn"] = 4
	v["phase"] = "take"
	v["tookCompany"] = null
	v["drawCost"] = 2
	v["market"] = [{"card": {"id": 20, "company": 1}, "coins": 2}, {"card": {"id": 21, "company": 2}, "coins": 0}]
	v["legal"] = [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}, {"type": "take_market", "cardId": 21}]
	v["seats"][0]["hand"] = hand.slice(0, 3)
	table._on_view(v.duplicate(true))
	await process_frame
	var market: Array = table._market_row.get_children()
	if not table._draw_button.disabled or market[0].disabled or not market[1].disabled:
		push_error("turn 2 take should allow only the Market share with coins")
		failures += 1

	# Turn 2, play: sell only, and only cards that may be sold.
	v["phase"] = "play"
	v["tookCompany"] = 1
	v["drawCost"] = null
	v["seats"][0]["hand"] = hand.slice(0, 3) + [{"id": 20, "company": 1}]
	v["legal"] = [
		{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3}, {"type": "play_portfolio", "cardId": 20},
		{"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 2}, {"type": "play_market", "cardId": 3},
	]
	table._on_view(v.duplicate(true))
	await process_frame
	if not table.coach.seen.has("first_sell"):
		push_error("turn 2 play should explain selling")
		failures += 1
	while table.coach.visible:
		table.coach._on_got_it()
	table._on_hand_card_pressed(20)
	if table._selected_card == 20:
		push_error("the company just taken cannot be selected when selling is forced")
		failures += 1
	table._on_hand_card_pressed(2)
	await process_frame
	if not table._keep_button.disabled or table._sell_button.disabled:
		push_error("turn 2 play should allow Sell and not Keep")
		failures += 1

	# Turn 3: free play again.
	v["turn"] = 7
	table._on_view(v.duplicate(true))
	await process_frame
	table._on_hand_card_pressed(2)
	await process_frame
	if table._keep_button.disabled or table._sell_button.disabled or table._prompt.text.begins_with("Tutorial"):
		push_error("from turn 3 every legal move is allowed")
		failures += 1

	# Skipping the tutorial lifts a restriction at once.
	v["turn"] = 1
	table._on_view(v.duplicate(true))
	await process_frame
	table.coach._on_skip()
	await process_frame
	table._on_hand_card_pressed(2)
	await process_frame
	if table._sell_button.disabled:
		push_error("skip should lift the turn 1 restriction")
		failures += 1
	if Coach.my_turn_index({"you": 1, "active": 1, "turn": 5, "phase": "take", "seats": [{}, {}, {}]}) != 2:
		push_error("seat 1's second turn in a 3-seat game is turn 5")
		failures += 1
	table.queue_free()
	return failures


## A 4-card hand (the play step) stays on screen, tilt and scale included.
func _hand_fit_checks() -> int:
	var failures := 0
	root.size = Vector2i(720, 1280)
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var hand := []
	for i in 4:
		hand.append({"id": i + 1, "company": i})
	var v := {
		"you": 0,
		"seats": [
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 4, "hand": hand, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:0", "name": "Ivy", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "bot:1", "name": "Avi", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 20, "removedCount": 5, "active": 0, "phase": "play", "turn": 7,
		"tookCompany": 3, "tokens": [null, null, null, null, null, null], "seq": 5, "deadline": 0, "drawCost": null, "legal": [], "result": null,
	}
	table._on_view(v)
	await process_frame
	await process_frame
	var width: float = table.get_viewport_rect().size.x
	for cv in table._hand_cards:
		var xf: Transform2D = cv.get_global_transform()
		for corner in [Vector2.ZERO, Vector2(CardView.W, 0), Vector2(0, CardView.H), Vector2(CardView.W, CardView.H)]:
			var x: float = (xf * corner).x
			if x < 0.0 or x > width:
				push_error("hand card %d corner at x=%.0f is off screen (width %.0f)" % [cv.card_id, x, width])
				failures += 1
				break
	table.queue_free()
	return failures


func _live_view() -> Dictionary:
	return {
		"you": 1,
		"seats": [
			{"id": "bot:0", "name": "Ivy", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "me", "name": "You", "isBot": false, "connected": true, "handCount": 3,
			 "hand": [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}], "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "u-bo", "name": "Bo", "isBot": false, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 31, "removedCount": 5, "active": 0, "phase": "take", "turn": 1,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 0,
		"deadline": Time.get_unix_time_from_system() * 1000.0 + 34000.0, "drawCost": null, "legal": [], "result": null,
		"startsInMs": 1500,
	}


## The get-ready countdown: shown from the first view, lists the turn order,
## hides the step timer, holds the turn chime, and ends when play begins.
## The table also renders the view the lobby received before it opened.
func _get_ready_checks() -> int:
	var failures := 0
	var net: Node = root.get_node("Net")
	var v := _live_view()
	net.last_view = v
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	net.last_view = {}
	if table.view.is_empty() or table._hand_cards.size() != 3:
		push_error("the table should render the view the lobby already received")
		failures += 1
	if not table._ready_overlay.visible or table._ready_count.text != "2":
		push_error("get-ready should count down from the first view, got visible=%s count=%s" % [table._ready_overlay.visible, table._ready_count.text])
		failures += 1
	if not table._ready_seats.text.begins_with("1.  Ivy  • bot\n2.  You") or table._ready_first.text != "Ivy goes first":
		push_error("get-ready should list the turn order, got %s / %s" % [table._ready_seats.text, table._ready_first.text])
		failures += 1
	if table._timer_label.text != "":
		push_error("the step timer should stay hidden during the countdown")
		failures += 1
	# My turn comes first in this deal: no chime until the countdown ends.
	v["active"] = 1
	table._on_view(v.duplicate(true))
	await process_frame
	if table._ready_first.text != "You go first!" or table.sfx.history.has("turn"):
		push_error("you go first, and the chime waits for the countdown")
		failures += 1
	v["startsInMs"] = 0
	v["legal"] = [{"type": "take_supply"}]
	v["drawCost"] = 0
	table._on_view(v.duplicate(true))
	for i in 40:
		await create_timer(0.05).timeout
		if not table._ready_overlay.visible:
			break
	if table._ready_overlay.visible or table._ready_count.text != "Go!" or table._ready_ends_msec != 0:
		push_error("the countdown should end with Go! when play begins")
		failures += 1
	if table.sfx.history.count("turn") != 1:
		push_error("the turn chime should play once the countdown ends, history %s" % [table.sfx.history])
		failures += 1
	# A countdown that runs out locally before the server's view also ends.
	v["startsInMs"] = 200
	table._on_view(v.duplicate(true))
	for i in 40:
		await create_timer(0.05).timeout
		if not table._ready_overlay.visible:
			break
	if table._ready_overlay.visible:
		push_error("the countdown should end on its own when time is up")
		failures += 1
	table.queue_free()
	return failures


## Forfeit: offered only in a live game you sit in, behind a confirmation;
## other players' forfeits show over their seat.
func _forfeit_checks() -> int:
	var failures := 0
	var net: Node = root.get_node("Net")
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := _live_view()
	v["startsInMs"] = 0
	table._on_view(v.duplicate(true))
	await process_frame
	if table._leave_button.text != "Forfeit":
		push_error("a live game should offer Forfeit, got %s" % table._leave_button.text)
		failures += 1
	table._on_leave_pressed()
	if not table._forfeit_overlay.visible:
		push_error("Forfeit should ask for confirmation first")
		failures += 1
	await process_frame
	failures += _check_button_sizes(table._forfeit_overlay, "forfeit dialog")
	var keep_playing: Button = null
	for b in table._forfeit_overlay.find_children("*", "Button", true, false):
		if b.text == "Keep playing":
			keep_playing = b
	keep_playing.pressed.emit()
	if table._forfeit_overlay.visible:
		push_error("Keep playing should close the confirmation")
		failures += 1
	var bubbles: int = table._fx_layer.get_child_count()
	table._on_player_forfeited(2)
	await process_frame
	if table._fx_layer.get_child_count() != bubbles + 1 or not table._status.text.begins_with("Bo forfeited"):
		push_error("another player's forfeit should show over their seat, status %s" % table._status.text)
		failures += 1
	net.tutorial_mode = true
	table._on_view(v.duplicate(true))
	if table._leave_button.text != "Leave":
		push_error("the tutorial offers Leave, not Forfeit")
		failures += 1
	net.tutorial_mode = false
	v["phase"] = "ended"
	v["result"] = {"companies": [], "scores": []}
	table._on_view(v.duplicate(true))
	if table._leave_button.text != "Leave":
		push_error("after dividend day the button is Leave")
		failures += 1
	table.queue_free()
	return failures


func _mouse(at: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	ev.global_position = at
	root.push_input(ev)


## Press and hold shows a close-up above everything without selecting the
## card; a tap still selects; Cancel returns the card to its place.
func _peek_checks() -> int:
	var failures := 0
	root.size = Vector2i(720, 1280)
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := _live_view()
	v["startsInMs"] = 0
	v["active"] = 1
	v["phase"] = "play"
	v["tookCompany"] = 5
	v["seats"][1]["hand"] = [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}, {"id": 4, "company": 5}]
	v["market"] = [{"card": {"id": 20, "company": 1}, "coins": 2}]
	v["legal"] = [{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3}, {"type": "play_portfolio", "cardId": 4}, {"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 2}]
	table._on_view(v.duplicate(true))
	await process_frame
	await process_frame
	var card: CardView = table._hand_cards[3]
	var at: Vector2 = card.get_global_transform() * Vector2(CardView.W / 2.0, CardView.H * 0.6)
	_mouse(at, true)
	await create_timer(CardView.HOLD_SECONDS + 0.15).timeout
	if table._peek == null or table._peek.card_id != 4 or table._peek.scale.x < table.PEEK_SCALE * 0.84:
		push_error("holding a hand card should show its close-up")
		failures += 1
	elif table._peek.get_global_rect().position.y > card.get_global_rect().position.y:
		push_error("the close-up should sit above the held card")
		failures += 1
	_mouse(at, false)
	await process_frame
	if table._peek != null:
		push_error("letting go should close the close-up")
		failures += 1
	if table._selected_card != -1:
		push_error("a hold must not select the card")
		failures += 1
	_mouse(at, true)
	await process_frame
	_mouse(at, false)
	await process_frame
	if table._selected_card != 4 or card.z_index != 1:
		push_error("a tap should select the card and lift it above the others")
		failures += 1
	table._on_cancel_pressed()
	await create_timer(0.3).timeout
	if card.z_index != 0 or absf(card.position.y - card._rest_y) > 0.5:
		push_error("Cancel should return the card to its place, y %s rest %s" % [card.position.y, card._rest_y])
		failures += 1
	# Quick toggles must not strand a card above its rest.
	for i in 5:
		table._on_hand_card_pressed(2)
	await create_timer(0.3).timeout
	var two: CardView = table._hand_cards[1]
	if absf(two.position.y - (two._rest_y - CardView.LIFT)) > 0.5:
		push_error("after an odd number of taps the card should rest lifted, y %s" % two.position.y)
		failures += 1
	# Market cards can be looked at even when they cannot be taken.
	var market: CardView = table._market_row.get_child(0)
	var mat: Vector2 = market.get_global_transform() * Vector2(CardView.W / 2.0, CardView.H / 2.0)
	_mouse(mat, true)
	await create_timer(CardView.HOLD_SECONDS + 0.15).timeout
	if table._peek == null or table._peek.coins != 2:
		push_error("holding a Market card should show it with its coins")
		failures += 1
	_mouse(mat, false)
	await process_frame
	table.queue_free()
	return failures


## A share you draw flies face up into the slot it takes in your new hand.
func _draw_landing_checks() -> int:
	var failures := 0
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := _live_view()
	v["startsInMs"] = 0
	v["active"] = 1
	v["turn"] = 2
	v["drawCost"] = 0
	v["legal"] = [{"type": "take_supply"}]
	table._on_view(v.duplicate(true))
	await process_frame
	table._on_events(1, [{"type": "took_supply", "seat": 1, "cost": 0}])
	v["phase"] = "play"
	v["tookCompany"] = 4
	v["drawCost"] = null
	v["seats"][1]["hand"] = [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}, {"id": 9, "company": 4}]
	v["legal"] = [{"type": "play_portfolio", "cardId": 9}]
	table._on_view(v.duplicate(true))
	await process_frame
	var want: Dictionary = table._hand_slot(3, 4)
	var slot: Dictionary = table._new_hand_slot()
	if slot.get("pos") != want["pos"] or int(slot.get("company", -1)) != 4:
		push_error("the drawn share should land in slot 4 of 4, got %s" % [slot])
		failures += 1
	var ghost: CardView = null
	for c in table._fx_layer.get_children():
		if c is CardView:
			ghost = c
	if ghost == null or not ghost.face_up or ghost.company != 4:
		push_error("your own draw should fly face up")
		failures += 1
	for i in 40:
		await create_timer(0.05).timeout
		if not table._animating:
			break
	if table._hand_cards.size() != 4 or table._hand_cards[3].card_id != 9 or table._hand_cards[3].position != want["pos"]:
		push_error("the new hand should show the drawn share in the slot it landed in")
		failures += 1
	table.queue_free()
	return failures


## Friends panel: rows render with the right buttons, the Invite button
## follows the room code, an invite row shows and its Join fires the signal.
func _friends_checks() -> int:
	var failures := 0
	# WHY: loaded by path, not by class_name: the panel uses the Net autoload,
	# which does not exist yet when this test script is compiled.
	var panel = load("res://scripts/ui/friends_panel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.set_friends([
		{"userId": "u-bo", "name": "Bo", "online": true, "state": 0},
		{"userId": "u-ada", "name": "Ada", "online": false, "state": 2},
		{"userId": "u-cal", "name": "Cal", "online": false, "state": 1},
	])
	await process_frame
	if panel._list.get_child_count() != 3:
		push_error("expected 3 friend rows, got %d" % panel._list.get_child_count())
		failures += 1
		panel.queue_free()
		return failures
	var bo_row: HBoxContainer = panel._list.get_child(0)
	if bo_row.get_child(0).get_theme_color("font_color") != panel.ONLINE:
		push_error("online friend should have a green dot")
		failures += 1
	if bo_row.get_child(1).text != "Bo":
		push_error("friend row should show the name")
		failures += 1
	var invite: Button = bo_row.get_child(2)
	if invite.text != "Invite" or invite.visible:
		push_error("Invite must be hidden outside a private room")
		failures += 1
	if panel._list.get_child(1).get_child(2).text != "Accept":
		push_error("a received request should offer Accept")
		failures += 1
	if panel._list.get_child(2).get_child(2).text != "Pending":
		push_error("a sent request should read Pending")
		failures += 1
	if bo_row.get_child(bo_row.get_child_count() - 1).text != "Remove" or bo_row.get_child(3).text != "Gift":
		push_error("a friend row has Gift, then Remove")
		failures += 1
	if panel._list.get_child(1).get_child(3).text != "Remove":
		push_error("a request row has no Gift")
		failures += 1
	var bo_id := String(panel._friends[0].get("userId", ""))
	panel.set_extras({"waiting": 2, "names": ["Cara", "Dev"], "claimLeft": 5, "sentToday": [bo_id], "sendLeft": 9, "points": 5}, [bo_id])
	await process_frame
	bo_row = panel._list.get_child(0)
	if bo_row.get_child(3).text != "Watch" or bo_row.get_child(4).text != "Sent" or not bo_row.get_child(4).disabled:
		push_error("a friend in a game offers Watch; a gift sent today reads Sent")
		failures += 1
	if not panel._gift_row.visible or panel._gift_label.text != "2 gifts from Cara, Dev (+5 track points each)" or panel._collect_button.custom_minimum_size.y < 48:
		push_error("waiting gifts show with Collect, got '%s'" % panel._gift_label.text)
		failures += 1
	panel.set_extras({}, [])

	panel.room_code = "ABC234"
	await process_frame
	invite = panel._list.get_child(0).get_child(2)
	if not invite.visible:
		push_error("Invite should show once the lobby is in a private room")
		failures += 1
	if panel._list.get_child(0).get_child(0).get_theme_color("font_color") != panel.ONLINE or panel._list.get_child(1).get_child(0).get_theme_color("font_color") != panel.OFFLINE:
		push_error("online dots wrong after re-render")
		failures += 1
	for b in [invite, panel._list.get_child(0).get_child(3), panel._add_button, panel._name_edit]:
		if b.custom_minimum_size.y < 48:
			push_error("%s is under the 48 px touch target" % b.get_class())
			failures += 1

	var joined: Array = []
	panel.join_requested.connect(func(code: String) -> void: joined.append(code))
	panel.visible = false
	panel.show_invite("Cara", "XYZ789")
	await process_frame
	if not panel.visible:
		push_error("an invite should open the panel")
		failures += 1
	if panel._invites.get_child_count() != 1:
		push_error("expected 1 invite row, got %d" % panel._invites.get_child_count())
		failures += 1
	else:
		var row: HBoxContainer = panel._invites.get_child(0)
		if not row.get_child(0).text.contains("Cara invited you to room XYZ789"):
			push_error("invite text wrong: %s" % row.get_child(0).text)
			failures += 1
		var join: Button = row.get_child(1)
		if join.text != "Join" or join.custom_minimum_size.y < 48:
			push_error("invite row needs a 48 px Join button")
			failures += 1
		join.pressed.emit()
		await process_frame
		if joined != ["XYZ789"]:
			push_error("Join should request the invite's code, got %s" % [joined])
			failures += 1
		if panel._invites.get_child_count() != 0:
			push_error("a used invite should disappear")
			failures += 1
	# A live invite reaches the listening panel once and is not queued for
	# the next lobby visit; a queued one is offered once by the next panel.
	var net: Node = root.get_node("Net")
	var live = NakamaAPI.ApiNotification.create(NakamaAPI, {"id": "smoke-inv-1", "code": Protocol.INVITE_CODE, "content": JSON.stringify({"fromName": "Dee", "code": "QRS456", "fromUserId": "u-dee"})})
	net._on_notification(live)
	await process_frame
	if panel._invites.get_child_count() != 1 or not panel._invites.get_child(0).get_child(0).text.contains("Dee invited you to room QRS456"):
		push_error("a live invite should show in the listening panel")
		failures += 1
	if not net.pending_invites.is_empty():
		push_error("an invite shown live must not stay queued for the next lobby")
		failures += 1
	net.pending_invites.append({"fromName": "Eve", "code": "TUV123"})
	var later = load("res://scripts/ui/friends_panel.gd").new()
	root.add_child(later)
	await process_frame
	if later._invites.get_child_count() != 1 or not net.pending_invites.is_empty():
		push_error("a queued invite should be shown once by the next panel")
		failures += 1
	later.queue_free()

	# Empty list shows a hint instead of nothing.
	panel.set_friends([])
	if panel._list.get_child_count() != 1 or not (panel._list.get_child(0) is Label):
		push_error("empty friends list should show a hint")
		failures += 1
	panel.queue_free()
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
	var felt: Color = table._board.felt_color
	if felt != Cosmetics.table_bg_color() or felt == green:
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


## Account linking: no token provider on Linux, so the lobby shows the guest
## label and hides both link buttons; the pure helpers behave.
func _account_checks() -> int:
	var failures := 0
	var avail: Dictionary = SocialTokens.available()
	if avail.get("apple", true) or avail.get("google", true):
		push_error("SocialTokens.available() should be all false on %s, got %s" % [OS.get_name(), avail])
		failures += 1
	if SocialTokens.is_mobile():
		push_error("SocialTokens.is_mobile() should be false in the headless test")
		failures += 1
	if SocialTokens.request_apple() != "" or SocialTokens.request_google() != "":
		push_error("SocialTokens.request_* must return \"\" without a plugin")
		failures += 1

	var net: Node = root.get_node("Net")
	if net.describe_account_links({}) != "Guest account (device)":
		push_error("describe_account_links({}) should be the guest label")
		failures += 1
	if net.describe_account_links({"apple": false, "google": false, "device": true}) != "Guest account (device)":
		push_error("device-only links should be the guest label")
		failures += 1
	if net.describe_account_links({"apple": true, "google": false}) != "Signed in with Apple":
		push_error("apple-only links should say Signed in with Apple")
		failures += 1
	if net.describe_account_links({"apple": true, "google": true}) != "Signed in with Apple and Google":
		push_error("both links should list both providers")
		failures += 1
	# Offline: linking with an empty token or no session fails cleanly, and
	# the RPC wrapper returns {} instead of touching a null client.
	if await net.link_apple("") or await net.link_google("") or await net.unlink_apple() or await net.unlink_google():
		push_error("link/unlink must fail without a token or session")
		failures += 1
	if not (await net.get_account_links()).is_empty():
		push_error("get_account_links should be {} while offline")
		failures += 1
	# Provider persistence round-trip through user://net.cfg.
	var previous_provider: String = net.provider
	net.provider = "apple"
	net.save_settings()
	var cfg := ConfigFile.new()
	if cfg.load(net.SETTINGS_PATH) != OK or cfg.get_value("player", "provider", "") != "apple":
		push_error("provider should be saved under [player] provider")
		failures += 1
	net.provider = previous_provider
	net.save_settings()

	# WHY: loaded by path, not by class_name: the lobby uses the Net autoload,
	# which the class-name scan would otherwise pull into the graph as a cycle.
	var lobby = load("res://scripts/ui/main.gd").new()
	root.add_child(lobby)
	await process_frame
	await process_frame
	if lobby._account_label.text != "Guest account (device)":
		push_error("account row should show the guest label offline, got %s" % lobby._account_label.text)
		failures += 1
	if lobby._link_apple_button.visible or lobby._link_google_button.visible:
		push_error("link buttons must be hidden without a token provider")
		failures += 1
	lobby.queue_free()
	return failures


## Shop: rows from a fake catalog, Buy disabled without the store plugin,
## Use / In use for owned skins, Restore purchases always offered, paid
## skins labelled in the quests picker, and Remote Config hiding the shop.
func _shop_checks() -> int:
	var failures := 0
	Cosmetics.reset()
	RemoteConfig.reset()
	if not Cosmetics.is_paid("back_gilded") or Cosmetics.is_paid("back_midnight") or not Cosmetics.is_table("table_walnut"):
		push_error("paid skins should be in the catalog and flagged paid")
		failures += 1
	var catalog := {
		"configured": true,
		"owned": ["table_walnut"],
		"skins": [
			{"id": "back_gilded", "slot": "cardBack", "name": "Gilded", "productId": "bb_skin_back_gilded", "owned": false},
			{"id": "back_blueprint", "slot": "cardBack", "name": "Blueprint", "productId": "bb_skin_back_blueprint", "owned": false},
			{"id": "table_walnut", "slot": "table", "name": "Walnut", "productId": "bb_skin_table_walnut", "owned": true},
		],
	}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	if not main._shop_button.visible or main._shop_panel.visible:
		push_error("shop button shows by default; the overlay starts hidden")
		failures += 1
	var shop = main._shop_panel
	shop.visible = true
	shop.apply_catalog(catalog)
	await process_frame
	if shop.rows.size() != 3:
		push_error("shop should list 3 skins, got %d" % shop.rows.size())
		failures += 1
	var gilded: Button = shop._row_by_id("back_gilded")["button"]
	var walnut: Button = shop._row_by_id("table_walnut")["button"]
	if not gilded.text.begins_with("Buy") or not gilded.disabled:
		push_error("without the store plugin Buy is shown disabled (got '%s', disabled %s)" % [gilded.text, gilded.disabled])
		failures += 1
	if walnut.text != "Use" or walnut.disabled:
		push_error("an owned skin offers Use (got '%s')" % walnut.text)
		failures += 1
	if not shop._restore_button.visible or shop._restore_button.disabled:
		push_error("Restore purchases must always be offered")
		failures += 1
	# Using an owned skin applies at once (the server call fails offline and keeps it).
	await shop._use(shop._row_by_id("table_walnut"))
	if Cosmetics.table != "table_walnut" or walnut.text != "In use" or not walnut.disabled:
		push_error("Use should put the felt on and read In use (table %s, '%s')" % [Cosmetics.table, walnut.text])
		failures += 1
	main._on_cosmetic_changed("table", Cosmetics.table)
	if main._felt.color != Cosmetics.swatch_color("table_walnut"):
		push_error("the lobby felt should follow a shop felt")
		failures += 1
	failures += _check_button_sizes(shop, "shop")
	# A refund (server answer without the skin) turns Use back into Buy.
	shop.apply_owned([])
	if not walnut.text.begins_with("Buy"):
		push_error("a skin no longer owned should be offered for sale again")
		failures += 1
	# The quests picker labels paid skins instead of showing a points cost.
	var quests = main._quests_panel
	quests.apply_profile({"trackPoints": 0, "unlocked": ["back_classic", "table_green"], "track": [], "equipped": {}})
	var picker_text := ""
	for b in quests.find_children("*", "Button", true, false):
		if String(b.text).begins_with("Gilded"):
			picker_text = b.text
			if not b.disabled:
				push_error("an unowned paid skin must be disabled in the picker")
				failures += 1
	if picker_text != "Gilded  (shop)":
		push_error("paid skin picker label should say shop, got '%s'" % picker_text)
		failures += 1
	# Remote Config hides the shop; tutorial auto-routing is read from it too.
	RemoteConfig.apply({"shopEnabled": false, "tutorialAutoRoute": true, "pushEnabled": "junk"})
	main._apply_remote_config()
	if main._shop_button.visible or main._shop_panel.visible:
		push_error("shopEnabled false should hide the shop")
		failures += 1
	if not RemoteConfig.tutorial_auto_route or not RemoteConfig.push_enabled:
		push_error("RemoteConfig.apply should take typed values and ignore junk")
		failures += 1
	if PushTokens.request_token() != "" or Purchases.available() or PushTokens.platform() != "":
		push_error("store and push plugins are absent on the desktop")
		failures += 1
	main.queue_free()
	RemoteConfig.reset()
	Cosmetics.reset()
	return failures


## Designer: framing and rendering pictures to the templates, the room deck
## on cards, and the panel showing the step that is missing.
func _designer_checks() -> int:
	var failures := 0
	var back_rect := CardArt.crop_rect(Vector2i(1000, 1000), "back", 1.0, Vector2(0.5, 0.5))
	if back_rect.size != Vector2i(714, 1000) or back_rect.position != Vector2i(143, 0):
		push_error("back crop should be the largest 5:7 box, centred (got %s)" % back_rect)
		failures += 1
	var win_rect := CardArt.crop_rect(Vector2i(1000, 1000), "c0", 2.0, Vector2(1.0, 0.0))
	if win_rect.size != Vector2i(500, 352) or win_rect.end.x != 1000 or win_rect.position.y != 0:
		push_error("a zoomed window crop should stay inside the picture (got %s)" % win_rect)
		failures += 1
	var picture := Image.create(900, 600, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.2, 0.5, 0.8))
	picture.fill_rect(Rect2i(300, 200, 300, 200), Color(0.9, 0.7, 0.1))
	for part in ["back", "c4"]:
		var img := CardArt.render(picture, part, 1.5, Vector2(0.4, 0.5))
		var bytes := CardArt.encode(img)
		if img.get_size() != CardArt.template_size(part) or img.get_format() != Image.FORMAT_RGB8:
			push_error("%s should render at its template size without alpha" % part)
			failures += 1
		if bytes.is_empty() or bytes.size() > CardArt.MAX_BYTES or CardArt.webp_size(bytes) != CardArt.template_size(part):
			push_error("%s should encode as a lossy WebP the server accepts (%d bytes, %s)" % [part, bytes.size(), CardArt.webp_size(bytes)])
			failures += 1

	# A room deck puts its pictures on the cards; the setting hides them.
	var hash := "f".repeat(64)
	var webp := CardArt.encode(CardArt.render(picture, "back"))
	if not CardArt.add_art(hash, Marshalls.raw_to_base64(webp)) or CardArt.texture(hash) == null:
		push_error("fetched art should be cached by hash")
		failures += 1
	CardArt.set_room_deck({"owner": "u1", "back": hash, "art": [null, null, hash, null, null, null]})
	if CardArt.back_texture() == null or CardArt.company_texture(2) == null or CardArt.company_texture(0) != null:
		push_error("the room deck should give the back and company 2 a picture, others none")
		failures += 1
	if CardArt.deck_hashes() != [hash] or CardArt.missing_hashes().size() != 0 or CardArt.deck_owner() != "u1":
		push_error("deck hashes should be listed once and found in the cache")
		failures += 1
	var card := CardView.new()
	card.size = Vector2(CardView.W, CardView.H)
	root.add_child(card)
	card.setup(1, 2, 0, true)
	await process_frame
	card.setup(1, 2, 0, false)
	await process_frame
	card.queue_free()
	CardArt.show_custom = false
	if CardArt.back_texture() != null:
		push_error("turning custom decks off should show the standard back")
		failures += 1
	CardArt.show_custom = true
	CardArt.clear_room_deck()
	if CardArt.back_texture() != null:
		push_error("leaving the room clears its deck")
		failures += 1
	DirAccess.remove_absolute("%s/%s.webp" % [CardArt.CACHE_DIR, hash])

	if load("res://scripts/net/designer_api.gd").clean_error("Error: Designer is not unlocked at reject (index.js:866:13(3))") != "Designer is not unlocked":
		push_error("server refusals should read as their message only")
		failures += 1

	# Loaded by path: these scripts use the Net autoload, which a --script run
	# only has once the tree is up.
	var panel = load("res://scripts/ui/designer_panel.gd").new()
	panel.size = Vector2(672, 1100)
	root.add_child(panel)
	await process_frame
	panel.apply_state({"enabled": true, "owned": false, "slots": 0, "blocker": "not_owned", "decks": [], "active": -1})
	if not panel._unlock_box.visible or panel._deck_box.visible or panel._age_box.visible:
		push_error("without the unlock the panel offers it and nothing else")
		failures += 1
	panel.apply_state({"enabled": true, "owned": true, "slots": 3, "blocker": "age_unknown", "decks": [], "active": -1})
	if not panel._age_box.visible or panel._unlock_box.visible or panel._deck_box.visible:
		push_error("with the unlock and no age the panel asks the age")
		failures += 1
	panel.apply_state({"enabled": true, "owned": true, "slots": 3, "blocker": "too_young", "decks": [], "active": -1})
	if not panel._blocked_label.visible or panel._deck_box.visible:
		push_error("too young to upload: say so, no decks")
		failures += 1
	var empty_deck := {"back": null, "backStatus": null, "art": [null, null, null, null, null, null], "artStatus": [null, null, null, null, null, null]}
	var deck0 := {"back": hash, "backStatus": "pending", "art": [null, null, null, null, null, null], "artStatus": [null, null, null, null, null, null]}
	panel.apply_state({"enabled": true, "owned": true, "slots": 3, "blocker": "", "decks": [deck0, empty_deck, empty_deck], "active": 0})
	await process_frame
	if not panel._deck_box.visible or panel._parts_list.get_child_count() != 7 or not panel._use_toggle.button_pressed:
		push_error("an unlocked adult sees 7 part rows for the active deck")
		failures += 1
	var first_row: Label = panel._parts_list.get_child(0).get_child(0)
	if not first_row.text.contains("Card back") or not first_row.text.contains("Waiting for review"):
		push_error("the back row should show its review status, got '%s'" % first_row.text)
		failures += 1
	failures += _check_button_sizes(panel, "designer")
	panel.open_editor(picture, "c1")
	await process_frame
	if not panel._editor.visible or panel._deck_box.visible or panel._preview.preview_art == null:
		push_error("picking a picture opens the framing editor with a live preview")
		failures += 1
	if panel.rendered().get_size() != CardArt.WINDOW_SIZE:
		push_error("the editor renders at the art-window template")
		failures += 1
	panel.close_editor()
	if panel._editor.visible or not panel._deck_box.visible or panel._preview.preview_art != null:
		push_error("cancel returns to the deck")
		failures += 1
	panel.queue_free()

	var shop = load("res://scripts/ui/shop_panel.gd").new()
	root.add_child(shop)
	await process_frame
	if not shop._designer_button.visible:
		push_error("the shop offers Designer by default")
		failures += 1
	await shop._on_open_designer()
	if not shop.designer_panel.visible or shop._deed_panel.visible:
		push_error("Designer opens over the shop")
		failures += 1
	if shop.designer_panel._status.text != "Connect to use Designer.":
		push_error("offline the Designer panel says to connect, got '%s'" % shop.designer_panel._status.text)
		failures += 1
	shop.queue_free()
	RemoteConfig.apply({"designerEnabled": false})
	if RemoteConfig.designer_enabled:
		push_error("Remote Config can switch Designer off")
		failures += 1
	RemoteConfig.reset()
	return failures


## Plus: the subscription row, host skins on the table, the Plus skin, the
## stats text and the larger Designer.
func _plus_checks() -> int:
	var failures := 0
	Cosmetics.reset()
	RemoteConfig.reset()
	if not Cosmetics.is_plus("back_ticker") or not Cosmetics.is_plus("table_slate") or Cosmetics.is_paid("back_ticker"):
		push_error("Plus skins are flagged plus, not paid")
		failures += 1
	Cosmetics.set_room_skins("back_ticker", "table_walnut")
	if Cosmetics.shown_card_back() != "back_ticker" or Cosmetics.table_bg_color() != Cosmetics.swatch_color("table_walnut") or Cosmetics.card_back != "back_classic":
		push_error("a Plus host's skins show on the table without changing your own")
		failures += 1
	var card := CardView.new()
	card.size = Vector2(CardView.W, CardView.H)
	root.add_child(card)
	card.setup(1, 0, 0, false)
	await process_frame
	card.queue_free()
	Cosmetics.set_room_skins("", "")
	if Cosmetics.shown_card_back() != "back_classic" or Cosmetics.shown_table() != "table_green":
		push_error("leaving the room restores your own skins")
		failures += 1

	var stats_script = load("res://scripts/ui/stats_panel.gd")
	var locked: String = stats_script.describe({"plus": false, "games": 4, "wins": 1})
	var full: String = stats_script.describe({"plus": true, "games": 4, "wins": 1, "winRate": 25, "averageScore": 12.5, "bestScore": 20, "podiums": 3, "peopleGames": 2,
		"majorities": [0, 2, 0, 0, 1, 0], "recent": [{"rank": 2}, {"rank": 1}]})
	if not locked.begins_with("4 games, 1 wins") or not locked.contains("Plus shows"):
		push_error("without Plus the stats show games and wins and what Plus adds, got '%s'" % locked)
		failures += 1
	if not full.contains("(25%)") or not full.contains("Foods 2") or not full.contains("#2 #1"):
		push_error("Plus stats should show the breakdown, got '%s'" % full)
		failures += 1

	var shop = load("res://scripts/ui/shop_panel.gd").new()
	root.add_child(shop)
	await process_frame
	var catalog := {"configured": true, "owned": [], "skins": [], "unlocks": [
		{"id": "designer", "name": "Designer", "productId": "bb_designer", "owned": false},
		{"id": "plus", "name": "Plus", "productId": "bb_plus_monthly", "owned": false}]}
	shop.apply_catalog(catalog)
	if shop._plus_box.visible:
		push_error("Plus stays hidden while Remote Config does not offer it")
		failures += 1
	RemoteConfig.apply({"plusEnabled": true})
	shop.apply_catalog(catalog)
	await process_frame
	if not shop._plus_box.visible or shop._plus_button.text != "Subscribe" or not shop._plus_button.disabled:
		push_error("offered Plus shows Subscribe, disabled without the store plugin")
		failures += 1
	failures += _check_button_sizes(shop, "shop with Plus")
	RemoteConfig.reset()
	catalog["owned"] = ["plus"]
	catalog["unlocks"][1]["owned"] = true
	shop.apply_catalog(catalog)
	if not shop._plus_box.visible or shop._plus_button.text != "Plus active":
		push_error("a member always sees Plus as active")
		failures += 1
	shop.queue_free()

	var panel = load("res://scripts/ui/designer_panel.gd").new()
	panel.size = Vector2(672, 1100)
	root.add_child(panel)
	await process_frame
	var empty := {"back": null, "backStatus": null, "art": [null, null, null, null, null, null], "artStatus": [null, null, null, null, null, null]}
	var decks := []
	for i in 10:
		decks.append(empty)
	panel.apply_state({"enabled": true, "owned": true, "plus": true, "publicDeck": true, "slots": 10, "blocker": "", "decks": decks, "active": 0})
	await process_frame
	var shown: int = panel._slot_buttons.filter(func(b): return b.visible).size()
	if shown != 10 or not panel._public_toggle.visible or not panel._public_toggle.button_pressed:
		push_error("Plus shows ten decks and the quick play switch (got %d decks)" % shown)
		failures += 1
	failures += _check_button_sizes(panel, "designer with Plus")
	panel.apply_state({"enabled": true, "owned": true, "plus": false, "slots": 3, "blocker": "", "decks": [empty, empty, empty], "active": -1})
	if panel._public_toggle.visible:
		push_error("the quick play switch is Plus only")
		failures += 1
	panel.queue_free()
	Cosmetics.reset()
	return failures


func _club_checks() -> int:
	var failures := 0
	var api = load("res://scripts/net/clubs_api.gd")
	if api.ADJECTIVES.size() != 16 or api.NOUNS.size() != 16:
		push_error("club word lists must match the server's 16 + 16 words")
		failures += 1
	var panel_script = load("res://scripts/ui/clubs_panel.gd")
	var panel = panel_script.new()
	panel.size = Vector2(672, 1100)
	root.add_child(panel)
	panel.apply_state({"club": null, "league": [], "max": 30}, {"clubs": [{"id": "c1", "name": "Bold Ventures 7", "count": 3, "max": 30}]})
	await process_frame
	var texts := _texts(panel)
	if not texts.has("Start club") or not texts.has("Join") or not texts.has("Bold Ventures 7  3/30"):
		push_error("without a club the panel offers start and join, got %s" % [texts])
		failures += 1
	failures += _small_buttons(panel, "clubs (no club)")
	panel.apply_state({"club": {"id": "c1", "name": "Bold Ventures 7", "role": "owner", "rank": 2, "score": 40,
		"members": [{"userId": "u2", "name": "bob", "role": "member", "week": 25}, {"userId": "u1", "name": "alice", "role": "owner", "week": 15}]},
		"league": [{"id": "c9", "name": "Grand Guild 3", "score": 60, "rank": 1}, {"id": "c1", "name": "Bold Ventures 7", "score": 40, "rank": 2}], "max": 30})
	await process_frame
	texts = _texts(panel)
	if not texts.has("40 points this week, place 2 in the league. 2 of 30 members.") or not texts.has("Remove") or not texts.has("2. Bold Ventures 7  40") or not texts.has("Leave club"):
		push_error("in a club the panel shows members, points and the league, got %s" % [texts])
		failures += 1
	failures += _small_buttons(panel, "clubs (member)")
	if panel_script._may_remove("admin", "admin") or not panel_script._may_remove("owner", "admin"):
		push_error("club remove rules should match the server")
		failures += 1
	panel.queue_free()
	return failures


## Every label and button text under a node.
func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for c in node.find_children("*", "", true, false):
		if c is Label or c is Button:
			out.append(String(c.text))
	return out


## Visible buttons shorter than the 48 px touch target.
func _small_buttons(node: Node, what: String) -> int:
	var bad := 0
	for c in node.find_children("*", "BaseButton", true, false):
		if c.is_visible_in_tree() and c.size.y < 48:
			push_error("%s: button '%s' is %d px tall" % [what, String(c.get("text")), int(c.size.y)])
			bad += 1
	return bad


## A watcher's view (no seat): the table shows every seat as an opponent,
## no hand and no move buttons.
func _watch_checks() -> int:
	var failures := 0
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var v := {
		"you": null,
		"seats": [
			{"id": "a", "name": "Ana", "isBot": false, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
			{"id": "b", "name": "Broker Bo", "isBot": true, "connected": true, "handCount": 3, "portfolio": [], "bronze": 10, "gold": 0, "tokens": []},
		],
		"market": [], "supplyCount": 31, "removedCount": 5, "active": 0, "phase": "take", "turn": 1,
		"tookCompany": null, "tokens": [null, null, null, null, null, null], "seq": 0, "deadline": 0,
		"drawCost": null, "legal": [], "result": null,
	}
	table._on_view(v)
	await process_frame
	if table._me_view.visible:
		push_error("a watcher has no seat of their own")
		failures += 1
	for b in table.find_children("*", "Button", true, false):
		if b is CardView and b.is_visible_in_tree() and b.face_up and b.selectable:
			push_error("a watcher must have no playable cards")
			failures += 1
			break
	if not String(table._prompt.text).begins_with("Watching."):
		push_error("a watcher's prompt says they are watching, got '%s'" % table._prompt.text)
		failures += 1
	table.queue_free()
	return failures
