extends SceneTree
## Renders the lobby's panels and sheets and the table's dialogs with fake
## data and saves PNGs, to check text and layout by eye.
## Needs a display (use xvfb-run on Linux):
##   xvfb-run -a godot --rendering-driver opengl3 --path client --script res://tests/screenshot_panels.gd -- out_dir
## Output: quests.png, quests_looks.png, shop.png, clubs_start.png, clubs_member.png,
## friends.png, friend_menu.png, designer.png, designer_editor.png,
## stats.png, season.png, season_full.png, join.png, more.png, room.png,
## waiting.png, notice.png, emotes.png, reconnect.png, seat_menu.png,
## long_names.png, friends_long.png, notch.png.
## After the folder: a locale ("en" is the default; the layout stays left
## to right in every locale), then the screen's height in px (1560 by
## default; 1280 is the shortest phone the layout serves).


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "screenshots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		TranslationServer.set_locale(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tall := int(args[2]) if args.size() > 2 else 1560
	root.get_window().size = Vector2i(720, tall)
	root.size = Vector2i(720, tall)
	await process_frame

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._apply_progress({"xp": 120, "level": 2, "gamesPlayed": 3, "wins": 1, "streak": 4}, true)
	# A named player, without touching the settings file: with `named`
	# already set, `_set_named` only shows the name.
	var net: Node = root.get_node("Net")
	net.display_name = "Tal"
	net.named = true
	main._set_named(true)
	await _settle()
	for b in main._buttons:
		b.disabled = false
	main._status.text = "Connected as Tal"

	main._quests_panel.apply_profile(_profile())
	main._quests_panel.visible = true
	await _shot(out_dir, "quests")
	main._quests_panel.select_tab(1, false)
	await _shot(out_dir, "quests_looks")
	main._quests_panel.visible = false

	var shop = main._shop_panel
	shop.visible = true
	shop.apply_catalog({
		"configured": true, "owned": ["table_walnut"],
		"skins": [
			{"id": "back_gilded", "slot": "cardBack", "name": "Gilded", "productId": "bb_skin_back_gilded", "owned": false},
			{"id": "back_blueprint", "slot": "cardBack", "name": "Blueprint", "productId": "bb_skin_back_blueprint", "owned": false},
			{"id": "table_walnut", "slot": "table", "name": "Walnut", "productId": "bb_skin_table_walnut", "owned": true},
		],
		"unlocks": [{"id": "plus", "productId": "bb_plus_monthly", "owned": false}],
	})
	shop._apply_plus([{"id": "plus", "productId": "bb_plus_monthly", "owned": false}])
	await _shot(out_dir, "shop")

	shop._deed_panel.visible = false
	shop.stats_panel.visible = true
	shop.stats_panel.apply({"plus": true, "games": 42, "wins": 11, "winRate": 26.2, "averageScore": 14.3, "bestScore": 27,
		"podiums": 30, "peopleGames": 18, "majorities": [4, 9, 2, 7, 1, 12], "recent": [{"rank": 1}, {"rank": 3}, {"rank": 2}, {"rank": 5}, {"rank": 1}]})
	await _shot(out_dir, "stats")
	shop.stats_panel.visible = false

	shop.designer_panel.visible = true
	var empty_deck := {"back": null, "backStatus": null, "art": [null, null, null, null, null, null], "artStatus": [null, null, null, null, null, null]}
	var deck0 := {"back": "abc", "backStatus": "pending", "art": [null, "def", null, null, null, null], "artStatus": [null, "approved", null, null, null, null]}
	shop.designer_panel.apply_state({"enabled": true, "owned": true, "slots": 3, "blocker": "", "decks": [deck0, empty_deck, empty_deck], "active": 0})
	await _shot(out_dir, "designer")
	var picture := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	picture.fill(Color("#5B8DEF"))
	shop.designer_panel.open_editor(picture, "back")
	await _shot(out_dir, "designer_editor")
	shop.designer_panel.close_editor()
	shop.designer_panel.visible = false
	shop._deed_panel.visible = true
	shop.visible = false

	var clubs = main._clubs_panel
	clubs.visible = true
	clubs.apply_state({"club": null, "league": [], "max": 30}, {"clubs": [{"id": "c1", "name": "Bold Ventures 7", "count": 3, "max": 30}, {"id": "c2", "name": "Grand Guild 3", "count": 29, "max": 30}]})
	await _shot(out_dir, "clubs_start")
	clubs.apply_state({"club": {"id": "c1", "name": "Bold Ventures 7", "role": "owner", "rank": 2, "score": 40,
		"members": [{"userId": "u2", "name": "bob", "role": "member", "week": 25}, {"userId": "u1", "name": "alice", "role": "owner", "week": 15}]},
		"league": [{"id": "c9", "name": "Grand Guild 3", "score": 60, "rank": 1}, {"id": "c1", "name": "Bold Ventures 7", "score": 40, "rank": 2}], "max": 30})
	await _shot(out_dir, "clubs_member")
	clubs.visible = false

	main._friends_sheet.visible = true
	await _settle()
	main._friends_panel.room_code = "ABC123"
	main._friends_panel.set_friends([
		{"userId": "u-bo", "name": "Bo", "online": true, "state": 0},
		{"userId": "u-cara", "name": "Cara-with-a-long-name", "online": false, "state": 2},
		{"userId": "u-dev", "name": "Dev", "online": false, "state": 1},
	])
	main._friends_panel.set_extras({"waiting": 2, "names": ["Cara", "Dev"], "claimLeft": 5, "sentToday": [], "sendLeft": 9, "points": 5}, ["u-bo"])
	main._friends_panel.show_invite("Cara", "XYZ789")
	main._friends_panel._status.text = "Request sent to Dev. You're friends once they add you back."
	await _shot(out_dir, "friends")
	var bo_row: Control = main._friends_panel._list.get_child(0).get_child(0)
	bo_row.get_child(bo_row.get_child_count() - 1).pressed.emit()
	await _shot(out_dir, "friend_menu")
	main._friends_panel._row_menu.hide()
	# A list longer than the screen: it scrolls, with a bar.
	var many := []
	for i in 15:
		many.append({"userId": "u-%d" % i, "name": ["Maximilian-Alexa", "Bo", "אבישג", "W"][i % 4], "online": i % 2 == 0, "state": 0})
	main._friends_panel.set_friends(many)
	await _shot(out_dir, "friends_long")
	main._friends_sheet.visible = false

	main._season_sheet.visible = true
	var board := [
		{"rank": 1, "name": "Maya", "score": 310, "wins": 9, "userId": "a"},
		{"rank": 2, "name": "Tal", "score": 245, "wins": 7, "userId": "me", "mine": true},
		{"rank": 3, "name": "Noa", "score": 190, "wins": 5, "userId": "c"},
		{"rank": 4, "name": "Maximilian the Third", "score": 120, "wins": 2, "userId": "d"},
	]
	main._show_board_rows(board, "me")
	await _shot(out_dir, "season")
	# The longest board the server sends: ten places and your own after a gap.
	var full := []
	for i in 10:
		full.append({"rank": i + 1, "name": "Player %d" % (i + 1), "score": 400 - i * 30, "wins": 12 - i, "userId": "u%d" % i})
	full.append({"rank": 57, "name": "Tal", "score": 12, "wins": 1, "userId": "me", "mine": true})
	main._show_board_rows(full, "me")
	await _shot(out_dir, "season_full")
	main._season_sheet.visible = false

	main._join_sheet.visible = true
	main._code_edit.text = "ABC"
	await _shot(out_dir, "join")
	main._join_sheet.visible = false

	main._more_sheet.visible = true
	main._link_row.visible = true
	main._link_apple_button.visible = true
	main._link_google_button.visible = true
	await _shot(out_dir, "more")
	main._more_sheet.visible = false

	# Waiting in a private room.
	main._room_code = "ABC123"
	main._room_label.text = "Room code  ABC123"
	main._room_row.visible = true
	main._ready_button.visible = true
	main._on_lobby({"isPrivate": true, "maxSeats": 5, "seats": [{"name": "Tal", "ready": true}, {"name": "Maya", "ready": false}], "startsAt": 0})
	main._status.text = "Share the code with a friend"
	await _shot(out_dir, "room")
	main.queue_free()

	# Table dialogs.
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var view := _view()
	view["active"] = 1
	view["legal"] = []
	view["drawCost"] = null
	table._on_view(view)
	await _settle()
	table._action_note = "Broker Bo draws from the supply and pays 2 capital onto the Market."
	table._update_prompt()
	await _shot(out_dir, "waiting")
	table._show_notice("Bo forfeited. A bot plays their seat.")
	await _settle()
	await _shot(out_dir, "notice")
	table._notice.visible = false
	table._toggle_emote_bar()
	await _shot(out_dir, "emotes")
	table._toggle_emote_bar()
	table._on_reconnecting(2)
	await _shot(out_dir, "reconnect")
	table._reconnect_overlay.visible = false
	table._on_seat_pressed(2, Vector2(700, 260))
	await _shot(out_dir, "seat_menu")
	table._seat_menu.hide()
	table.queue_free()

	# Worst-case text: long names, big counts, a full Market.
	var crowded = load("res://scenes/table.tscn").instantiate()
	root.add_child(crowded)
	await process_frame
	var hard := _view()
	hard["seats"][0]["portfolio"] = [{"id": 60, "company": 0}, {"id": 61, "company": 0}, {"id": 62, "company": 0}, {"id": 63, "company": 0}, {"id": 64, "company": 1}, {"id": 65, "company": 3}]
	hard["seats"][0]["bronze"] = 128
	hard["seats"][0]["gold"] = 12
	hard["seats"][1]["name"] = "Maximilian-Alexander"
	hard["seats"][2]["name"] = "אבישג"
	hard["seats"][2]["bronze"] = 104
	hard["seats"][2]["gold"] = 23
	hard["seats"][3]["name"] = "W"
	hard["seats"].append({"id": "f", "name": "Investor Ines", "isBot": true, "connected": true, "handCount": 3, "portfolio": [{"id": 30, "company": 0}, {"id": 31, "company": 1}, {"id": 32, "company": 2}, {"id": 33, "company": 3}, {"id": 34, "company": 4}, {"id": 35, "company": 5}], "bronze": 3, "gold": 0, "tokens": []})
	hard["market"] = []
	for k in 9:
		hard["market"].append({"card": {"id": 40 + k, "company": k % 6}, "coins": k})
	hard["supplyCount"] = 3
	hard["active"] = 1
	hard["legal"] = []
	hard["drawCost"] = null
	crowded._on_view(hard)
	await _settle()
	await _shot(out_dir, "long_names")
	crowded.queue_free()

	# A notched phone (insets as on an iPhone 14): the strip under the top
	# bar is gone, so the notice lies on the bar's own row.
	UiTheme.insets_override = Vector2(87, 63)
	var notched = load("res://scenes/table.tscn").instantiate()
	root.add_child(notched)
	await process_frame
	notched._on_view(view)
	await _settle()
	notched._show_notice("Bo forfeited. A bot plays their seat.")
	await _settle()
	await _shot(out_dir, "notch")
	notched.queue_free()
	UiTheme.insets_override = null
	print("PANEL SCREENSHOTS OK")
	quit(0)


func _settle() -> void:
	for i in 8:
		await process_frame


func _shot(out_dir: String, name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [out_dir, name])
	print("saved %s/%s.png err=%d" % [out_dir, name, err])


func _profile() -> Dictionary:
	return {
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


func _view() -> Dictionary:
	return {
		"you": 0,
		"seats": [
			{"id": "a", "name": "Tal", "isBot": false, "connected": true, "handCount": 3,
			 "hand": [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}],
			 "portfolio": [{"id": 9, "company": 5}, {"id": 10, "company": 5}, {"id": 11, "company": 3}], "bronze": 7, "gold": 0, "tokens": [5]},
			{"id": "b", "name": "Broker Bo", "isBot": true, "connected": true, "handCount": 3,
			 "portfolio": [{"id": 12, "company": 2}, {"id": 13, "company": 2}], "bronze": 10, "gold": 0, "tokens": [2]},
			{"id": "c", "name": "Maya", "isBot": false, "connected": true, "handCount": 3,
			 "portfolio": [{"id": 14, "company": 0}, {"id": 15, "company": 1}], "bronze": 12, "gold": 0, "tokens": [0]},
			{"id": "d", "name": "Analyst Avi", "isBot": true, "connected": true, "handCount": 3,
			 "portfolio": [{"id": 16, "company": 4}, {"id": 17, "company": 4}, {"id": 18, "company": 1}], "bronze": 8, "gold": 0, "tokens": [4]},
			{"id": "e", "name": "Noa", "isBot": false, "connected": false, "handCount": 3,
			 "portfolio": [{"id": 19, "company": 1}], "bronze": 9, "gold": 0, "tokens": []},
		],
		"market": [{"card": {"id": 20, "company": 1}, "coins": 2}, {"card": {"id": 21, "company": 5}, "coins": 0}, {"card": {"id": 22, "company": 2}, "coins": 3}],
		"supplyCount": 14, "removedCount": 5, "active": 0, "phase": "take", "turn": 11,
		"tookCompany": null, "tokens": [2, null, 1, null, 3, 0], "seq": 20,
		"deadline": Time.get_unix_time_from_system() * 1000.0 + 21000.0,
		"drawCost": 2,
		"legal": [{"type": "take_supply"}, {"type": "take_market", "cardId": 20}, {"type": "take_market", "cardId": 22}],
		"result": null,
	}
