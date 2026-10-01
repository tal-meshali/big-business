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
var _profile_label: Label
var _xp_bar: ProgressBar
var _daily_button: Button
var _board_button: Button
var _board_label: Label
var _friends_panel: FriendsPanel
var _quests_button: Button
var _quests_panel: QuestsPanel
var _felt: ColorRect
var _felt_edge: ReferenceRect
var _account_label: Label
var _link_apple_button: Button
var _link_google_button: Button
var _connected := false
var _in_lobby := false
## Set when a link attempt signed in to the provider's existing account.
var _account_switched := false


func _ready() -> void:
	_build()
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.lobby_updated.connect(_on_lobby)
	Net.view_updated.connect(_on_first_view, CONNECT_ONE_SHOT)
	Net.server_error.connect(func(m: String) -> void: _status.text = m)
	Net.account_switched.connect(_on_account_switched)
	if not Net.is_connected_to_server():
		_on_connect_pressed.call_deferred()
	else:
		# Back from a game on a live socket: no connected signal will come,
		# so load the profile and quests (advanced by that game) now.
		_on_connected.call_deferred()
	_refresh_account_row.call_deferred()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Cosmetics.table_bg_color()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_felt = bg
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Cosmetics.table_edge_color()
	_felt_edge = frame
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

	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "server (127.0.0.1 or https://your.domain)"
	_host_edit.text = Net.server_address()
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
	var friends_button := Button.new()
	friends_button.text = "Friends"
	friends_button.custom_minimum_size = Vector2(0, 48)
	friends_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_button.pressed.connect(func() -> void: _friends_panel.visible = not _friends_panel.visible)
	prow.add_child(friends_button)
	_board_label = Label.new()
	_board_label.visible = false
	_board_label.add_theme_font_size_override("font_size", 15)
	pbox.add_child(_board_label)
	_quests_button = Button.new()
	_quests_button.text = "Quests & card backs"
	_quests_button.custom_minimum_size = Vector2(0, 48)
	_quests_button.pressed.connect(_on_toggle_quests)
	pbox.add_child(_quests_button)
	box.add_child(profile["panel"])

	_friends_panel = FriendsPanel.new()
	_friends_panel.visible = false
	_friends_panel.join_requested.connect(_on_invite_join)
	box.add_child(_friends_panel)

	_add_button(box, "Connect", _on_connect_pressed, true)
	_add_button(box, "Play now", _on_quick_play)
	_add_button(box, "How to play (tutorial)", _on_tutorial)
	_add_button(box, "Rules and help", _on_help, true)
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

	# Account row: guest or linked providers, with link buttons where a
	# token provider exists (iOS / Android with the plugin installed).
	var account_row := HBoxContainer.new()
	account_row.add_theme_constant_override("separation", 8)
	box.add_child(account_row)
	_account_label = Label.new()
	_account_label.text = Net.describe_account_links({})
	_account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_account_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	account_row.add_child(_account_label)
	_link_apple_button = Button.new()
	_link_apple_button.text = "Link Apple"
	_link_apple_button.custom_minimum_size = Vector2(0, 56)
	_link_apple_button.visible = false
	_link_apple_button.pressed.connect(_on_link_apple)
	account_row.add_child(_link_apple_button)
	_link_google_button = Button.new()
	_link_google_button.text = "Link Google"
	_link_google_button.custom_minimum_size = Vector2(0, 56)
	_link_google_button.visible = false
	_link_google_button.pressed.connect(_on_link_google)
	account_row.add_child(_link_google_button)

	# Quests overlay above the lobby, toggled by its button.
	_quests_panel = QuestsPanel.new()
	_quests_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quests_panel.offset_left = 24
	_quests_panel.offset_right = -24
	_quests_panel.offset_top = 60
	_quests_panel.offset_bottom = -40
	_quests_panel.visible = false
	_quests_panel.cosmetic_changed.connect(_on_cosmetic_changed)
	add_child(_quests_panel)


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
	Net.set_server_address(_host_edit.text)
	_host_edit.text = Net.server_address()
	Net.display_name = _name_edit.text.strip_edges()
	Net.save_settings()
	_status.text = "Connecting to %s..." % Net.server_address()
	await Net.connect_preferred()


func _on_connected() -> void:
	_connected = true
	_status.text = "Connected as %s" % Net.display_name
	_set_online_buttons(true)
	_board_button.disabled = false
	_refresh_profile()
	_refresh_account_row()


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


func _on_toggle_quests() -> void:
	_quests_panel.visible = not _quests_panel.visible


## The lobby felt follows the picked table felt at once.
func _on_cosmetic_changed(_slot: String, _id: String) -> void:
	_felt.color = Cosmetics.table_bg_color()
	_felt_edge.border_color = Cosmetics.table_edge_color()


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
		var me := "  (you)" if r.get("userId", "") == Net.user_id else ""
		lines.append("#%d  %s  %d pts, %d wins%s" % [int(r.get("rank", 0)), r.get("name", "?"), int(r.get("score", 0)), int(r.get("wins", 0)), me])
	_board_label.text = "\n".join(lines)


## Account row: the label follows the server's view of the account; a link
## button shows only where SocialTokens can produce a token and that
## provider is not linked yet.
func _refresh_account_row() -> void:
	var links: Dictionary = {}
	if Net.is_connected_to_server():
		links = await Net.get_account_links()
	_account_label.text = Net.describe_account_links(links)
	var avail: Dictionary = SocialTokens.available()
	_link_apple_button.visible = bool(avail.get("apple", false)) and not links.get("apple", false)
	_link_google_button.visible = bool(avail.get("google", false)) and not links.get("google", false)
	_link_apple_button.disabled = not Net.is_connected_to_server()
	_link_google_button.disabled = not Net.is_connected_to_server()


func _on_link_apple() -> void:
	var token: String = SocialTokens.request_apple()
	if token.is_empty():
		_status.text = "Apple sign-in was cancelled."
		return
	_account_switched = false
	if await Net.link_apple(token) and not _account_switched:
		_status.text = "Apple linked. Your account now survives a reinstall."
	_refresh_account_row()


## Linking found the provider already tied to another account (ours before
## a reinstall), so Net signed in to it; show that account's progress.
func _on_account_switched(provider_name: String) -> void:
	_account_switched = true
	_status.text = "Signed in to your existing %s account." % provider_name.capitalize()
	_refresh_profile()


func _on_link_google() -> void:
	var token: String = SocialTokens.request_google()
	if token.is_empty():
		_status.text = "Google sign-in was cancelled."
		return
	_account_switched = false
	if await Net.link_google(token) and not _account_switched:
		_status.text = "Google linked. Your account now survives a reinstall."
	_refresh_account_row()


func _on_failed(reason: String) -> void:
	_connected = false
	_status.text = reason
	_set_online_buttons(false)


func _on_quick_play() -> void:
	_status.text = "Finding a game..."
	_in_lobby = await Net.quick_play()


func _on_help() -> void:
	HelpScreen.open_over(self)


func _on_tutorial() -> void:
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
		lines.append("  %s%s" % [s.get("name", "?"), "  (ready)" if s.get("ready", false) else ""])
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
	# Leave the lobby we are waiting in first: a socket in two matches would
	# take the other lobby's game when it starts.
	if not Net.match_id.is_empty():
		await Net.leave_match()
		_in_lobby = false
		_room_code = ""
		_friends_panel.room_code = ""
	_code_edit.text = code
	await _on_join_room()
	if _in_lobby:
		_friends_panel.room_code = code
