extends Control
## Lobby screen: connect, quick play, create or join a private room.

var _host_edit: LineEdit
var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _lobby_label: Label
var _buttons: Array[Button] = []
var _ready_button: Button
var _copy_button: Button
var _room_code := ""
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
	var bg := ColorRect.new()
	bg.color = Companies.TABLE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 32
	box.offset_right = -32
	box.offset_top = 80
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "Big Business"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Companies.GOLD)
	box.add_child(title)

	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "server host (127.0.0.1)"
	_host_edit.text = Net.host
	_host_edit.custom_minimum_size = Vector2(0, 52)
	box.add_child(_host_edit)

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

	_add_button(box, "Connect", _on_connect_pressed, true)
	_add_button(box, "Play now", _on_quick_play)
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
	Net.host = _host_edit.text.strip_edges()
	Net.display_name = _name_edit.text.strip_edges()
	Net.save_settings()
	_status.text = "Connecting to %s..." % Net.host
	await Net.connect_to_server()


func _on_connected() -> void:
	_connected = true
	_status.text = "Connected as %s" % Net.display_name
	_set_online_buttons(true)


func _on_failed(reason: String) -> void:
	_connected = false
	_status.text = reason
	_set_online_buttons(false)


func _on_quick_play() -> void:
	_status.text = "Finding a game..."
	_in_lobby = await Net.quick_play()


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
