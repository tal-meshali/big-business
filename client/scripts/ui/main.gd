extends Control
## Lobby screen: connect, quick play, create or join a private room.

var _host_edit: LineEdit
var _secure_check: CheckButton
var _help: HelpScreen = null
var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _lobby_label: Label
var _buttons: Array[Button] = []
var _ready_button: Button
var _copy_button: Button
var _room_code := ""
var _profile_label: Label
var _xp_bar: ProgressBar
var _daily_button: Button
var _board_button: Button
var _board_label: Label
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


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Companies.TABLE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Companies.TABLE_EDGE
	frame.border_width = 6.0
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 32
	box.offset_right = -32
	box.offset_top = 80
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	# Title on a red deed band, like the name plate of a property board.
	var deed := UiTheme.deed_panel(Companies.ALERT, "BIG BUSINESS", Color.WHITE)
	deed["title"].add_theme_font_size_override("font_size", 40)
	var tagline := Label.new()
	tagline.text = "Collect shares. Corner the market. Cash in on dividend day."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.add_theme_font_size_override("font_size", 16)
	deed["body"].add_child(tagline)
	box.add_child(deed["panel"])

	# Host field accepts "host", "host:port" or a full "https://host" URL; the
	# toggle shows the scheme and applies when the text has none.
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	box.add_child(host_row)
	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "server host (127.0.0.1)"
	var default_port := 443 if Net.scheme == "https" else 7350
	_host_edit.text = Net.host if Net.port == default_port else "%s:%d" % [Net.host, Net.port]
	_host_edit.custom_minimum_size = Vector2(0, 52)
	_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_edit.text_changed.connect(_on_host_text_changed)
	host_row.add_child(_host_edit)
	_secure_check = CheckButton.new()
	_secure_check.text = "Secure (https)"
	_secure_check.button_pressed = Net.scheme == "https"
	_secure_check.custom_minimum_size = Vector2(0, 52)
	_secure_check.toggled.connect(_on_secure_toggled)
	host_row.add_child(_secure_check)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "your name"
	_name_edit.text = Net.display_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 52)
	box.add_child(_name_edit)

	_status = Label.new()
	_status.text = "Not connected"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	# Profile card: level, XP bar, streak and the daily bonus.
	var profile := UiTheme.deed_panel(Companies.CHEST, "Your portfolio", Color.WHITE)
	profile["title"].add_theme_font_size_override("font_size", 20)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 8)
	profile["body"].add_child(pbox)
	_profile_label = Label.new()
	_profile_label.text = "Level 1"
	_profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_label.add_theme_font_size_override("font_size", 16)
	pbox.add_child(_profile_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 14)
	_xp_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Companies.GOLD
	fill.set_corner_radius_all(6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#E8E8E8")
	track.border_color = Companies.INK
	track.set_border_width_all(1)
	track.set_corner_radius_all(6)
	_xp_bar.add_theme_stylebox_override("fill", fill)
	_xp_bar.add_theme_stylebox_override("background", track)
	pbox.add_child(_xp_bar)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 10)
	pbox.add_child(prow)
	_daily_button = Button.new()
	_daily_button.text = "Claim daily bonus"
	_daily_button.custom_minimum_size = Vector2(0, 48)
	_daily_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_button.disabled = true
	_daily_button.pressed.connect(_on_claim_daily)
	prow.add_child(_daily_button)
	_board_button = Button.new()
	_board_button.text = "Season standings"
	_board_button.custom_minimum_size = Vector2(0, 48)
	_board_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_button.disabled = true
	_board_button.pressed.connect(_on_show_board)
	prow.add_child(_board_button)
	_board_label = Label.new()
	_board_label.visible = false
	_board_label.add_theme_font_size_override("font_size", 15)
	pbox.add_child(_board_label)
	box.add_child(profile["panel"])

	_add_button(box, "Connect", _on_connect_pressed, true)
	_add_button(box, "Play now", _on_quick_play)
	var learn_row := HBoxContainer.new()
	learn_row.add_theme_constant_override("separation", 10)
	box.add_child(learn_row)
	_add_button(learn_row, "How to play (tutorial)", _on_tutorial)
	learn_row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(learn_row, "Help", _on_help, true)
	learn_row.get_child(1).custom_minimum_size = Vector2(150, 56)
	_add_button(box, "Create private room", _on_create_room)

	var join_row := HBoxContainer.new()
	box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.max_length = 6
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, 56)
	join_row.add_child(_code_edit)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size = Vector2(120, 56)
	join.pressed.connect(_on_join_room)
	join.disabled = true
	join_row.add_child(join)
	_buttons.append(join)

	_lobby_label = Label.new()
	_lobby_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_lobby_label)

	_copy_button = Button.new()
	_copy_button.text = "Copy room code"
	_copy_button.custom_minimum_size = Vector2(0, 56)
	_copy_button.visible = false
	_copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_room_code)
		_copy_button.text = "Copied!")
	box.add_child(_copy_button)

	_ready_button = Button.new()
	_ready_button.text = "I'm ready"
	_ready_button.custom_minimum_size = Vector2(0, 56)
	_ready_button.visible = false
	_ready_button.pressed.connect(_on_ready_pressed)
	box.add_child(_ready_button)


func _add_button(parent: Control, text: String, handler: Callable, enabled := false) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(handler)
	b.disabled = not enabled
	parent.add_child(b)
	if not enabled:
		_buttons.append(b)


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
	_set_online_buttons(true)
	_board_button.disabled = false
	_refresh_profile()


func _refresh_profile() -> void:
	var data: Dictionary = await Net.get_profile()
	if data.is_empty():
		return
	_apply_progress(data.get("progress", {}), bool(data.get("dailyAvailable", false)))


func _apply_progress(p: Dictionary, daily_available: bool) -> void:
	var level := int(p.get("level", 1))
	var xp := int(p.get("xp", 0))
	var floor_xp := 50 * (level - 1) * (level - 1)
	var next_xp := 50 * level * level
	_profile_label.text = "Level %d  •  %d / %d XP  •  %d games, %d wins  •  streak %d" % [
		level, xp, next_xp, int(p.get("gamesPlayed", 0)), int(p.get("wins", 0)), int(p.get("streak", 0))]
	_xp_bar.min_value = floor_xp
	_xp_bar.max_value = next_xp
	_xp_bar.value = xp
	_daily_button.disabled = not daily_available
	_daily_button.text = "Claim daily bonus" if daily_available else "Daily bonus claimed"


func _on_claim_daily() -> void:
	_daily_button.disabled = true
	var res: Dictionary = await Net.claim_daily()
	if res.is_empty():
		_daily_button.disabled = false
		return
	if res.get("claimed", false):
		_status.text = "+%d XP  (day %d streak)" % [int(res.get("xpAwarded", 0)), int(res.get("progress", {}).get("streak", 1))]
	_apply_progress(res.get("progress", {}), false)


func _on_show_board() -> void:
	_board_label.visible = not _board_label.visible
	if not _board_label.visible:
		return
	_board_label.text = "Loading..."
	var rows: Array = await Net.season_leaderboard(10)
	if rows.is_empty():
		_board_label.text = "No season games yet. Points come from games with other people."
		return
	var lines := PackedStringArray()
	lines.append("Season standings (resets monthly)")
	for r in rows:
		if r.get("mine", false) and int(r.get("rank", 0)) > 10:
			lines.append("…")
		var me := "  ← you" if r.get("userId", "") == Net.user_id else ""
		lines.append("#%d  %s  %d pts, %d wins%s" % [int(r.get("rank", 0)), r.get("name", "?"), int(r.get("score", 0)), int(r.get("wins", 0)), me])
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
	_status.text = "Room code: %s" % code
	_copy_button.visible = true
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
