extends SceneTree
## Scratch tester script (not part of the feature).

func _init() -> void:
	_run.call_deferred()

func _cfg_case(net: Node, label: String, text: String) -> void:
	var f := FileAccess.open("user://net.cfg", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	net.bot_count = -99
	net._load_settings()
	print("CFG %s -> bot_count=%s name=%s" % [label, net.bot_count, net.display_name])

func _run() -> void:
	await process_frame
	var net: Node = root.get_node("Net")
	print("FRESH bot_count=", net.bot_count)
	var old := "[player]\nname=\"Tal\"\nnamed=true\n"
	_cfg_case(net, "old-no-play-section", old)
	_cfg_case(net, "bots=3", old + "[play]\nbots=3\n")
	_cfg_case(net, "bots=4", old + "[play]\nbots=4\n")
	_cfg_case(net, "bots=9", old + "[play]\nbots=9\n")
	_cfg_case(net, "bots=-1", old + "[play]\nbots=-1\n")
	_cfg_case(net, "bots=\"abc\"", old + "[play]\nbots=\"abc\"\n")
	_cfg_case(net, "bots=\"3\"", old + "[play]\nbots=\"3\"\n")
	_cfg_case(net, "bots=3.9", old + "[play]\nbots=3.9\n")
	_cfg_case(net, "bots=true", old + "[play]\nbots=true\n")
	_cfg_case(net, "bots=[1,2]", old + "[play]\nbots=[1, 2]\n")
	_cfg_case(net, "bots={}", old + "[play]\nbots={}\n")
	_cfg_case(net, "bots=null", old + "[play]\nbots=null\n")
	# round trip
	net.bot_count = 4
	net.save_settings()
	net.bot_count = 2
	net._load_settings()
	print("ROUNDTRIP 4 -> ", net.bot_count)
	print(FileAccess.get_file_as_string("user://net.cfg"))
	# main offline
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10:
		await create_timer(1.0).timeout
		if not main._connected and main._status.text != "" and not main._status.text.begins_with("Connecting"):
			pass
	print("STATUS=", main._status.text, " connected=", main._connected)
	var states := []
	for b in main._bot_buttons:
		states.append("%s disabled=%s" % [b.text, b.disabled])
	print("BOT BUTTONS (offline): ", states)
	for b in main._buttons:
		if b.text == "Vs bots":
			print("VS BOTS disabled=", b.disabled)
	net.bot_count = 4
	main._open_bots_sheet()
	var vars := []
	for b in main._bot_buttons:
		vars.append("%s:%s" % [b.text, b.theme_type_variation])
	print("HIGHLIGHT bot_count=4: ", vars, " sheet visible=", main._bots_sheet.visible)
	quit(0)
