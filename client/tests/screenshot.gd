extends SceneTree
## Renders the lobby and a mid-game table with a fake view and saves PNGs.
## Needs a display (use xvfb-run on Linux):
##   xvfb-run -a godot --rendering-driver opengl3 --path client --script res://tests/screenshot.gd -- out_dir
## Output: <out_dir>/lobby.png, help.png, table.png, play_step.png, dividend.png,
## tutorial.png, emotes.png, get_ready.png, forfeit.png, peek.png, token.png,
## then lobby_tall.png, lobby_more.png, table_tall.png and coach_tall.png at
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
	tall._name_edit.text = "Tal"
	tall._on_name_changed("Tal")
	await _settle()
	for b in tall._buttons:
		b.disabled = false
	tall._status.text = "Connected as Tal"
	await _settle()
	await _save(out_dir + "/lobby_tall.png")
	var scroll: ScrollContainer = tall.find_children("*", "ScrollContainer", false, false)[0]
	scroll.scroll_vertical = 100000
	await _settle()
	await _save(out_dir + "/lobby_more.png")
	tall.queue_free()
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
	print("SCREENSHOTS OK")
	quit(0)


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
