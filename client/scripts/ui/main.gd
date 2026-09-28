extends Control
## Start page, after the design canvas: a hero of floating shares over a
## small felt, the red title deed, "Your portfolio" (name, level, XP, daily
## bonus, season standings), then Play now, the tutorial, private rooms and
## the room code. The server address row sits at the bottom. Overlays:
## season standings sheet, friends, quests, help.

const P := UiTheme.SCALE

var _host_edit: LineEdit
var _secure_check: CheckButton
var _help: HelpScreen = null
var _name_edit: LineEdit
var _avatar: Label
var _code_edit: LineEdit
var _status: Label
var _lobby_label: Label
var _buttons: Array[Button] = []
var _ready_button: Button
var _copy_button: Button
var _room_row: HBoxContainer
var _room_label: Label
var _join_row: HBoxContainer
var _room_code := ""
var _profile_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _daily_button: Button
var _board_button: Button
var _board_label: Label
var _season_sheet: Control
var _friends_panel: FriendsPanel
var _quests_button: Button
var _quests_panel: QuestsPanel
var _felt: StartStage
var _room: TextureRect
var _connected := false
var _in_lobby := false


func _ready() -> void:
	_build()
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.lobby_updated.connect(_on_lobby)
	Net.view_updated.connect(_on_first_view, CONNECT_ONE_SHOT)
	Net.server_error.connect(func(m: String) -> void: _status.text = m)
	if not Net.is_connected_to_server():
		_on_connect_pressed.call_deferred()


func _px(design: float) -> float:
	return roundf(design * P)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_room = UiTheme.room_background(Cosmetics.table_bg_color())
	add_child(_room)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", int(_px(18)))
	margin.add_theme_constant_override("margin_right", int(_px(18)))
	margin.add_theme_constant_override("margin_bottom", int(_px(24)))
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_px(12)))
	margin.add_child(box)

	# Hero: floating shares over a small felt.
	_felt = StartStage.new()
	_felt.set_colors(Cosmetics.table_bg_color(), Cosmetics.table_edge_color())
	_felt.custom_minimum_size = Vector2(0, _px(StartStage.STAGE_H))
	box.add_child(_felt)

	# Title on a red deed band, like the name plate of a property board.
	var deed := UiTheme.deed_panel(Companies.ALERT, "BIG BUSINESS", Color.WHITE)
	deed["title"].add_theme_font_override("font", UiTheme.display_heavy())
	deed["title"].add_theme_font_size_override("font_size", int(_px(34)))
	var tagline := UiTheme.label("Collect shares. Corner the market. Cash in on dividend day.", 13.5, "bold")
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deed["body"].add_child(tagline)
	deed["body"].add_theme_constant_override("margin_top", int(_px(8)))
	deed["body"].add_theme_constant_override("margin_bottom", int(_px(9)))
	box.add_child(deed["panel"])

	# Profile card: name, level, XP bar, streak, daily bonus, season standings.
	var profile := UiTheme.deed_panel(Companies.CHEST, "Your portfolio", Color.WHITE)
	profile["title"].add_theme_font_size_override("font_size", int(_px(15)))
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", int(_px(9)))
	profile["body"].add_child(pbox)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", int(_px(10)))
	pbox.add_child(prow)
	_avatar = _make_avatar()
	prow.add_child(_avatar)
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", int(_px(2)))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(field)
	field.add_child(UiTheme.label("YOUR NAME", 10, "bold", Companies.CAPTION))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Pick a name"
	_name_edit.text = Net.display_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, _px(30))
	var underline := StyleBoxFlat.new()
	underline.bg_color = Color.TRANSPARENT
	underline.border_color = Companies.INK
	underline.border_width_bottom = int(_px(2))
	underline.content_margin_left = _px(2)
	underline.content_margin_right = _px(2)
	_name_edit.add_theme_stylebox_override("normal", underline)
	var underline_focus := underline.duplicate()
	underline_focus.border_color = Companies.CHEST
	_name_edit.add_theme_stylebox_override("focus", underline_focus)
	_name_edit.text_changed.connect(func(t: String) -> void: _avatar.text = t.strip_edges().substr(0, 1).to_upper())
	field.add_child(_name_edit)
	var level_box := PanelContainer.new()
	var level_style := HardBox.new(Companies.PRIMARY, _px(8), _px(2))
	level_style.border_width = _px(2)
	level_style.set_content_margin_all(_px(5))
	level_style.content_margin_left = _px(8)
	level_style.content_margin_right = _px(8)
	level_box.add_theme_stylebox_override("panel", level_style)
	level_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_label = UiTheme.label("Level 1", 13, "display")
	level_box.add_child(_profile_label)
	prow.add_child(level_box)

	var xrow := HBoxContainer.new()
	xrow.add_theme_constant_override("separation", int(_px(8)))
	pbox.add_child(xrow)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, _px(12))
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Companies.color_of(1)
	fill.set_corner_radius_all(int(_px(6)))
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#EEF0EA")
	track.border_color = Companies.INK
	track.set_border_width_all(int(_px(2)))
	track.set_corner_radius_all(int(_px(8)))
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_xp_bar.add_theme_stylebox_override("background", track)
	xrow.add_child(_xp_bar)
	_xp_label = UiTheme.label("0 / 50 XP  ·  Streak 0", 12, "bold")
	xrow.add_child(_xp_label)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", int(_px(8)))
	pbox.add_child(brow)
	_daily_button = UiTheme.button("Claim daily bonus", "", 44)
	_daily_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_button.disabled = true
	_daily_button.pressed.connect(_on_claim_daily)
	brow.add_child(_daily_button)
	_board_button = UiTheme.button("Season standings", "", 44)
	_board_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_button.disabled = true
	_board_button.pressed.connect(_on_show_board)
	brow.add_child(_board_button)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", int(_px(8)))
	pbox.add_child(srow)
	var friends_button := UiTheme.button("Friends", "", 44)
	friends_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_button.pressed.connect(func() -> void: _friends_panel.visible = not _friends_panel.visible)
	srow.add_child(friends_button)
	_quests_button = UiTheme.button("Quests & card backs", "", 44)
	_quests_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quests_button.pressed.connect(_on_toggle_quests)
	srow.add_child(_quests_button)
	var help_button := UiTheme.button("Help", "", 44)
	help_button.pressed.connect(_on_help)
	srow.add_child(help_button)
	box.add_child(profile["panel"])

	_friends_panel = FriendsPanel.new()
	_friends_panel.visible = false
	_friends_panel.join_requested.connect(_on_invite_join)
	box.add_child(_friends_panel)

	_status = UiTheme.label("Not connected", 13, "bold", Companies.CARD_FACE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	# Play.
	var play := UiTheme.button("Play now", "BigButton", 58)
	play.pressed.connect(_on_quick_play)
	play.disabled = true
	_buttons.append(play)
	box.add_child(play)
	var learn_row := HBoxContainer.new()
	learn_row.add_theme_constant_override("separation", int(_px(8)))
	box.add_child(learn_row)
	var how := UiTheme.button("How to play", "", 44)
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how.pressed.connect(_on_tutorial)
	how.disabled = true
	_buttons.append(how)
	learn_row.add_child(how)
	var create := UiTheme.button("Create private room", "", 44)
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.pressed.connect(_on_create_room)
	create.disabled = true
	_buttons.append(create)
	learn_row.add_child(create)

	# Join by code, or (once a room exists) the room's code with Copy.
	_join_row = HBoxContainer.new()
	_join_row.add_theme_constant_override("separation", int(_px(8)))
	box.add_child(_join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Room code"
	_code_edit.max_length = 6
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, _px(44))
	_code_edit.add_theme_font_override("font", UiTheme.display_heavy())
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			_code_edit.text = up
			_code_edit.caret_column = up.length())
	_join_row.add_child(_code_edit)
	var join := UiTheme.button("Join", "", 44)
	join.custom_minimum_size = Vector2(_px(88), _px(44))
	join.pressed.connect(_on_join_room)
	join.disabled = true
	_join_row.add_child(join)
	_buttons.append(join)
	_room_row = HBoxContainer.new()
	_room_row.add_theme_constant_override("separation", int(_px(8)))
	_room_row.visible = false
	box.add_child(_room_row)
	var code_box := PanelContainer.new()
	var dashed := StyleBoxFlat.new()
	dashed.bg_color = Color(Companies.CARD_FACE, 0.08)
	dashed.border_color = Companies.CARD_FACE
	dashed.set_border_width_all(int(_px(2)))
	dashed.set_corner_radius_all(int(_px(10)))
	code_box.add_theme_stylebox_override("panel", dashed)
	code_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_box.custom_minimum_size = Vector2(0, _px(44))
	_room_label = UiTheme.label("", 13, "bold", Companies.CARD_FACE)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	code_box.add_child(_room_label)
	_room_row.add_child(code_box)
	_copy_button = UiTheme.button("Copy", "", 44)
	_copy_button.custom_minimum_size = Vector2(_px(88), _px(44))
	_copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_room_code)
		_copy_button.text = "Copied!")
	_room_row.add_child(_copy_button)

	_lobby_label = UiTheme.label("", 14, "bold", Companies.CARD_FACE)
	_lobby_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_lobby_label)
	_ready_button = UiTheme.button("I'm ready", "PrimaryButton", 44)
	_ready_button.visible = false
	_ready_button.pressed.connect(_on_ready_pressed)
	box.add_child(_ready_button)

	# Server row: host, https toggle, connect. Accepts "host", "host:port"
	# or a full "https://host" URL; the toggle shows the scheme and applies
	# when the text has none.
	var server := VBoxContainer.new()
	server.add_theme_constant_override("separation", int(_px(4)))
	box.add_child(server)
	server.add_child(UiTheme.label("SERVER", 10, "bold", Color(Companies.CARD_FACE, 0.7)))
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", int(_px(8)))
	server.add_child(host_row)
	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "host (127.0.0.1)"
	var default_port := 443 if Net.scheme == "https" else 7350
	_host_edit.text = Net.host if Net.port == default_port else "%s:%d" % [Net.host, Net.port]
	_host_edit.custom_minimum_size = Vector2(0, _px(44))
	_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_edit.add_theme_font_size_override("font_size", int(_px(13)))
	_host_edit.text_changed.connect(_on_host_text_changed)
	host_row.add_child(_host_edit)
	_secure_check = CheckButton.new()
	_secure_check.text = "https"
	_secure_check.button_pressed = Net.scheme == "https"
	_secure_check.add_theme_color_override("font_color", Companies.CARD_FACE)
	_secure_check.add_theme_color_override("font_hover_color", Companies.CARD_FACE)
	_secure_check.add_theme_color_override("font_pressed_color", Companies.CARD_FACE)
	_secure_check.add_theme_color_override("font_hover_pressed_color", Companies.CARD_FACE)
	_secure_check.toggled.connect(_on_secure_toggled)
	host_row.add_child(_secure_check)
	var connect_button := UiTheme.button("Connect", "GhostButton", 44)
	connect_button.pressed.connect(_on_connect_pressed)
	host_row.add_child(connect_button)

	# Season standings: a sheet that rises from the bottom.
	_season_sheet = Control.new()
	_season_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_season_sheet.visible = false
	add_child(_season_sheet)
	var shade := ColorRect.new()
	shade.color = Color("#0A1610", 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_season_sheet.visible = false)
	_season_sheet.add_child(shade)
	var sheet := UiTheme.deed_panel(Companies.SEASON, "Season standings", Color.WHITE)
	sheet["title"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sp: PanelContainer = sheet["panel"]
	sp.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sp.offset_left = _px(16)
	sp.offset_right = -_px(16)
	sp.offset_bottom = -_px(16)
	sp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_season_sheet.add_child(sp)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", int(_px(14)))
	sheet["body"].add_child(sbox)
	_board_label = UiTheme.label("", 15, "body")
	_board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(_board_label)
	var close := UiTheme.button("Close", "PrimaryButton", 44)
	close.pressed.connect(func() -> void: _season_sheet.visible = false)
	sbox.add_child(close)

	# Quests overlay above the lobby, toggled by its button.
	_quests_panel = QuestsPanel.new()
	_quests_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quests_panel.offset_left = _px(14)
	_quests_panel.offset_right = -_px(14)
	_quests_panel.offset_top = _px(30)
	_quests_panel.offset_bottom = -_px(24)
	_quests_panel.visible = false
	_quests_panel.cosmetic_changed.connect(_on_cosmetic_changed)
	add_child(_quests_panel)


func _make_avatar() -> Label:
	var avatar := UiTheme.label(Net.display_name.strip_edges().substr(0, 1).to_upper(), 18, "heavy")
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.custom_minimum_size = Vector2(_px(42), _px(42))
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color("#FFD98A")
	circle.border_color = Companies.INK
	circle.set_border_width_all(int(_px(2)))
	circle.set_corner_radius_all(int(_px(21)))
	circle.anti_aliasing = true
	avatar.add_theme_stylebox_override("normal", circle)
	return avatar


func _set_online_buttons(enabled: bool) -> void:
	for b in _buttons:
		b.disabled = not enabled


func _on_ready_pressed() -> void:
	Net.send_ready()
	_ready_button.disabled = true


func _on_connect_pressed() -> void:
	var parsed := Net.parse_host_input(_host_edit.text, "https" if _secure_check.button_pressed else "http")
	Net.scheme = parsed["scheme"]
	Net.host = parsed["host"]
	Net.port = parsed["port"]
	_secure_check.set_pressed_no_signal(Net.scheme == "https")
	Net.display_name = _name_edit.text.strip_edges()
	Net.save_settings()
	_status.text = "Connecting to %s..." % _server_address()
	await Net.connect_to_server()


## The effective address after parsing, shown so a wrong scheme is obvious.
func _server_address() -> String:
	return "%s://%s:%d" % [Net.scheme, Net.host, Net.port]


## A scheme typed into the host field wins over the toggle, so mirror it.
func _on_host_text_changed(text: String) -> void:
	var lower := text.strip_edges().to_lower()
	if lower.begins_with("https://"):
		_secure_check.set_pressed_no_signal(true)
	elif lower.begins_with("http://"):
		_secure_check.set_pressed_no_signal(false)


## Toggling rewrites an explicit scheme in the text so the two never disagree.
func _on_secure_toggled(on: bool) -> void:
	var text := _host_edit.text.strip_edges()
	var lower := text.to_lower()
	if lower.begins_with("https://") or lower.begins_with("http://"):
		_host_edit.text = ("https://" if on else "http://") + text.substr(text.find("://") + 3)


func _on_help() -> void:
	if _help == null:
		_help = HelpScreen.new()
		_help.on_replay = _on_tutorial
		add_child(_help)
	_help.visible = true


func _on_connected() -> void:
	_connected = true
	_status.text = "Connected as %s  •  %s" % [Net.display_name, _server_address()]
	_avatar.text = Net.display_name.strip_edges().substr(0, 1).to_upper()
	_set_online_buttons(true)
	_board_button.disabled = false
	_refresh_profile()


func _refresh_profile() -> void:
	var data: Dictionary = await Net.get_profile()
	if data.is_empty():
		return
	_apply_progress(data.get("progress", {}), bool(data.get("dailyAvailable", false)))
	_quests_panel.apply_profile(data)
	_on_cosmetic_changed("table", Cosmetics.table)


func _apply_progress(p: Dictionary, daily_available: bool) -> void:
	var level := int(p.get("level", 1))
	var xp := int(p.get("xp", 0))
	var floor_xp := 50 * (level - 1) * (level - 1)
	var next_xp := 50 * level * level
	_profile_label.text = "Level %d" % level
	_xp_label.text = "%d / %d XP  ·  Streak %d" % [xp, next_xp, int(p.get("streak", 0))]
	_xp_label.tooltip_text = "%d games, %d wins" % [int(p.get("gamesPlayed", 0)), int(p.get("wins", 0))]
	_xp_bar.min_value = floor_xp
	_xp_bar.max_value = next_xp
	_xp_bar.value = xp
	_daily_button.disabled = not daily_available
	_daily_button.text = "Claim daily bonus" if daily_available else "Bonus claimed"


func _on_claim_daily() -> void:
	_daily_button.disabled = true
	var res: Dictionary = await Net.claim_daily()
	if res.is_empty():
		_daily_button.disabled = false
		return
	if res.get("claimed", false):
		_status.text = "+%d XP  (day %d streak)" % [int(res.get("xpAwarded", 0)), int(res.get("progress", {}).get("streak", 1))]
	_apply_progress(res.get("progress", {}), false)


func _on_toggle_quests() -> void:
	_quests_panel.visible = not _quests_panel.visible


## The hero felt and the room behind it follow the picked table felt at once.
func _on_cosmetic_changed(_slot: String, _id: String) -> void:
	_felt.set_colors(Cosmetics.table_bg_color(), Cosmetics.table_edge_color())
	var fresh := UiTheme.room_background(Cosmetics.table_bg_color())
	_room.texture = fresh.texture
	fresh.free()


func _on_show_board() -> void:
	_season_sheet.visible = not _season_sheet.visible
	if not _season_sheet.visible:
		return
	_board_label.text = "Loading..."
	var rows: Array = await Net.season_leaderboard(10)
	if rows.is_empty():
		_board_label.text = "No season games yet. Points come from games with other people, and the board resets every month."
		return
	var lines := PackedStringArray()
	for r in rows:
		if r.get("mine", false) and int(r.get("rank", 0)) > 10:
			lines.append("…")
		var me := "  ← you" if r.get("userId", "") == Net.user_id else ""
		lines.append("#%d  %s  %d pts, %d wins%s" % [int(r.get("rank", 0)), r.get("name", "?"), int(r.get("score", 0)), int(r.get("wins", 0)), me])
	lines.append("")
	lines.append("Resets monthly.")
	_board_label.text = "\n".join(lines)


func _on_failed(reason: String) -> void:
	_connected = false
	_status.text = reason
	_set_online_buttons(false)


func _on_quick_play() -> void:
	# WHY: a first game against strangers with no rules is the surest way to
	# lose a new player; the tutorial is short and can be skipped from inside.
	if not Net.tutorial_done:
		_status.text = "First time? A two-minute tutorial comes first. You can skip it any time."
		if Net.is_connected_to_server():
			_in_lobby = await Net.start_tutorial()
		return
	_status.text = "Finding a game..."
	_in_lobby = await Net.quick_play()


## Also reached from the Help screen's "Replay the tutorial".
func _on_tutorial() -> void:
	if not Net.is_connected_to_server():
		_status.text = "Connect to a server first, then start the tutorial."
		return
	_status.text = "Starting the tutorial..."
	_in_lobby = await Net.start_tutorial()


func _on_create_room() -> void:
	_status.text = "Creating room..."
	var code: String = await Net.create_room()
	if code.is_empty():
		return
	_in_lobby = true
	_room_code = code
	_friends_panel.room_code = code
	_status.text = "Share the code with friends, then press I'm ready."
	_room_label.text = "Your room  %s" % code
	_copy_button.text = "Copy"
	_join_row.visible = false
	_room_row.visible = true
	_ready_button.visible = true


func _on_join_room() -> void:
	_status.text = "Joining..."
	_in_lobby = await Net.join_room(_code_edit.text)
	if _in_lobby:
		_ready_button.visible = true


func _on_lobby(lobby: Dictionary) -> void:
	var lines := PackedStringArray()
	var seats: Array = lobby.get("seats", [])
	var is_private: bool = lobby.get("isPrivate", false)
	lines.append("%s room  •  %d / %d players" % ["Private" if is_private else "Public", seats.size(), int(lobby.get("maxSeats", 0))])
	for s in seats:
		lines.append("  %s %s" % ["✓" if s.get("ready", false) else "…", s.get("name", "?")])
	var starts := float(lobby.get("startsAt", 0))
	if starts > 0:
		var secs := maxi(0, int((starts - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
		lines.append("Starting in %ds (empty seats become bots)" % secs)
	elif is_private:
		lines.append("Starts when everyone is ready (2+ players)")
	_lobby_label.text = "\n".join(lines)


func _on_first_view(_view: Dictionary) -> void:
	get_tree().change_scene_to_file("res://scenes/table.tscn")


## Join the room a friend invited us to (Join button in the friends panel).
func _on_invite_join(code: String) -> void:
	_code_edit.text = code
	await _on_join_room()
	if _in_lobby:
		_friends_panel.room_code = code
