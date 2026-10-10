extends Control
## Start screen, after the "3D table" design: a little table with the six
## companies' shares fanned over it, the title card, your portfolio (name,
## level, XP, daily bonus, season standings), Play now, the tutorial and
## private rooms. Below the fold: friends, quests and card backs, the shop,
## rules, your account and the server address.

var _host_edit: LineEdit
var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _lobby_label: Label
var _buttons: Array[Button] = []
var _ready_button: Button
## In a lobby: stop waiting and fill the empty seats with bots.
var _start_now_button: Button
var _copy_button: Button
var _room_code := ""
var _room_label: Label
var _join_row: HBoxContainer
var _room_row: HBoxContainer
var _profile_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _avatar_label: Label
var _daily_button: Button
var _board_button: Button
var _board_label: Label
var _season_sheet: ColorRect
var _friends_panel: FriendsPanel
var _quests_button: Button
var _quests_panel: QuestsPanel
var _shop_button: Button
var _shop_panel: ShopPanel
var _clubs_panel: ClubsPanel
## Games on the profile; -1 until the profile has loaded.
var _games_played := -1
## The little table on top; its `color` is the picked felt.
var _felt: StartFan
var _room: TextureRect
var _account_label: Label
var _link_apple_button: Button
var _link_google_button: Button
var _connected := false
var _in_lobby := false
## Set when a link attempt signed in to the provider's existing account.
var _account_switched := false
## Design points to px.
var _s := 1.85


func _ready() -> void:
	_build()
	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)
	Net.lobby_updated.connect(_on_lobby)
	Net.view_updated.connect(_on_first_view, CONNECT_ONE_SHOT)
	Net.server_error.connect(func(m: String) -> void: _status.text = m)
	Net.account_switched.connect(_on_account_switched)
	Net.remote_config_updated.connect(_apply_remote_config)
	if not Net.is_connected_to_server():
		_on_connect_pressed.call_deferred()
	else:
		# Back from a game on a live socket: no connected signal will come,
		# so load the profile and quests (advanced by that game) now.
		_on_connected.call_deferred()
	_refresh_account_row.call_deferred()


func _px(dp: float) -> int:
	return int(round(dp * _s))


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_s = UiTheme.layout_scale(get_viewport_rect().size)
	_room = UiTheme.room_background(Cosmetics.table_bg_color(), Vector2(0.5, 0.22))
	add_child(_room)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Phones scroll by dragging; the bar would only cover the cards.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	var margins := MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margins.add_theme_constant_override("margin_left", _px(18))
	margins.add_theme_constant_override("margin_right", _px(18))
	var insets := UiTheme.safe_insets(self)
	margins.add_theme_constant_override("margin_top", maxi(_px(40), int(insets.x) + _px(8)))
	margins.add_theme_constant_override("margin_bottom", _px(28) + int(insets.y))
	scroll.add_child(margins)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(12))
	margins.add_child(box)

	_felt = StartFan.new()
	_felt.s = _s
	_felt.color = Cosmetics.table_bg_color()
	_felt.edge_color = Cosmetics.table_edge_color()
	box.add_child(_felt)
	box.add_child(_title_card())

	_status = UiTheme.label("Not connected", _px(13), UiTheme.CREAM)
	_status.add_theme_font_override("font", UiTheme.body_font())
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	box.add_child(_portfolio_card())

	var play := UiTheme.button("Play now", _px(20), _px(58), "big")
	play.icon = UiTheme.play_icon(_px(20))
	play.add_theme_constant_override("h_separation", _px(8))
	play.add_theme_constant_override("icon_max_width", _px(20))
	play.pressed.connect(_on_quick_play)
	play.disabled = true
	_buttons.append(play)
	box.add_child(play)
	var bots_row := _row(box)
	_add_button(bots_row, "Play vs bots now", _on_play_bots)
	var row := _row(box)
	_add_button(row, "How to play", _on_tutorial)
	_add_button(row, "Create private room", _on_create_room)

	# Join by code, or once you made a room, its code to share.
	_join_row = _row(box)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Room code"
	_code_edit.max_length = 6
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, _px(44))
	_code_edit.add_theme_font_override("font", UiTheme.display_font())
	_code_edit.add_theme_font_size_override("font_size", _px(16))
	_code_edit.add_theme_constant_override("minimum_character_width", 4)
	_code_edit.text_changed.connect(func(t: String) -> void:
		var caret := _code_edit.caret_column
		_code_edit.text = t.to_upper()
		_code_edit.caret_column = caret)
	_join_row.add_child(_code_edit)
	var join := UiTheme.button("Join", _px(14), _px(44))
	join.custom_minimum_size.x = _px(88)
	join.pressed.connect(_on_join_room)
	join.disabled = true
	_join_row.add_child(join)
	_buttons.append(join)
	_room_row = _row(box)
	_room_row.visible = false
	_room_label = UiTheme.label("", _px(13), UiTheme.CREAM)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_label.custom_minimum_size = Vector2(0, _px(44))
	var dashed := StyleBoxFlat.new()
	dashed.draw_center = false
	dashed.border_color = UiTheme.CREAM
	dashed.set_border_width_all(2)
	dashed.set_corner_radius_all(_px(10))
	_room_label.add_theme_stylebox_override("normal", dashed)
	_room_row.add_child(_room_label)
	_copy_button = UiTheme.button("Copy", _px(14), _px(44))
	_copy_button.custom_minimum_size.x = _px(88)
	_copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_room_code)
		_copy_button.text = "Copied!")
	_room_row.add_child(_copy_button)

	_lobby_label = UiTheme.label("", _px(14), UiTheme.CREAM)
	_lobby_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_label.visible = false
	box.add_child(_lobby_label)
	_ready_button = UiTheme.button("I'm ready", _px(16), _px(48), "primary")
	_ready_button.visible = false
	_ready_button.pressed.connect(_on_ready_pressed)
	box.add_child(_ready_button)
	_start_now_button = UiTheme.button("Start now with bots", _px(16), _px(48))
	_start_now_button.visible = false
	_start_now_button.pressed.connect(_on_start_now_pressed)
	box.add_child(_start_now_button)

	_build_more(box)
	_build_season_sheet()

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

	_shop_panel = ShopPanel.new()
	_shop_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shop_panel.offset_left = 24
	_shop_panel.offset_right = -24
	_shop_panel.offset_top = 60
	_shop_panel.offset_bottom = -40
	_shop_panel.visible = false
	_shop_panel.cosmetic_changed.connect(_on_cosmetic_changed)
	# Purchases change what the quests picker may offer; reload the profile.
	_shop_panel.closed.connect(func() -> void:
		if Net.is_connected_to_server():
			_refresh_profile())
	add_child(_shop_panel)

	_clubs_panel = ClubsPanel.new()
	_clubs_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_clubs_panel.offset_left = 24
	_clubs_panel.offset_right = -24
	_clubs_panel.offset_top = 60
	_clubs_panel.offset_bottom = -40
	_clubs_panel.visible = false
	add_child(_clubs_panel)


## "BIG BUSINESS" on a red band, with the tagline under it.
func _title_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(Companies.PANEL, 12 * _s, 4 * _s))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var band := _band(Companies.ALERT, _px(58))
	column.add_child(band)
	var spaced := FontVariation.new()
	spaced.base_font = UiTheme.display_font()
	spaced.spacing_glyph = _px(2)
	var title := UiTheme.label("BIG BUSINESS", _px(34), Color.WHITE)
	title.add_theme_font_override("font", spaced)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(title)
	var tag := UiTheme.label("Collect shares. Corner the market. Cash in on dividend day.", _px(13.5))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, _px(14))
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, _px(9))
	pad.add_child(tag)
	column.add_child(pad)
	return card


## Your portfolio: avatar, name, level, XP towards the next level and the
## streak, the daily bonus and the season standings.
func _portfolio_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(Companies.PANEL, 12 * _s, 4 * _s))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var band := _band(Companies.color_of(2), _px(34))
	column.add_child(band)
	var title := UiTheme.label("Your portfolio", _px(15), Color.WHITE, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band.add_child(title)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", _px(12))
	pad.add_theme_constant_override("margin_right", _px(12))
	pad.add_theme_constant_override("margin_top", _px(10))
	pad.add_theme_constant_override("margin_bottom", _px(12))
	column.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _px(9))
	pad.add_child(body)

	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", _px(10))
	body.add_child(who)
	_avatar_label = UiTheme.label("?", _px(18), Companies.INK, true)
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.custom_minimum_size = Vector2(_px(42), _px(42))
	_avatar_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc := StyleBoxFlat.new()
	disc.bg_color = SeatView.AVATARS[0]
	disc.border_color = Companies.INK
	disc.set_border_width_all(2)
	disc.set_corner_radius_all(_px(21))
	_avatar_label.add_theme_stylebox_override("normal", disc)
	who.add_child(_avatar_label)
	var field := VBoxContainer.new()
	field.add_theme_constant_override("separation", _px(2))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(field)
	field.add_child(UiTheme.label("YOUR NAME", _px(10), UiTheme.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Pick a name"
	_name_edit.text = Net.display_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, maxf(48, _px(34)))
	_name_edit.add_theme_font_size_override("font_size", _px(16))
	var underline := StyleBoxFlat.new()
	underline.bg_color = Color(0, 0, 0, 0)
	underline.border_color = Companies.INK
	underline.border_width_bottom = 2
	underline.content_margin_left = 2
	var underline_focus := underline.duplicate()
	underline_focus.border_color = Companies.color_of(2)
	_name_edit.add_theme_stylebox_override("normal", underline)
	_name_edit.add_theme_stylebox_override("focus", underline_focus)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.focus_exited.connect(func() -> void: Net.save_settings())
	field.add_child(_name_edit)
	_on_name_changed(_name_edit.text)
	_profile_label = UiTheme.label("Level 1", _px(13), Companies.INK, true)
	_profile_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip := UiTheme.card_box(UiTheme.PRIMARY, 8 * _s, 2 * _s)
	chip.content_margin_left = 8 * _s
	chip.content_margin_right = 8 * _s
	chip.content_margin_top = 5 * _s
	chip.content_margin_bottom = 5 * _s
	_profile_label.add_theme_stylebox_override("normal", chip)
	who.add_child(_profile_label)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", _px(8))
	body.add_child(xp_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, _px(12))
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	xp_row.add_child(_xp_bar)
	_xp_label = UiTheme.label("0 / 50 XP · Streak 0", _px(12))
	xp_row.add_child(_xp_label)

	var buttons := _row(body)
	_daily_button = UiTheme.button("Claim daily bonus", _px(14), _px(44))
	_daily_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_button.disabled = true
	_daily_button.pressed.connect(_on_claim_daily)
	buttons.add_child(_daily_button)
	_board_button = UiTheme.button("Season standings", _px(14), _px(44))
	_board_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_button.disabled = true
	_board_button.pressed.connect(_on_show_board)
	buttons.add_child(_board_button)
	return card


## Below the fold: friends, quests and card backs, the shop, rules, your
## account and the server address.
func _build_more(box: VBoxContainer) -> void:
	var more := UiTheme.label("MORE", _px(11), Color(UiTheme.CREAM, 0.75), true)
	box.add_child(more)
	var row := _row(box)
	var friends_button := UiTheme.button("Friends", _px(14), _px(44))
	friends_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_button.pressed.connect(func() -> void: _friends_panel.visible = not _friends_panel.visible)
	row.add_child(friends_button)
	_quests_button = UiTheme.button("Quests & card backs", _px(14), _px(44))
	_quests_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quests_button.pressed.connect(_on_toggle_quests)
	row.add_child(_quests_button)
	var row2 := _row(box)
	_shop_button = UiTheme.button("Shop", _px(14), _px(44))
	_shop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_button.visible = RemoteConfig.shop_enabled
	_shop_button.pressed.connect(_on_open_shop)
	row2.add_child(_shop_button)
	var rules := UiTheme.button("Rules and help", _px(14), _px(44))
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.pressed.connect(_on_help)
	row2.add_child(rules)
	var row3 := _row(box)
	var clubs_button := UiTheme.button("Clubs", _px(14), _px(44))
	clubs_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clubs_button.pressed.connect(_on_open_clubs)
	row3.add_child(clubs_button)

	_friends_panel = FriendsPanel.new()
	_friends_panel.visible = false
	_friends_panel.join_requested.connect(_on_invite_join)
	_friends_panel.gifts_collected.connect(_refresh_profile)
	# Watching left any lobby we were in; the table opens with the first view.
	_friends_panel.watch_started.connect(func() -> void:
		_in_lobby = false
		_room_code = ""
		_friends_panel.room_code = "")
	box.add_child(_friends_panel)

	# Account row: guest or linked providers, with link buttons where a
	# token provider exists (iOS / Android with the plugin installed).
	var account_row := _row(box)
	_account_label = UiTheme.label(Net.describe_account_links({}), _px(12), UiTheme.CREAM)
	_account_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_account_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_account_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	account_row.add_child(_account_label)
	_link_apple_button = UiTheme.button("Link Apple", _px(13), _px(44))
	_link_apple_button.visible = false
	_link_apple_button.pressed.connect(_on_link_apple)
	account_row.add_child(_link_apple_button)
	_link_google_button = UiTheme.button("Link Google", _px(13), _px(44))
	_link_google_button.visible = false
	_link_google_button.pressed.connect(_on_link_google)
	account_row.add_child(_link_google_button)

	var server_row := _row(box)
	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "server (127.0.0.1 or https://your.domain)"
	_host_edit.text = Net.server_address()
	_host_edit.custom_minimum_size = Vector2(0, maxf(48, _px(40)))
	_host_edit.add_theme_font_size_override("font_size", _px(13))
	_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_row.add_child(_host_edit)
	var connect_button := UiTheme.button("Connect", _px(13), _px(40), "ghost")
	connect_button.pressed.connect(_on_connect_pressed)
	server_row.add_child(connect_button)


## Season standings in a sheet that rises from the bottom.
func _build_season_sheet() -> void:
	_season_sheet = ColorRect.new()
	_season_sheet.color = Color(0.04, 0.09, 0.06, 0.6)
	_season_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_season_sheet.visible = false
	_season_sheet.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_season_sheet.visible = false)
	add_child(_season_sheet)
	var deed := UiTheme.deed_panel(Color("#7B4FC6"), "Season standings", Color.WHITE)
	deed["title"].add_theme_font_size_override("font_size", _px(18))
	deed["title"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sheet: PanelContainer = deed["panel"]
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.offset_left = _px(16)
	sheet.offset_right = -_px(16)
	sheet.offset_bottom = -_px(16)
	_season_sheet.add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _px(14))
	deed["body"].add_child(body)
	_board_label = UiTheme.label("", _px(15))
	_board_label.add_theme_font_override("font", UiTheme.body_font())
	_board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_board_label)
	var close := UiTheme.button("Close", _px(14), _px(44), "primary")
	close.pressed.connect(func() -> void: _season_sheet.visible = false)
	body.add_child(close)


func _band(color: Color, height: int) -> PanelContainer:
	var band := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Companies.INK
	style.border_width_bottom = 2
	style.corner_radius_top_left = int(10 * _s)
	style.corner_radius_top_right = int(10 * _s)
	band.add_theme_stylebox_override("panel", style)
	band.custom_minimum_size = Vector2(0, height)
	return band


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(8))
	parent.add_child(row)
	return row


func _add_button(parent: Control, text: String, handler: Callable, enabled := false) -> void:
	var b := UiTheme.button(text, _px(14), _px(44))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	b.disabled = not enabled
	parent.add_child(b)
	if not enabled:
		_buttons.append(b)


func _on_name_changed(text: String) -> void:
	var who := text.strip_edges()
	Net.display_name = who
	_avatar_label.text = who.substr(0, 1).to_upper() if not who.is_empty() else "?"


func _set_online_buttons(enabled: bool) -> void:
	for b in _buttons:
		b.disabled = not enabled


func _on_ready_pressed() -> void:
	Net.send_ready()
	_ready_button.disabled = true


func _on_start_now_pressed() -> void:
	Net.send_start_now()
	_start_now_button.disabled = true
	_status.text = "Starting with bots..."


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
	_games_played = int(p.get("gamesPlayed", 0))
	var level := int(p.get("level", 1))
	var xp := int(p.get("xp", 0))
	var floor_xp := 50 * (level - 1) * (level - 1)
	var next_xp := 50 * level * level
	_profile_label.text = "Level %d" % level
	_profile_label.tooltip_text = "%d games, %d wins" % [int(p.get("gamesPlayed", 0)), int(p.get("wins", 0))]
	_xp_label.text = "%d / %d XP · Streak %d" % [xp, next_xp, int(p.get("streak", 0))]
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
		_float_xp(int(res.get("xpAwarded", 0)))
	_apply_progress(res.get("progress", {}), false)


## "+15 XP" rises off the daily bonus button and fades.
func _float_xp(amount: int) -> void:
	var tag := UiTheme.label("+%d XP" % amount, _px(15), Companies.INK, true)
	var chip := UiTheme.card_box(UiTheme.PRIMARY, 8 * _s, 0)
	chip.content_margin_left = 6 * _s
	chip.content_margin_right = 6 * _s
	chip.content_margin_top = 3 * _s
	chip.content_margin_bottom = 3 * _s
	tag.add_theme_stylebox_override("normal", chip)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag)
	var r := _daily_button.get_global_rect()
	var start := Vector2(r.get_center().x - tag.get_combined_minimum_size().x / 2.0, r.position.y - _px(6))
	tag.global_position = start
	var tw := create_tween().set_parallel()
	tw.tween_property(tag, "global_position:y", start.y - _px(38), 1.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(tag, "modulate:a", 0.0, 1.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(tag.queue_free)


func _on_toggle_quests() -> void:
	_quests_panel.visible = not _quests_panel.visible


func _on_open_clubs() -> void:
	_quests_panel.visible = false
	_shop_panel.visible = false
	await _clubs_panel.open()


func _on_open_shop() -> void:
	_quests_panel.visible = false
	await _shop_panel.open()


## Remote Config arrived: the shop can be switched off without a release.
func _apply_remote_config() -> void:
	_shop_button.visible = RemoteConfig.shop_enabled
	if not RemoteConfig.shop_enabled:
		_shop_panel.visible = false


## The lobby felt (and the room around it) follows the picked felt at once.
func _on_cosmetic_changed(_slot: String, _id: String) -> void:
	_felt.color = Cosmetics.table_bg_color()
	_felt.edge_color = Cosmetics.table_edge_color()
	UiTheme.paint_room(_room, Cosmetics.table_bg_color(), Vector2(0.5, 0.22))


func _on_show_board() -> void:
	_season_sheet.visible = true
	_board_label.text = "Loading..."
	var rows: Array = await Net.season_leaderboard(10)
	if rows.is_empty():
		_board_label.text = "No season games yet. Points come from games with other people, and the board resets every month."
		return
	var lines := PackedStringArray()
	lines.append("Resets every month.")
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
	# Remote Config can send a brand-new player to the tutorial first (TODO-local B2).
	if RemoteConfig.tutorial_auto_route and _games_played == 0:
		_status.text = "First game: let's start with the tutorial..."
		_in_lobby = await Net.start_tutorial()
		return
	_status.text = "Finding a game..."
	_in_lobby = await Net.quick_play()


func _on_play_bots() -> void:
	# Leave a lobby we are waiting in first, as for an invite below.
	if not Net.match_id.is_empty():
		await Net.leave_match()
		_in_lobby = false
		_room_code = ""
		_friends_panel.room_code = ""
	_status.text = "Starting a game against bots..."
	_in_lobby = await Net.play_bots()


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
		lines.append("  %s%s" % [s.get("name", "?"), "  (ready)" if s.get("ready", false) else ""])
	var starts := float(lobby.get("startsAt", 0))
	if starts > 0:
		var secs := maxi(0, int((starts - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
		lines.append("Starting in %ds (empty seats become bots)" % secs)
	elif is_private:
		lines.append("Starts when everyone is ready (2+ players)")
	_lobby_label.text = "\n".join(lines)
	_lobby_label.visible = true
	# Anyone may cut a public wait short; a private room waits for its host.
	_start_now_button.visible = not is_private or not _room_code.is_empty()


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
