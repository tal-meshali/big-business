extends SceneTree
## Renders the lobby and a mid-game table with a fake view and saves PNGs.
## Needs a display (use xvfb-run on Linux):
##   xvfb-run -a godot --rendering-driver opengl3 --path client --script res://tests/screenshot.gd -- out_dir
## Output: <out_dir>/lobby.png, help.png, table.png, play_step.png, dividend.png,
## tutorial.png, emotes.png, get_ready.png, forfeit.png, peek.png, token.png,
## then lobby_tall.png, lobby_more.png (the More sheet), table_tall.png and coach_tall.png at
## 720x1560 (a 19.5:9 phone).
## Add "he" after the folder to run under a Hebrew (right-to-left) locale:
##   ... --script res://tests/screenshot.gd -- out_dir he


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
	root.get_window().size = Vector2i(720, 1280)
	await process_frame
	# The name shots change what the settings file holds; put it back after.
	var settings: Node = root.get_node("Net")
	var previous_name: String = settings.display_name
	var previous_named: bool = settings.named

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	await _save(out_dir + "/lobby.png")
	main._on_help()
	await _settle()
	await _save(out_dir + "/help.png")
	main.queue_free()

	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var view := _fake_view()
	table._on_view(view)
	await _settle()
	await _save(out_dir + "/table.png")
	table._stamp_token.call_deferred(int(view["you"]), 2)
	await create_timer(0.35).timeout
	await _save(out_dir + "/token.png")
	await create_timer(2.8).timeout

	view["phase"] = "play"
	view["tookCompany"] = 2
	view["drawCost"] = null
	view["legal"] = [{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3}, {"type": "play_market", "cardId": 1}, {"type": "play_market", "cardId": 3}]
	table._on_view(view)
	await process_frame
	table._on_hand_card_pressed(2)
	await _settle()
	await _save(out_dir + "/play_step.png")

	view["phase"] = "ended"
	view["legal"] = []
	view["result"] = {
		"companies": [
			{"company": 0, "majority": 2, "payments": [{"from": 0, "to": 2, "coins": 1}]},
			{"company": 1, "majority": null, "payments": []},
			{"company": 2, "majority": 1, "payments": [{"from": 0, "to": 1, "coins": 2}, {"from": 3, "to": 1, "coins": 1}]},
			{"company": 3, "majority": 0, "payments": [{"from": 2, "to": 0, "coins": 2}]},
			{"company": 4, "majority": 3, "payments": [{"from": 4, "to": 3, "coins": 3}]},
			{"company": 5, "majority": 0, "payments": [{"from": 1, "to": 0, "coins": 2}, {"from": 4, "to": 0, "coins": 1}]},
		],
		"scores": [
			{"seat": 0, "bronze": 6, "gold": 5, "score": 21, "rank": 1},
			{"seat": 1, "bronze": 8, "gold": 3, "score": 17, "rank": 2},
			{"seat": 2, "bronze": 9, "gold": 1, "score": 12, "rank": 3},
			{"seat": 3, "bronze": 8, "gold": 3, "score": 17, "rank": 2},
			{"seat": 4, "bronze": 6, "gold": 0, "score": 6, "rank": 5},
		],
	}
	table._on_view(view)
	await _settle()
	await _save(out_dir + "/dividend.png")
	table.queue_free()

	# Tutorial coach card over the opening position.
	var net: Node = root.get_node("Net")
	net.tutorial_mode = true
	var tutorial = load("res://scenes/table.tscn").instantiate()
	root.add_child(tutorial)
	tutorial.enable_coach()
	await process_frame
	var opening := _fake_view()
	opening["market"] = []
	opening["drawCost"] = 0
	opening["legal"] = [{"type": "take_supply"}]
	for seat in opening["seats"]:
		seat["portfolio"] = []
		seat["tokens"] = []
		seat["bronze"] = 10
	opening["seats"] = opening["seats"].slice(0, 3)
	opening["supplyCount"] = 31
	opening["turn"] = 1
	opening["deadline"] = 0
	tutorial._on_view(opening)
	await _settle()
	await _save(out_dir + "/tutorial.png")
	tutorial.queue_free()
	net.tutorial_mode = false

	# Emote bar open and bubbles on two opponents.
	var social = load("res://scenes/table.tscn").instantiate()
	root.add_child(social)
	await process_frame
	var mid := _fake_view()
	mid["active"] = 1
	mid["drawCost"] = null
	mid["legal"] = []
	social._on_view(mid)
	await _settle()
	social._on_emote_shown(1, "good_move")
	social._on_emote_shown(3, "wave")
	social._toggle_emote_bar()
	await _settle()
	await _save(out_dir + "/emotes.png")
	social.queue_free()

	# Get-ready countdown over the opening deal.
	var start = load("res://scenes/table.tscn").instantiate()
	root.add_child(start)
	await process_frame
	var first := _fake_view()
	first["market"] = []
	first["drawCost"] = null
	first["legal"] = []
	for seat in first["seats"]:
		seat["portfolio"] = []
		seat["tokens"] = []
		seat["bronze"] = 10
		seat["connected"] = true
	first["active"] = 1
	first["turn"] = 1
	first["supplyCount"] = 25
	first["startsInMs"] = 2500
	start._on_view(first)
	await _settle()
	await _save(out_dir + "/get_ready.png")

	# Forfeit confirmation.
	first["startsInMs"] = 0
	start._on_view(first)
	await create_timer(0.8).timeout
	start._on_leave_pressed()
	await _settle()
	await _save(out_dir + "/forfeit.png")
	start.queue_free()

	# Holding a hand card shows it up close.
	var peek = load("res://scenes/table.tscn").instantiate()
	root.add_child(peek)
	await process_frame
	var play := _fake_view()
	play["phase"] = "play"
	play["tookCompany"] = 1
	play["seats"][0]["hand"] = [{"id": 1, "company": 0}, {"id": 2, "company": 3}, {"id": 3, "company": 5}, {"id": 20, "company": 1}]
	play["market"] = play["market"].slice(1)
	play["legal"] = [{"type": "play_portfolio", "cardId": 1}, {"type": "play_portfolio", "cardId": 2}, {"type": "play_portfolio", "cardId": 3}, {"type": "play_portfolio", "cardId": 20}]
	peek._on_view(play)
	await _settle()
	peek._on_card_held(peek._hand_cards[2])
	for i in 20:
		await process_frame
	await _save(out_dir + "/peek.png")
	peek.queue_free()

	# A tall phone: the start screen, scrolled to the bottom, and the table.
	root.get_window().size = Vector2i(720, 1560)
	root.size = Vector2i(720, 1560)
	await process_frame
	var tall = load("res://scenes/main.tscn").instantiate()
	root.add_child(tall)
	tall._apply_progress({"xp": 120, "level": 2, "gamesPlayed": 3, "wins": 1, "streak": 4}, true)
	tall._status.text = "Connected as Tal"
	net.display_name = "Tal"
	tall._set_named(true)
	await _settle()
	for b in tall._buttons:
		b.disabled = false
	tall._status.text = "Connected as Tal"
	await _settle()
	await _save(out_dir + "/lobby_tall.png")
	tall._more_sheet.visible = true
	await _settle()
	await _save(out_dir + "/lobby_more.png")
	tall._more_sheet.visible = false
	await _profile_shots(tall, out_dir, "_tall")
	tall.queue_free()
	await process_frame
	# The same screens on a 16:9 phone, where the record scrolls under the card.
	root.get_window().size = Vector2i(720, 1280)
	root.size = Vector2i(720, 1280)
	await process_frame
	var short = load("res://scenes/main.tscn").instantiate()
	root.add_child(short)
	short._show_name()
	await _settle()
	await _profile_shots(short, out_dir, "")
	short.queue_free()
	root.get_window().size = Vector2i(720, 1560)
	root.size = Vector2i(720, 1560)
	await process_frame
	var big = load("res://scenes/table.tscn").instantiate()
	root.add_child(big)
	await process_frame
	var four := _fake_view()
	four["seats"] = four["seats"].slice(0, 4)
	big._on_view(four)
	await _settle()
	await _save(out_dir + "/table_tall.png")
	big.queue_free()
	net.tutorial_mode = true
	var coached = load("res://scenes/table.tscn").instantiate()
	root.add_child(coached)
	coached.enable_coach()
	await process_frame
	coached._on_view(opening)
	await _settle()
	coached.coach._on_got_it()
	await _settle()
	await _save(out_dir + "/coach_tall.png")
	coached.queue_free()
	net.tutorial_mode = false
	net.display_name = previous_name
	net.named = previous_named
	net.save_settings()
	print("SCREENSHOTS OK")
	quit(0)


## The profile (a regular player, a Plus member, a brand-new player and
## worst-case data) and the name step (first launch, and a refused name).
func _profile_shots(lobby, out_dir: String, suffix: String) -> void:
	var net: Node = root.get_node("Net")
	var panel = lobby._profile_panel
	var regular := {"xp": 1240, "level": 5, "gamesPlayed": 42, "wins": 11, "streak": 4, "bestRank": 1}
	lobby._apply_progress(regular, false)
	lobby._open_profile()
	panel.apply_season([{"userId": "me", "name": "Tal", "score": 84, "rank": 12, "wins": 6, "mine": true}])
	panel.apply_club({"club": {"name": "Golden Partners 412"}})
	panel.apply_account({"device": true, "username": "Tal", "named": true})
	panel._account_label.text = "Guest account (device)"
	panel._rename_button.disabled = false
	await create_timer(1.3).timeout
	await _save(out_dir + "/profile%s.png" % suffix)
	panel.card.flip()
	await create_timer(0.6).timeout
	await _save(out_dir + "/profile_back%s.png" % suffix)
	panel.card.flip()
	await create_timer(0.5).timeout

	panel.apply_stats({"plus": true, "games": 40, "wins": 11, "podiums": 27, "bestScore": 31, "peopleGames": 30, "averageScore": 14.2, "winRate": 27.5,
		"majorities": [9, 4, 12, 7, 0, 15], "recent": [{"rank": 1}, {"rank": 3}, {"rank": 2}, {"rank": 2}, {"rank": 5}, {"rank": 1}, {"rank": 4}, {"rank": 3}, {"rank": 1}, {"rank": 2}]})
	await _settle()
	await _save(out_dir + "/profile_plus%s.png" % suffix)
	panel._scroll.scroll_vertical = 100000
	await _settle()
	await _save(out_dir + "/profile_plus_end%s.png" % suffix)
	panel._scroll.scroll_vertical = 0

	# Worst case: the longest name, a long club, huge counts, level 120.
	net.display_name = "WWWWWWWWWWWWWWWW"
	lobby._show_name()
	lobby._apply_progress({"xp": 720000, "level": 121, "gamesPlayed": 1234567, "wins": 987654, "streak": 3650, "bestRank": 1}, true)
	panel.refresh_name()
	panel.apply_stats({"plus": true, "games": 1234567, "wins": 987654, "podiums": 1111111, "bestScore": 99999, "peopleGames": 1000000, "averageScore": 12345.6, "winRate": 100,
		"majorities": [123456, 99999, 1234, 12, 0, 7654321], "recent": [{"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}, {"rank": 7}]})
	panel.apply_season([{"userId": "me", "score": 9999999, "rank": 1234567, "mine": true}])
	panel.apply_club({"club": {"name": "Northern Collective 99999"}})
	await _settle()
	await _save(out_dir + "/profile_worst%s.png" % suffix)
	lobby._profile_panel.close()
	await create_timer(0.3).timeout
	await _save(out_dir + "/lobby_worst%s.png" % suffix)

	# A brand-new player, and a name in Hebrew.
	net.display_name = "טל"
	lobby._show_name()
	lobby._apply_progress({"xp": 0, "level": 1, "gamesPlayed": 0, "wins": 0, "streak": 0, "bestRank": 0}, true)
	lobby._open_profile()
	panel.apply_stats({"plus": false, "games": 0, "wins": 0})
	panel.apply_season([])
	panel.apply_club({"club": null, "league": []})
	await create_timer(1.3).timeout
	await _save(out_dir + "/profile_new%s.png" % suffix)
	lobby._profile_panel.close()
	await create_timer(0.3).timeout

	# The name step at first launch, empty, typed, and refused.
	net.display_name = "NmnqzZdeZg"
	lobby._show_name()
	lobby._saved_name = ""
	lobby._ask_name_if_new({"named": false, "username": "NmnqzZdeZg"})
	await create_timer(1.0).timeout
	await _save(out_dir + "/name_first%s.png" % suffix)
	lobby._name_prompt._edit.text = "Tal"
	lobby._name_prompt._on_typed("Tal")
	await _settle()
	await _save(out_dir + "/name_typed%s.png" % suffix)
	lobby._name_prompt._show_error("That name is taken. Try another.")
	await create_timer(0.4).timeout
	await _save(out_dir + "/name_taken%s.png" % suffix)
	# The same step with a keyboard up (a grey block stands in for it).
	var keyboard := ColorRect.new()
	keyboard.color = Color("#2B2B33")
	keyboard.size = Vector2(root.size.x, roundf(root.size.y * 0.4))
	keyboard.position = Vector2(0, root.size.y - keyboard.size.y)
	root.add_child(keyboard)
	lobby._name_prompt._on_typed("Tal")
	lobby.keyboard_override = keyboard.size.y
	await create_timer(0.4).timeout
	await _save(out_dir + "/name_keyboard%s.png" % suffix)
	lobby.keyboard_override = -1.0
	keyboard.queue_free()
	await create_timer(0.2).timeout
	lobby._name_prompt._on_cancel()
	await create_timer(0.2).timeout
	lobby._set_named(true)
	lobby._name_prompt.open("Tal", false, 5)
	await create_timer(1.0).timeout
	await _save(out_dir + "/name_change%s.png" % suffix)
	lobby._name_prompt._on_cancel()
	await create_timer(0.2).timeout
	net.display_name = "Tal"
	lobby._show_name()


func _settle() -> void:
	for i in 6:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("saved ", path, " (", img.get_width(), "x", img.get_height(), ") err=", err)


func _fake_view() -> Dictionary:
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
