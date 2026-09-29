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
	failures += await _touch_checks()
	failures += await _help_checks()
	failures += await _feedback_checks()
	failures += await _forced_turn_checks()

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
