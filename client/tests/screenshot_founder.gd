extends SceneTree
## Renders the Founder screen (locked, the studio with custom companies,
## an under-13 player, the logo crop) and a table whose host has custom
## companies, from fixtures, with no server. Needs a display:
##   xvfb-run -a godot --rendering-driver opengl3 --path client --script res://tests/screenshot_founder.gd -- <ABSOLUTE out_dir> [height]
## Output: founder_locked.png, founder_studio.png, founder_young.png,
## founder_crop.png, founder_table.png, founder_logos.png.

const CUSTOM := [
	null,
	{"name": "Leafline Grocers", "color": "lime", "logo": "leaf", "picture": null},
	{"name": "Rocket Mail", "color": "teal", "logo": "rocket", "picture": null},
	null,
	{"name": "Crown & Co.", "color": "pink", "logo": "crown", "picture": null},
	{"name": "Summit Outdoors", "color": "navy", "logo": "mountain", "picture": null},
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "screenshots"
	var height := int(args[1]) if args.size() > 1 else 1280
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.get_window().size = Vector2i(720, height)
	await process_frame
	var bg := ColorRect.new()
	bg.color = UiTheme.NIGHT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var panel_script = load("res://scripts/ui/founder_panel.gd")
	var panel: PanelContainer = panel_script.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = 60
	panel.offset_bottom = -40
	panel.theme = UiTheme.get_theme()
	root.add_child(panel)

	panel.apply_state({"enabled": true, "owned": false, "productId": "bb_founder", "companies": [null, null, null, null, null, null]})
	await _settle()
	await _save(out_dir + "/founder_locked.png")

	var companies := []
	for c in CUSTOM:
		companies.append(null if c == null else {"name": c["name"], "color": c["color"], "logo": c["logo"], "picture": null, "pictureStatus": null})
	var owned := {"enabled": true, "owned": true, "productId": "bb_founder", "uploadBlocker": "", "companies": companies, "active": true}
	panel.apply_state(owned)
	panel.select_company(2)
	await _settle()
	await _save(out_dir + "/founder_studio.png")

	var young := owned.duplicate()
	young["uploadBlocker"] = "too_young"
	panel.apply_state(young)
	panel.select_company(0)
	await _settle()
	await _save(out_dir + "/founder_young.png")

	panel.apply_state(owned)
	panel.select_company(2)
	var img := Image.create(400, 300, false, Image.FORMAT_RGB8)
	img.fill(Color("#203040"))
	img.fill_rect(Rect2i(120, 60, 160, 160), Color("#F2C230"))
	img.fill_rect(Rect2i(170, 110, 60, 60), Color("#D6262C"))
	panel.open_crop(img)
	await _settle()
	await _save(out_dir + "/founder_crop.png")
	panel.queue_free()
	bg.queue_free()

	# Every drawn logo, in each standard colour, to check the drawings.
	var sheet := Control.new()
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)
	var sheet_bg := ColorRect.new()
	sheet_bg.color = Companies.CARD_FACE
	sheet_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(sheet_bg)
	var canvas := Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(func() -> void:
		var logos: Array = Companies.LOGOS
		for i in logos.size():
			var col := i % 4
			var row := i / 4
			var c := Vector2(100 + col * 170, 90 + row * 170)
			var cid: String = Companies.PALETTE_ORDER[i % Companies.PALETTE_ORDER.size()]
			CompanyLogos.draw(canvas, logos[i], c, 120, Companies.PALETTE[cid])
			canvas.draw_string(UiTheme.ui_font(), c + Vector2(-50, 80), logos[i], HORIZONTAL_ALIGNMENT_CENTER, 100, 18, Companies.INK))
	sheet.add_child(canvas)
	await _settle()
	await _save(out_dir + "/founder_logos.png")
	sheet.queue_free()

	# A table in a room whose host has custom companies.
	Companies.set_room_companies(CUSTOM)
	var table = load("res://scenes/table.tscn").instantiate()
	root.add_child(table)
	await process_frame
	table._on_view(_fake_view())
	await _settle()
	await _save(out_dir + "/founder_table.png")
	quit(0)


func _settle() -> void:
	for i in 12:
		await process_frame


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


## Copied from screenshot.gd (a SceneTree script cannot be called from here).
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
