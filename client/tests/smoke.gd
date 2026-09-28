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
	failures += await _lobby_checks()
	failures += await _friends_checks()

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
	var first_take_view: Dictionary = v.duplicate(true)
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
	if table.coach.forced_action() != {"type": "take_supply"} or table._draw_button.disabled:
		push_error("turn 1 take: the draw must be forced and enabled, got %s" % [table.coach.forced_action()])
		failures += 1
	table.coach._on_got_it()

	# Play step (turn 1): every company held once, so the tie goes to the
	# larger company, Redline Motors (card 3), and only that card is enabled.
	v["phase"] = "play"
	v["tookCompany"] = 5
	v["drawCost"] = null
	v["legal"] = [
		{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3},
		{"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 2},
	]
	table._on_view(v)
	await process_frame
	if shown.back() != "first_play":
		push_error("first_play should fire on the first play step, got %s" % [shown])
		failures += 1
	if not table.coach._body.text.contains("Keep the Redline Motors share"):
		push_error("first_play should name the majority card, got %s" % table.coach._body.text)
		failures += 1
	if table.coach.forced_action() != {"type": "play_portfolio", "cardId": 3} or table.coach.highlight_card_id != 3:
		push_error("turn 1 play should force keeping card 3, got %s" % [table.coach.forced_action()])
		failures += 1
	for cv in table._hand_cards:
		if cv.selectable != (cv.card_id == 3):
			push_error("only the coached hand card may be selectable (card %d)" % cv.card_id)
			failures += 1
	table._on_hand_card_pressed(1)
	await process_frame
	if not table._keep_button.disabled or not table._sell_button.disabled:
		push_error("keep and sell must be disabled for a non-forced selection")
		failures += 1
	table._on_hand_card_pressed(3)
	await process_frame
	if table._keep_button.disabled or not table._sell_button.disabled:
		push_error("keep must be the only enabled play for the coached card")
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

	# My second turn (turn 4 of the game): coins in the market and a token of
	# mine blocking a share. The coach forces taking the richest share.
	v["phase"] = "take"
	v["active"] = 0
	v["turn"] = 4
	v["market"] = [{"card": {"id": 20, "company": 1}, "coins": 2}, {"card": {"id": 21, "company": 5}, "coins": 0}]
	v["seats"][0]["tokens"] = [5]
	v["seats"][0]["portfolio"] = [{"id": 3, "company": 5}]
	v["supplyCount"] = 2
	v["legal"] = [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}]
	table._on_view(v)
	# Queued events animate before the view renders; wait for that to finish.
	for i in 120:
		await process_frame
		if not table._animating and not table._pending_events.size():
			break
	await process_frame
	for id in ["endgame_near", "token_blocks", "take_with_coins", "second_take"]:
		if not table.coach.seen.has(id):
			push_error("%s should fire, seen %s" % [id, table.coach.seen.keys()])
			failures += 1
	if table.coach.forced_action() != {"type": "take_market", "cardId": 20} or not table._draw_button.disabled:
		push_error("turn 2 take should force the share with the most coins, got %s" % [table.coach.forced_action()])
		failures += 1
	var market_cards: Array = table._market_row.get_children()
	if market_cards.size() != 2 or not market_cards[0].selectable or market_cards[1].selectable:
		push_error("turn 2 take: only the coached market card may be selectable")
		failures += 1
	while table.coach.visible:
		if shown.back() == "second_take" and not table.coach._body.text.contains("Take the Pinecone Foods share and pocket its 2 coins"):
			push_error("second_take should name the share and its coins, got %s" % table.coach._body.text)
			failures += 1
		table.coach._on_got_it()
		await process_frame

	# Turn 2 play: sell a lone share that is not the company just taken;
	# Solar (card 1) and Robotics (card 2) qualify, the smaller company wins.
	v["phase"] = "play"
	v["tookCompany"] = 1
	v["market"] = [{"card": {"id": 21, "company": 5}, "coins": 0}]
	v["seats"][0]["hand"] = [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 20, "company": 1}, {"id": 30, "company": 5}]
	v["legal"] = [
		{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 20}, {"type": "play_portfolio", "cardId": 30},
		{"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 2}, {"type": "play_market", "cardId": 30},
	]
	table._on_view(v)
	await process_frame
	if shown.back() != "second_play" or not table.coach._body.text.contains("Sell the Sunny Side Solar share"):
		push_error("second_play should fire and name the lone share, got %s / %s" % [shown, table.coach._body.text])
		failures += 1
	if table.coach.forced_action() != {"type": "play_market", "cardId": 1}:
		push_error("turn 2 play should force selling card 1, got %s" % [table.coach.forced_action()])
		failures += 1
	for cv in table._hand_cards:
		if cv.selectable != (cv.card_id == 1):
			push_error("turn 2 play: only the coached hand card may be selectable (card %d)" % cv.card_id)
			failures += 1
	table._on_hand_card_pressed(1)
	await process_frame
	if not table._keep_button.disabled or table._sell_button.disabled:
		push_error("sell must be the only enabled play for the coached card")
		failures += 1
	table.coach._on_got_it()
	await process_frame
	# Same view again must not re-fire anything.
	var count_before := shown.size()
	table._on_view(v)
	await process_frame
	if shown.size() != count_before or table.coach.visible:
		push_error("steps must fire only once")
		failures += 1

	# Third turn: the guided phase is over, everything legal is enabled again.
	v["phase"] = "take"
	v["turn"] = 7
	v["tookCompany"] = null
	v["legal"] = [{"type": "take_supply"}]
	table._on_view(v)
	await process_frame
	if not table.coach.forced_action().is_empty() or table.coach.highlight_card_id != -1 or table._draw_button.disabled:
		push_error("nothing may be forced after the second turn, got %s" % [table.coach.forced_action()])
		failures += 1
	if shown.size() != count_before or table.coach.visible:
		push_error("no guided step may fire after the second turn, got %s" % [shown])
		failures += 1

	# Skip clears the guidance mid-turn.
	var solo := Coach.new()
	root.add_child(solo)
	solo.on_view(first_take_view)
	if solo.forced_action() != {"type": "take_supply"}:
		push_error("a fresh coach should force the opening draw, got %s" % [solo.forced_action()])
		failures += 1
	solo._on_skip()
	if not solo.forced_action().is_empty() or solo.highlight_card_id != -1 or not solo.allows({"type": "take_market", "cardId": 5}):
		push_error("skip should clear the forced action")
		failures += 1
	solo.queue_free()

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


## Lobby: host parsing, mute persistence, the Help screen, and the first
## "Play now" routing new players into the tutorial.
func _lobby_checks() -> int:
	var failures := 0
	var net: Node = root.get_node("Net")

	# Host field forms -> {scheme, host, port}.
	var cases := [
		["play.example.com", "http", "play.example.com", 7350],
		["play.example.com:7350", "http", "play.example.com", 7350],
		["https://play.example.com", "https", "play.example.com", 443],
		["http://127.0.0.1:7350", "http", "127.0.0.1", 7350],
		["https://play.example.com/", "https", "play.example.com", 443],
		[" HTTPS://play.example.com:8443/path ", "https", "play.example.com", 8443],
	]
	for c in cases:
		var r: Dictionary = net.parse_host_input(c[0])
		if r.get("scheme") != c[1] or r.get("host") != c[2] or r.get("port") != c[3]:
			push_error("parse_host_input(%s) gave %s" % [c[0], r])
			failures += 1
	var with_default: Dictionary = net.parse_host_input("play.example.com", "https")
	if with_default.get("scheme") != "https" or with_default.get("port") != 443:
		push_error("parse_host_input should apply the default scheme, got %s" % [with_default])
		failures += 1

	# Mute persistence round-trip through user://net.cfg.
	net.mute_player("smoke-muted", true)
	net.save_settings()
	var cfg := ConfigFile.new()
	if cfg.load(net.SETTINGS_PATH) != OK or not cfg.get_value("social", "muted", {}).has("smoke-muted"):
		push_error("muted list should be saved under [social] muted")
		failures += 1
	if cfg.get_value("player", "tutorial_done", null) == null:
		push_error("tutorial_done should be saved under [player]")
		failures += 1
	net.mute_player("smoke-muted", false)
	cfg = ConfigFile.new()
	if cfg.load(net.SETTINGS_PATH) != OK or cfg.get_value("social", "muted", {}).has("smoke-muted"):
		push_error("unmute should drop the id from the saved list")
		failures += 1
	if net.is_muted("smoke-muted"):
		push_error("unmute should clear the in-memory flag")
		failures += 1

	# Help screen: rules sections, buttons and the replay callback.
	var help: HelpScreen = HelpScreen.new()
	root.add_child(help)
	await process_frame
	var titles: PackedStringArray = help.section_titles()
	for expected in ["Goal", "A turn: take, then play", "Drawing costs coins", "The Market", "Regulator tokens", "The end and dividend day", "Timers and bots"]:
		if not titles.has(expected):
			push_error("help screen missing section %s, got %s" % [expected, titles])
			failures += 1
	for b in [help.replay_button, help.support_button, help.privacy_button, help.close_button]:
		if b == null or b.custom_minimum_size.y < 48:
			push_error("help buttons must exist with 48 px touch targets")
			failures += 1
			break
	if help.replay_button.text != "Replay the tutorial" or help.support_button.text != "Contact support" or help.privacy_button.text != "Privacy policy":
		push_error("help button labels wrong")
		failures += 1
	if not help.version_label.text.contains(AppInfo.VERSION):
		push_error("help screen should show the version")
		failures += 1
	var replayed := [false]
	help.on_replay = func() -> void: replayed[0] = true
	help.replay_button.pressed.emit()
	await process_frame
	if not replayed[0] or help.visible:
		push_error("replay button should close the help screen and call the callback")
		failures += 1
	help.queue_free()

	# First "Play now" with tutorial_done=false routes into the tutorial. No
	# server here, so only the status line is checked.
	net.tutorial_done = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await main._on_quick_play()
	if not main._status.text.contains("tutorial"):
		push_error("first Play now should start the tutorial, status was: %s" % main._status.text)
		failures += 1
	net.tutorial_done = true
	main._on_quick_play()
	if main._status.text.contains("tutorial"):
		push_error("Play now after the tutorial should look for a real game")
		failures += 1
	main._on_help()
	await process_frame
	if main._help == null or not main._help.visible:
		push_error("Help button should open the help overlay")
		failures += 1
	main._help.close_button.pressed.emit()
	if main._help.visible:
		push_error("Close should hide the help overlay")
		failures += 1
	# Secure toggle mirrors a scheme typed into the host field, and vice versa.
	main._host_edit.text = "https://play.example.com"
	main._on_host_text_changed(main._host_edit.text)
	if not main._secure_check.button_pressed:
		push_error("typing https:// should switch the secure toggle on")
		failures += 1
	main._on_secure_toggled(false)
	if main._host_edit.text != "http://play.example.com":
		push_error("toggling secure off should rewrite the scheme, got %s" % main._host_edit.text)
		failures += 1
	main.queue_free()
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
	if bo_row.get_child(3).text != "Remove":
		push_error("each friend row needs a Remove button")
		failures += 1

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
	# Empty list shows a hint instead of nothing.
	panel.set_friends([])
	if panel._list.get_child_count() != 1 or not (panel._list.get_child(0) is Label):
		push_error("empty friends list should show a hint")
		failures += 1
	panel.queue_free()
	return failures
