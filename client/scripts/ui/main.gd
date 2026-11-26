extends Control
## Start screen, "after-hours trading floor" (2026-11), fitted to one phone
## screen: a royal purple room with turning gold rays; a HUD with your
## avatar and level, name, XP, streak, season standings and the daily gift;
## the little table with the six shares fanned over it (it shrinks to the
## room left) under the gold logo; the breathing PLAY button, bots, the
## tutorial and private rooms; and a dock along the bottom edge for
## friends, quests and card backs, the shop, clubs and More (rules, your
## account, the server address). A tap on the avatar or the name opens the
## profile (ProfilePanel); a new player is asked for a name first
## (NamePrompt). Typing happens in sheets or fields that the lobby lifts
## above the on-screen keyboard.

var _host_edit: LineEdit
var _name_label: Label
## The avatar, name and XP bar: one button that opens the profile.
var _identity: Control
var _profile_button: Button
var _profile_panel: ProfilePanel
var _name_prompt: NamePrompt
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
var _daily_button: IconTile
var _board_button: IconTile
var _streak_label: Label
var _quests_tab: IconTile
var _board_label: Label
var _board_rows: VBoxContainer
var _board_scroll: ScrollContainer
var _board_mine: VBoxContainer
var _season_sheet: ColorRect
var _friends_panel: FriendsPanel
var _quests_button: Button
var _quests_panel: QuestsPanel
var _shop_button: Button
var _shop_panel: ShopPanel
var _clubs_panel: ClubsPanel
## Play now and the other ways in; swapped for `_room_box` while waiting.
var _play_box: VBoxContainer
## A room or quick-play lobby: its code, who is in, ready, start now, leave.
var _room_box: VBoxContainer
var _join_sheet: Control
## Vs bots: pick 2, 3 or 4 bots; a tap on a size starts that game.
var _bots_sheet: Control
var _bot_buttons: Array[Button] = []
var _friends_sheet: Control
var _more_sheet: Control
var _feedback_sheet: Control
var _feedback_panel: FeedbackPanel
## Notch / Dynamic Island (x) and home indicator (y), canvas units.
var _insets := Vector2.ZERO
## Games on the profile; -1 until the profile has loaded.
var _games_played := -1
var _level := 1
## The name in the settings file when the lobby loaded and nobody was
## signed in yet: what the player typed into an earlier build's name field.
var _saved_name := ""
## The account the server has said is named, so the lobby does not wait
## for that answer again after every game.
static var _named_user := ""
var _press_tween: Tween
## The little table on top; its `color` is the picked felt.
var _felt: StartFan
var _room: LobbyBackdrop
var _account_label: Label
var _link_row: HBoxContainer
var _link_apple_button: Button
var _link_google_button: Button
var _connected := false
var _in_lobby := false
## Set when a link attempt signed in to the provider's existing account.
var _account_switched := false
## Design points to px.
var _s := 1.85
## A keyboard height in canvas units for tests and screenshots, which have
## no on-screen keyboard; below 0 the phone's own is used.
var keyboard_override := -1.0


func _ready() -> void:
	if not Net.is_connected_to_server():
		_saved_name = Net.display_name
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
	_room = LobbyBackdrop.new()
	add_child(_room)

	_insets = UiTheme.safe_insets(self)
	var dock_h := _px(74) + int(_insets.y)

	# WHY: the layout is sized to fit a phone screen; the scroll only
	# matters on very short screens (and the keyboard lift handles typing).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -dock_h
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	var margins := MarginContainer.new()
	margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margins.add_theme_constant_override("margin_left", _px(16))
	margins.add_theme_constant_override("margin_right", _px(16))
	margins.add_theme_constant_override("margin_top", maxi(_px(14), int(_insets.x) + _px(4)))
	margins.add_theme_constant_override("margin_bottom", _px(10))
	scroll.add_child(margins)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", _px(8))
	margins.add_child(box)

	box.add_child(_hud())

	_felt = StartFan.new()
	_felt.s = _s
	_felt.fit = true
	_felt.color = Cosmetics.table_bg_color()
	_felt.edge_color = Cosmetics.table_edge_color()
	box.add_child(_felt)
	box.add_child(_logo())

	_status = UiTheme.label("Not connected", _px(UiTheme.TYPE_LABEL), UiTheme.LILAC)
	_status.add_theme_font_override("font", UiTheme.body_font())
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	box.add_child(_status)

	_play_box = VBoxContainer.new()
	_play_box.add_theme_constant_override("separation", _px(10))
	box.add_child(_play_box)
	var play := UiTheme.button("PLAY", _px(30), _px(70), "big")
	play.add_theme_constant_override("outline_size", _px(5))
	play.tooltip_text = "Play now: join an online game"
	play.pressed.connect(_on_quick_play)
	play.disabled = true
	_buttons.append(play)
	_play_box.add_child(_breathing(play))
	var row := _row(_play_box)
	_add_button(row, "Vs bots", _open_bots_sheet)
	_add_button(row, "How to play", _on_tutorial)
	var rooms := _row(_play_box)
	_add_button(rooms, "Create room", _on_create_room)
	_add_button(rooms, "Join with code", _open_join_sheet)

	_build_room_box(box)
	_build_dock(dock_h)
	_build_join_sheet()
	_build_bots_sheet()
	_build_friends_sheet()
	_build_more_sheet()
	_build_feedback_sheet()
	_build_season_sheet()

	# Quests overlay above the lobby, toggled by its button.
	# A full-height royal sheet over a dimmed lobby, like the rules.
	var quests_shade := ColorRect.new()
	quests_shade.color = Color(UiTheme.NIGHT, 0.78)
	quests_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quests_shade.visible = false
	add_child(quests_shade)
	_quests_panel = QuestsPanel.new()
	_quests_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quests_panel.offset_left = _px(10)
	_quests_panel.offset_right = -_px(10)
	_quests_panel.offset_top = _insets.x + _px(10)
	_quests_panel.offset_bottom = -_insets.y - _px(10)
	_quests_panel.visible = false
	_quests_panel.visibility_changed.connect(func() -> void: quests_shade.visible = _quests_panel.visible)
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

	_profile_panel = ProfilePanel.new()
	_profile_panel.s = _s
	_profile_panel.insets = _insets
	_profile_panel.navigate.connect(_on_profile_navigate)
	_profile_panel.unnamed = not Net.named
	# WHY "" while unnamed: the random name is not theirs to edit.
	_profile_panel.rename_requested.connect(func() -> void: _name_prompt.open(Net.display_name if Net.named else "", false, _level))
	_profile_panel.link_requested.connect(func(provider_name: String) -> void:
		if provider_name == "apple":
			_on_link_apple()
		else:
			_on_link_google())
	add_child(_profile_panel)

	_name_prompt = NamePrompt.new()
	_name_prompt.s = _s
	_name_prompt.bottom_inset = _insets.y
	_name_prompt.saved.connect(_on_name_saved)
	add_child(_name_prompt)


## The gold wordmark and the red ribbon under it, tilted together.
func _logo() -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := LogoTitle.new()
	logo.px = _px(40)
	logo.tilt = 0.0
	var tag := _tagline()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(2))
	column.add_child(logo)
	column.add_child(tag)
	holder.add_child(column)
	holder.custom_minimum_size = Vector2(0, _px(40) * 1.95 + _px(26))
	holder.resized.connect(func() -> void:
		column.size = Vector2(holder.size.x, column.get_combined_minimum_size().y)
		column.position = Vector2(0, (holder.size.y - column.size.y) / 2.0)
		column.pivot_offset = column.size / 2.0)
	column.rotation = deg_to_rad(LogoTitle.TILT_DEG)
	return holder


## The red ribbon under the logo.
func _tagline() -> Control:
	var center := CenterContainer.new()
	var tag := UiTheme.label("CORNER THE MARKET", _px(11), Color.WHITE, true)
	var spaced := FontVariation.new()
	spaced.base_font = UiTheme.display_font()
	spaced.spacing_glyph = _px(1.5)
	tag.add_theme_font_override("font", spaced)
	tag.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	tag.add_theme_constant_override("outline_size", _px(3))
	var pill := UiTheme.card_box(UiTheme.BADGE, 12 * _s, 2 * _s)
	pill.border_color = UiTheme.OUTLINE
	pill.content_margin_left = 14 * _s
	pill.content_margin_right = 14 * _s
	pill.content_margin_top = 3 * _s
	pill.content_margin_bottom = 3 * _s
	tag.add_theme_stylebox_override("normal", pill)
	tag.tooltip_text = "Collect shares. Corner the market. Cash in on dividend day."
	center.add_child(tag)
	return center


## The top bar, as in mobile games: your avatar with its level diamond,
## your name over the XP bar, the streak, season standings and the daily
## gift (it wiggles while a bonus waits).
func _hud() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(8))

	# Avatar, name and XP bar are one button: the way into the profile.
	_identity = MarginContainer.new()
	_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_identity)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", _px(8))
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_child(who)

	var avatar := Control.new()
	avatar.custom_minimum_size = Vector2(_px(48), _px(48))
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(avatar)
	_avatar_label = UiTheme.label("?", _px(19), UiTheme.OUTLINE, true)
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var disc := StyleBoxFlat.new()
	disc.bg_color = SeatView.AVATARS[0]
	disc.border_color = Color.WHITE
	disc.set_border_width_all(_px(2.5))
	disc.set_corner_radius_all(_px(24))
	disc.shadow_color = UiTheme.OUTLINE
	disc.shadow_size = _px(2)
	disc.shadow_offset = Vector2(0, _px(2))
	disc.anti_aliasing = true
	_avatar_label.add_theme_stylebox_override("normal", disc)
	avatar.add_child(_avatar_label)
	# The level diamond on the avatar's corner.
	var diamond := Control.new()
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diamond.custom_minimum_size = Vector2(_px(22), _px(22))
	diamond.size = diamond.custom_minimum_size
	diamond.position = Vector2(_px(31), _px(29))
	diamond.draw.connect(func() -> void:
		var c := diamond.size / 2.0
		var k := diamond.size.x * 0.55
		var pts := PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, 0), c + Vector2(0, k), c + Vector2(-k, 0)])
		diamond.draw_colored_polygon(pts, UiTheme.OUTLINE)
		var inner := PackedVector2Array()
		for p in pts:
			inner.append(c + (p - c) * 0.8)
		diamond.draw_colored_polygon(inner, UiTheme.VIOLET)
		var lvl := _profile_label.text.trim_prefix("Level ") if _profile_label != null else "1"
		var f := UiTheme.display_font()
		var sz := _px(10)
		var w := f.get_string_size(lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		diamond.draw_string(f, c + Vector2(-w / 2.0, sz * 0.36), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE))
	avatar.add_child(diamond)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(1))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(col)
	_name_label = UiTheme.label("", _px(15), Color.WHITE, true)
	_name_label.custom_minimum_size = Vector2(0, _px(24))
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_name_label.add_theme_constant_override("outline_size", _px(3))
	# A long name ends in an ellipsis instead of pushing the HUD apart.
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.clip_text = true
	col.add_child(_name_label)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", _px(6))
	col.add_child(xp_row)
	_profile_label = UiTheme.label("Level 1", _px(UiTheme.TYPE_CAPTION), UiTheme.GOLD, true)
	_profile_label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_profile_label.add_theme_constant_override("outline_size", _px(3))
	_profile_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_profile_label.draw.connect(func() -> void: diamond.queue_redraw())
	xp_row.add_child(_profile_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, _px(16))
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	xp_row.add_child(_xp_bar)
	_xp_label = UiTheme.label("0 / 50", _px(UiTheme.TYPE_CAPTION), Color.WHITE, true)
	_xp_label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_xp_label.add_theme_constant_override("outline_size", _px(2.5))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_bar.add_child(_xp_label)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_profile_button = Button.new()
	_profile_button.flat = true
	_profile_button.focus_mode = Control.FOCUS_NONE
	_profile_button.tooltip_text = "Your profile"
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		_profile_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_profile_button.pressed.connect(_open_profile)
	_identity.add_child(_profile_button)
	# The whole cluster gives under the finger, not just the invisible button.
	_identity.resized.connect(func() -> void: _identity.pivot_offset = Vector2(_px(24), _identity.size.y / 2.0))
	_profile_button.button_down.connect(_press_identity.bind(Vector2(0.96, 0.96), 0.08, Tween.TRANS_CUBIC))
	_profile_button.button_up.connect(_press_identity.bind(Vector2.ONE, 0.18, Tween.TRANS_BACK))
	_show_name()

	# Streak: a flame and the day count in a dark pill.
	var streak := PanelContainer.new()
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(UiTheme.NIGHT, 0.6)
	pill.border_color = UiTheme.OUTLINE
	pill.set_border_width_all(_px(1.5))
	pill.set_corner_radius_all(_px(14))
	pill.content_margin_left = _px(4)
	pill.content_margin_right = _px(8)
	pill.anti_aliasing = true
	streak.add_theme_stylebox_override("panel", pill)
	streak.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	streak.tooltip_text = "Daily streak: play or claim your bonus every day"
	row.add_child(streak)
	var streak_row := HBoxContainer.new()
	streak_row.add_theme_constant_override("separation", _px(2))
	streak.add_child(streak_row)
	var flame := Control.new()
	flame.custom_minimum_size = Vector2(_px(20), _px(26))
	flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flame.draw.connect(func() -> void: GameIcons.draw(flame, "flame", flame.size / 2.0, flame.size.x * 0.55))
	streak_row.add_child(flame)
	_streak_label = UiTheme.label("0", _px(13), Color.WHITE, true)
	_streak_label.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	_streak_label.add_theme_constant_override("outline_size", _px(3))
	_streak_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	streak_row.add_child(_streak_label)

	_board_button = _tile("trophy", "", UiTheme.VIOLET, _px(46))
	_board_button.tooltip_text = "Season standings"
	_board_button.disabled = true
	_board_button.pressed.connect(_on_show_board)
	row.add_child(_board_button)
	_daily_button = _tile("gift", "", UiTheme.MINT, _px(46))
	_daily_button.tooltip_text = "Daily bonus"
	_daily_button.disabled = true
	_daily_button.pressed.connect(_on_claim_daily)
	row.add_child(_daily_button)
	return row


func _tile(kind: String, caption: String, face: Color, side: int) -> IconTile:
	var t := IconTile.new()
	t.icon_kind = kind
	t.caption = caption
	t.face = face
	t.s = _s
	t.custom_minimum_size = Vector2(side, side + (_px(13) if not caption.is_empty() else 0))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## Wraps the Play button so it can breathe (scale the wrapper, so the
## button's own press squash stays free), with a light sweep across it.
func _breathing(b: Button) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_child(b)
	wrap.resized.connect(func() -> void: wrap.pivot_offset = wrap.size / 2.0)
	var tw := wrap.create_tween().set_loops()
	tw.tween_property(wrap, "scale", Vector2(1.03, 1.03), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(wrap, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var sweep := Control.new()
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.clip_contents = true
	sweep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sweep.offset_left = _px(3)
	sweep.offset_right = -_px(3)
	sweep.offset_top = _px(3)
	sweep.offset_bottom = -_px(10)
	b.add_child(sweep)
	sweep.set_meta("k", 2.0)
	sweep.draw.connect(func() -> void:
		var k: float = sweep.get_meta("k")
		if b.disabled or k > 1.0:
			return
		var h := sweep.size.y
		var w := h * 0.35
		var x := -h + (sweep.size.x + h * 2.0) * k
		sweep.draw_colored_polygon(PackedVector2Array([Vector2(x, h), Vector2(x + h * 0.5, 0), Vector2(x + h * 0.5 + w, 0), Vector2(x + w, h)]), Color(1, 1, 1, 0.45)))
	# One pass in 0.9 s, then a rest, forever.
	var shine := wrap.create_tween().set_loops()
	shine.tween_method(func(k: float) -> void:
		sweep.set_meta("k", k)
		sweep.queue_redraw(), 0.0, 3.5, 3.2)
	return wrap


## While waiting in a room or a quick-play lobby, this replaces the play
## buttons: the code to share, who is in, ready, start now and leave.
func _build_room_box(box: VBoxContainer) -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", _px(8))
	_room_box.visible = false
	box.add_child(_room_box)
	_room_row = _row(_room_box)
	_room_row.visible = false
	_room_label = UiTheme.label("", _px(UiTheme.TYPE_HEADING), UiTheme.GOLD, true)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_label.custom_minimum_size = Vector2(0, _px(44))
	# The code to share sits in a well, in gold, so it reads over the rays.
	_room_label.add_theme_stylebox_override("normal", UiTheme.well_box())
	_room_row.add_child(_room_label)
	_copy_button = UiTheme.button("Copy", _px(14), _px(44))
	_copy_button.custom_minimum_size.x = _px(88)
	_copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_room_code)
		_copy_button.text = "Copied!")
	_room_row.add_child(_copy_button)

	_lobby_label = UiTheme.body("", _px(UiTheme.TYPE_BODY))
	_lobby_label.add_theme_stylebox_override("normal", UiTheme.well_box())
	_lobby_label.visible = false
	_room_box.add_child(_lobby_label)
	var buttons := _row(_room_box)
	_ready_button = UiTheme.button("I'm ready", _px(16), _px(48), "primary")
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_button.visible = false
	_ready_button.pressed.connect(_on_ready_pressed)
	buttons.add_child(_ready_button)
	_start_now_button = UiTheme.button("Start with bots", _px(16), _px(48))
	_start_now_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_now_button.visible = false
	_start_now_button.pressed.connect(_on_start_now_pressed)
	buttons.add_child(_start_now_button)
	var leave := UiTheme.button("Leave", _px(14), _px(48), "ghost")
	leave.pressed.connect(_on_leave_room)
	buttons.add_child(leave)


## The dock along the bottom edge: friends, quests and card backs, the
## shop, clubs, and More (rules, account, server). Quests carry a red badge
## while a quest waits to be claimed.
func _build_dock(height: int) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -height
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.ROYAL.darkened(0.25)
	style.border_color = UiTheme.OUTLINE
	style.border_width_top = _px(2)
	style.corner_radius_top_left = _px(18)
	style.corner_radius_top_right = _px(18)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = _px(8)
	style.content_margin_left = _px(8)
	style.content_margin_right = _px(8)
	style.content_margin_top = _px(8)
	style.content_margin_bottom = _px(6) + _insets.y
	style.anti_aliasing = true
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", _px(4))
	bar.add_child(dock)
	var friends_button := _dock_button(dock, "friends", "Friends")
	friends_button.pressed.connect(func() -> void: _friends_sheet.visible = true)
	_quests_tab = _dock_button(dock, "quests", "Quests")
	_quests_tab.tooltip_text = "Quests & card backs"
	_quests_tab.pressed.connect(_on_toggle_quests)
	_shop_button = _dock_button(dock, "shop", "Shop")
	_shop_button.visible = RemoteConfig.shop_enabled
	_shop_button.pressed.connect(_on_open_shop)
	var clubs_button := _dock_button(dock, "clubs", "Clubs")
	clubs_button.pressed.connect(_on_open_clubs)
	var more := _dock_button(dock, "more", "More")
	more.pressed.connect(func() -> void: _more_sheet.visible = true)
	_quests_button = _quests_tab


func _dock_button(parent: Control, kind: String, caption: String) -> IconTile:
	var b := _tile(kind, caption, UiTheme.VIOLET, _px(44))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


## Red badge on Quests: how many quests are done but not yet claimed.
func _refresh_quest_badge() -> void:
	var n := 0
	for r in _quests_panel.rows:
		if r.get("claimable", false) and not r.get("claimed", false):
			n += 1
	_quests_tab.badge = str(n) if n > 0 else ""


## A night panel rising from the bottom over a dimmed lobby; a tap outside
## closes it. Returns {"root": the overlay, "body": a VBox for content}.
func _sheet(color: Color, title: String) -> Dictionary:
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.NIGHT, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.visible = false
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			shade.visible = false)
	add_child(shade)
	var deed := UiTheme.panel(color, title)
	var sheet: PanelContainer = deed["panel"]
	# WHY it swallows taps: only a tap on the dimmed lobby closes the sheet.
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.offset_left = _px(16)
	sheet.offset_right = -_px(16)
	sheet.offset_bottom = -_px(16) - _insets.y
	shade.add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _px(12))
	deed["body"].add_child(body)
	return {"root": shade, "body": body}


func _close_button(sheet: Control) -> Button:
	var close := UiTheme.button("Close", _px(14), _px(44), "ghost")
	close.pressed.connect(func() -> void: sheet.visible = false)
	return close


## Join by code: a sheet, so the field sits low and the lobby lifts it
## above the keyboard.
func _build_join_sheet() -> void:
	var sheet := _sheet(UiTheme.VIOLET, "Join a private room")
	_join_sheet = sheet["root"]
	var body: VBoxContainer = sheet["body"]
	body.add_child(UiTheme.body("Type the 6-letter code your friend shared.", _px(UiTheme.TYPE_BODY)))
	_join_row = _row(body)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Room code"
	_code_edit.max_length = 6
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0, _px(48))
	_code_edit.add_theme_font_override("font", UiTheme.display_font())
	_code_edit.add_theme_font_size_override("font_size", _px(18))
	_code_edit.add_theme_constant_override("minimum_character_width", 4)
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_code_edit.text_changed.connect(func(t: String) -> void:
		var caret := _code_edit.caret_column
		_code_edit.text = t.to_upper()
		_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join_room())
	_join_row.add_child(_code_edit)
	var join := UiTheme.button("Join", _px(14), _px(48), "primary")
	join.custom_minimum_size.x = _px(88)
	join.pressed.connect(_on_join_room)
	join.disabled = true
	_join_row.add_child(join)
	_buttons.append(join)
	body.add_child(_close_button(_join_sheet))


func _open_join_sheet() -> void:
	_join_sheet.visible = true
	_code_edit.grab_focus()


## Vs bots: three table sizes side by side (D28). One tap picks the size
## and starts the game; the size played last time wears the gold.
func _build_bots_sheet() -> void:
	var sheet := _sheet(UiTheme.VIOLET, "Play against bots")
	_bots_sheet = sheet["root"]
	var body: VBoxContainer = sheet["body"]
	body.add_child(UiTheme.body("Tap a table size to start. More bots, fewer turns for you.", _px(UiTheme.TYPE_BODY)))
	var sizes := _row(body)
	_bot_buttons.clear()
	for n in range(Net.MIN_BOTS, Net.MAX_BOTS + 1):
		var option := VBoxContainer.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_constant_override("separation", _px(4))
		sizes.add_child(option)
		var b := UiTheme.button("%d bots" % n, _px(UiTheme.TYPE_HEADING), _px(56))
		b.pressed.connect(_on_play_bots.bind(n))
		b.set_meta("bots", n)
		option.add_child(b)
		# Touch has no tooltips, so the table size is spelled out underneath.
		var players := UiTheme.caption("%d players" % (n + 1), _px(UiTheme.TYPE_CAPTION))
		players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option.add_child(players)
		_bot_buttons.append(b)
		_buttons.append(b)
	body.add_child(_close_button(_bots_sheet))


func _open_bots_sheet() -> void:
	for b in _bot_buttons:
		b.theme_type_variation = "PrimaryButton" if int(b.get_meta("bots")) == Net.bot_count else ""
	_bots_sheet.visible = true


## Friends in a sheet that fills the screen between the safe insets.
func _build_friends_sheet() -> void:
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.NIGHT, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.visible = false
	add_child(shade)
	_friends_sheet = shade
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = _px(12)
	column.offset_right = -_px(12)
	column.offset_top = _insets.x + _px(12)
	column.offset_bottom = -_insets.y - _px(12)
	column.add_theme_constant_override("separation", _px(10))
	shade.add_child(column)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_friends_panel = FriendsPanel.new()
	_friends_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_panel.join_requested.connect(func(code: String) -> void:
		_friends_sheet.visible = false
		_on_invite_join(code))
	_friends_panel.gifts_collected.connect(_refresh_profile)
	# Watching left any lobby we were in; the table opens with the first view.
	_friends_panel.watch_started.connect(func() -> void:
		_in_lobby = false
		_room_code = ""
		_friends_panel.room_code = "")
	scroll.add_child(_friends_panel)
	var close := UiTheme.button("Close", _px(14), _px(48), "ghost")
	close.pressed.connect(func() -> void: shade.visible = false)
	column.add_child(close)
	# FriendsPanel shows and hides itself with the sheet.
	shade.visibility_changed.connect(func() -> void: _friends_panel.visible = shade.visible)
	_friends_panel.visible = false


## More: rules and help, feedback to the team, your account (guest or
## linked) and the server.
func _build_more_sheet() -> void:
	var sheet := _sheet(UiTheme.VIOLET, "More")
	_more_sheet = sheet["root"]
	var body: VBoxContainer = sheet["body"]
	var rules := UiTheme.button("Rules and help", _px(14), _px(48))
	rules.pressed.connect(func() -> void:
		_more_sheet.visible = false
		_on_help())
	body.add_child(rules)
	var feedback := UiTheme.button("Send feedback or report a bug", _px(14), _px(48))
	feedback.pressed.connect(func() -> void:
		_more_sheet.visible = false
		_open_feedback_sheet())
	body.add_child(feedback)

	# Account row: guest or linked providers, with link buttons where a
	# token provider exists (iOS / Android with the plugin installed).
	var account_row := _row(body)
	var account := VBoxContainer.new()
	account.add_theme_constant_override("separation", _px(2))
	account.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	account_row.add_child(account)
	account.add_child(UiTheme.caption("Account", _px(UiTheme.TYPE_CAPTION)))
	_account_label = UiTheme.body(Net.describe_account_links({}), _px(UiTheme.TYPE_BODY))
	account.add_child(_account_label)
	# WHY a row of their own: next to the account line two link buttons left
	# it a few words per line and stretched to its height.
	_link_row = _row(body)
	_link_row.visible = false
	_link_apple_button = UiTheme.button("Link Apple", _px(13), _px(44))
	_link_apple_button.visible = false
	_link_apple_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_apple_button.pressed.connect(_on_link_apple)
	_link_row.add_child(_link_apple_button)
	_link_google_button = UiTheme.button("Link Google", _px(13), _px(44))
	_link_google_button.visible = false
	_link_google_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_link_google_button.pressed.connect(_on_link_google)
	_link_row.add_child(_link_google_button)

	var server := VBoxContainer.new()
	server.add_theme_constant_override("separation", _px(4))
	body.add_child(server)
	server.add_child(UiTheme.caption("Server", _px(UiTheme.TYPE_CAPTION)))
	var server_row := _row(server)
	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "127.0.0.1 or https://your.domain"
	_host_edit.text = Net.server_address()
	_host_edit.custom_minimum_size = Vector2(0, maxf(48, _px(44)))
	_host_edit.add_theme_font_size_override("font_size", _px(UiTheme.TYPE_LABEL))
	_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_host_edit.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())
	server_row.add_child(_host_edit)
	var connect_button := UiTheme.button("Connect", _px(13), _px(44), "primary")
	connect_button.pressed.connect(_on_connect_pressed)
	server_row.add_child(connect_button)
	body.add_child(_close_button(_more_sheet))


## Feedback to the team (FeedbackPanel), from More.
func _build_feedback_sheet() -> void:
	var sheet := _sheet(UiTheme.VIOLET, "Send feedback")
	_feedback_sheet = sheet["root"]
	_feedback_panel = FeedbackPanel.new()
	_feedback_panel.s = _s
	_feedback_panel.closed.connect(func() -> void: _feedback_sheet.visible = false)
	sheet["body"].add_child(_feedback_panel)


func _open_feedback_sheet() -> void:
	_feedback_panel.reset_view()
	_feedback_sheet.visible = true


## Lifts the lobby so a focused text field stays above the on-screen
## keyboard (phones report its height; desktops report 0).
func _process(_delta: float) -> void:
	var lift := 0.0
	var kb := _keyboard_height()
	# The name step sizes its card to the room the keyboard leaves.
	_name_prompt.keyboard_height = kb
	var focus := get_viewport().gui_get_focus_owner()
	if kb > 0 and (focus is LineEdit or focus is TextEdit) and is_ancestor_of(focus):
		var keyboard_top := get_viewport_rect().size.y - kb
		# A field may name a control under it that must stay in view with it
		# (the name step's error line and its Save button).
		var keep: Control = focus.get_meta(NamePrompt.KEEP_IN_VIEW, focus)
		var field_bottom := keep.get_global_rect().end.y - position.y + _px(12)
		lift = maxf(0.0, field_bottom - keyboard_top)
	if absf(position.y + lift) > 0.5:
		position.y = -lift


## Height of the on-screen keyboard in canvas units; 0 when it is down.
func _keyboard_height() -> float:
	if keyboard_override >= 0.0:
		return keyboard_override
	var window_h := get_window().size.y
	if window_h <= 0:
		return 0.0
	return DisplayServer.virtual_keyboard_get_height() * get_viewport_rect().size.y / float(window_h)


## Season standings in a sheet that rises from the bottom.
func _build_season_sheet() -> void:
	_season_sheet = ColorRect.new()
	_season_sheet.color = Color(UiTheme.NIGHT, 0.72)
	_season_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_season_sheet.visible = false
	_season_sheet.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_season_sheet.visible = false)
	add_child(_season_sheet)
	var deed := UiTheme.panel(UiTheme.VIOLET, "Season standings")
	var sheet: PanelContainer = deed["panel"]
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.offset_left = _px(16)
	sheet.offset_right = -_px(16)
	sheet.offset_bottom = -_px(16) - _insets.y
	_season_sheet.add_child(sheet)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _px(12))
	deed["body"].add_child(body)
	# One line above the rows: "Loading…", the empty state, or the reset rule.
	_board_label = UiTheme.body("", _px(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT)
	body.add_child(_board_label)
	# WHY a scroll: ten places plus your own are taller than a phone.
	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_board_scroll)
	_board_rows = VBoxContainer.new()
	_board_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_rows.add_theme_constant_override("separation", _px(6))
	_board_scroll.add_child(_board_rows)
	# Your own place when it is past the top ten: under the list, always
	# in view, never scrolled away.
	_board_mine = VBoxContainer.new()
	_board_mine.visible = false
	body.add_child(_board_mine)
	var close := UiTheme.button("Close", _px(14), _px(44), "ghost")
	close.pressed.connect(func() -> void: _season_sheet.visible = false)
	body.add_child(close)


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


## One tween at a time on the cluster: a quick tap must not leave the
## press and the release fighting over its scale.
func _press_identity(to: Vector2, seconds: float, curve: Tween.TransitionType) -> void:
	if _press_tween != null:
		_press_tween.kill()
	_press_tween = _identity.create_tween()
	_press_tween.tween_property(_identity, "scale", to, seconds).set_trans(curve).set_ease(Tween.EASE_OUT)


## The HUD name and the avatar's initial follow the account's name; an
## account that has not picked one shows a stand-in, not the random string.
func _show_name() -> void:
	var who := Net.display_name.strip_edges() if Net.named else ""
	_name_label.text = who if not who.is_empty() else "New investor"
	_avatar_label.text = who.substr(0, 1).to_upper() if not who.is_empty() else "?"


## The profile grows out of the avatar it was opened from.
func _open_profile() -> void:
	_quests_panel.visible = false
	_profile_panel.open(_avatar_label.get_global_rect())


## A row of the profile that belongs to another screen: close the profile
## and open that one.
func _on_profile_navigate(to: String) -> void:
	_profile_panel.close()
	match to:
		"season":
			_on_show_board()
		"clubs":
			_on_open_clubs()
		"look":
			_quests_panel.visible = true
		"plus":
			_on_open_shop()


## The name step saved a name; Net has already signed in again with it.
func _on_name_saved(_player_name: String) -> void:
	_set_named(true)
	if Net.is_connected_to_server():
		_status.text = _connected_text()


## Records whether the account has a name of its own and shows it (or the
## stand-in) on the HUD and the profile.
## WHY saved: the lobby is rebuilt after every game and must not show the
## random name while it waits for the account's answer, or offline.
func _set_named(named: bool) -> void:
	if Net.named != named:
		Net.named = named
		Net.save_settings()
	if named:
		_named_user = Net.user_id
	_profile_panel.unnamed = not named
	_show_name()


func _set_online_buttons(enabled: bool) -> void:
	for b in _buttons:
		b.disabled = not enabled


func _on_ready_pressed() -> void:
	Net.send_ready()
	_ready_button.disabled = true


func _on_start_now_pressed() -> void:
	Net.send_start_now()
	_start_now_button.disabled = true
	_status.text = "Starting with bots…"


func _on_connect_pressed() -> void:
	Net.set_server_address(_host_edit.text)
	_host_edit.text = Net.server_address()
	Net.save_settings()
	_status.text = "Connecting to %s…" % Net.server_address()
	await Net.connect_preferred()


func _on_connected() -> void:
	_connected = true
	_board_button.disabled = false
	# The session has just said which name the account holds.
	_show_name()
	_refresh_profile()
	# WHY the wait: a new player is asked for a name before they can start
	# a game, and the account answer says whether this one is new. An
	# account already known to be named (back from a game) does not wait.
	if _named_user == Net.user_id and not Net.user_id.is_empty():
		_set_named(true)
		_status.text = _connected_text()
		_set_online_buttons(true)
		_refresh_account_row()
		return
	_status.text = "Connected"
	await _refresh_account_row()
	if _connected:
		_status.text = _connected_text()
		_set_online_buttons(true)


## "Connected as Tal", or without the name while the account has only the
## random one the server made.
func _connected_text() -> String:
	return "Connected as %s" % Net.display_name if Net.named else "Connected"


func _refresh_profile() -> void:
	var data: Dictionary = await Net.get_profile()
	if data.is_empty():
		return
	_apply_progress(data.get("progress", {}), bool(data.get("dailyAvailable", false)))
	_quests_panel.apply_profile(data)
	_on_cosmetic_changed("table", Cosmetics.table)
	_refresh_quest_badge()


func _apply_progress(p: Dictionary, daily_available: bool) -> void:
	_games_played = int(p.get("gamesPlayed", 0))
	var level := int(p.get("level", 1))
	var xp := int(p.get("xp", 0))
	var floor_xp := Leveling.span(level).x
	var next_xp := Leveling.span(level).y
	_level = level
	_profile_panel.apply_progress(p)
	_profile_label.text = "Level %d" % level
	_profile_label.tooltip_text = "%d games, %d wins" % [int(p.get("gamesPlayed", 0)), int(p.get("wins", 0))]
	# From 10,000 on the figures are rounded ("12.3k / 20k") to stay inside
	# the bar; the tooltip keeps them whole.
	_xp_label.text = "%s / %s" % [_short_count(xp), _short_count(next_xp)]
	_xp_label.tooltip_text = "%d / %d XP to level %d" % [xp, next_xp, level + 1]
	_streak_label.text = str(int(p.get("streak", 0)))
	_xp_bar.min_value = floor_xp
	_xp_bar.max_value = next_xp
	_xp_bar.value = xp
	_daily_button.disabled = not daily_available
	_daily_button.wiggle = daily_available
	_daily_button.badge = "!" if daily_available else ""
	_daily_button.tooltip_text = "Claim your daily bonus" if daily_available else "Bonus claimed. Come back tomorrow"


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
	var tag := UiTheme.label("+%d XP" % amount, _px(15), Color.WHITE, true)
	tag.add_theme_color_override("font_outline_color", UiTheme.OUTLINE)
	tag.add_theme_constant_override("outline_size", _px(3))
	var chip := UiTheme.card_box(UiTheme.MINT, 8 * _s, 0)
	chip.border_color = UiTheme.OUTLINE
	chip.content_margin_left = 6 * _s
	chip.content_margin_right = 6 * _s
	chip.content_margin_top = 3 * _s
	chip.content_margin_bottom = 3 * _s
	tag.add_theme_stylebox_override("normal", chip)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag)
	var r := _daily_button.get_global_rect()
	var start := Vector2(minf(r.get_center().x - tag.get_combined_minimum_size().x / 2.0, get_viewport_rect().size.x - tag.get_combined_minimum_size().x - _px(8)), r.end.y)
	tag.global_position = start
	var tw := create_tween().set_parallel()
	tw.tween_property(tag, "global_position:y", start.y + _px(60), 1.4).set_ease(Tween.EASE_OUT)
	tw.tween_property(tag, "modulate:a", 0.0, 1.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(tag.queue_free)


func _on_toggle_quests() -> void:
	_quests_panel.visible = not _quests_panel.visible
	_refresh_quest_badge()


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
	_profile_panel.apply_look()


func _on_show_board() -> void:
	_season_sheet.visible = true
	_show_board_rows([], Net.user_id)
	_board_label.text = "Loading…"
	var rows: Array = await Net.season_leaderboard(10)
	_show_board_rows(rows, Net.user_id)


## Fills the season sheet: one row per place, yours lit up. The top ten
## take the height they need up to what the screen has left, and scroll
## beyond that; a place of yours past the top ten stays under the list.
func _show_board_rows(rows: Array, my_id: String) -> void:
	for box in [_board_rows, _board_mine]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_board_scroll.visible = not rows.is_empty()
	_board_mine.visible = false
	if rows.is_empty():
		_board_label.text = "No season games yet. Points come from games with other people, and the board resets every month."
		return
	_board_label.text = "Points from games with other people. Resets every month."
	# The server sends your own record again after the top ten; inside the
	# top ten that would show you twice.
	var seen := {}
	var own := {}
	for r in rows:
		if _board_is_mine(r, my_id):
			own[_board_key(r)] = true
	for r in rows:
		var rank := int(r.get("rank", 0))
		var key := _board_key(r)
		var mine: bool = own.has(key)
		if seen.has(key):
			continue
		seen[key] = true
		var wins := int(r.get("wins", 0))
		var detail := "%d %s%s" % [wins, "win" if wins == 1 else "wins", " · you" if mine else ""]
		var row := UiTheme.standing_row(rank, String(r.get("name", "?")), detail, str(int(r.get("score", 0))), mine)
		if mine and rank > 10:
			_board_mine.add_child(row)
			_board_mine.visible = true
		else:
			_board_rows.add_child(row)
	var gap := _px(6)
	var tall := -float(gap)
	for child in _board_rows.get_children():
		tall += child.get_combined_minimum_size().y + gap
	# Room for the band, the line above the list, your own row, Close and
	# the margins.
	var room := get_viewport_rect().size.y - _insets.x - _insets.y - _px(230 + (70 if _board_mine.visible else 0))
	_board_scroll.custom_minimum_size.y = minf(maxf(tall, 0.0), room)


## What makes two standings records the same player: the user id, or
## place and name where the server sent none.
static func _board_key(r: Dictionary) -> String:
	var uid := String(r.get("userId", ""))
	return uid if not uid.is_empty() else "rank %d %s" % [int(r.get("rank", 0)), r.get("name", "")]


static func _board_is_mine(r: Dictionary, my_id: String) -> bool:
	return bool(r.get("mine", false)) or (not my_id.is_empty() and String(r.get("userId", "")) == my_id)


static func _short_count(n: int) -> String:
	if n < 10000:
		return str(n)
	var k := n / 1000.0
	return ("%dk" % int(k)) if is_equal_approx(k, floorf(k)) or k >= 100.0 else ("%.1fk" % (floorf(k * 10.0) / 10.0))


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
	_link_row.visible = _link_apple_button.visible or _link_google_button.visible
	_link_apple_button.disabled = not Net.is_connected_to_server()
	_link_google_button.disabled = not Net.is_connected_to_server()
	_profile_panel.apply_account(links)
	_ask_name_if_new(links)


## Takes the account's answer on whether the player has picked a name.
## First launch: it still has the random name the server made, so ask for
## one before anything else. `named` is missing from a server that predates
## set_name; then nobody is asked. {} (offline) changes nothing.
func _ask_name_if_new(links: Dictionary) -> void:
	if links.is_empty():
		return
	_set_named(links.get("named") != false)
	if Net.named or _name_prompt.is_open() or _in_lobby or not Net.match_id.is_empty():
		return
	# A name typed into an earlier build's name field is offered back; the
	# random one the settings file may hold instead is not.
	var saved := _saved_name if NamesApi.problem(_saved_name).is_empty() and _saved_name != String(links.get("username", "")) else ""
	_name_prompt.open(saved, true, _level)


func _on_link_apple() -> void:
	var token: String = SocialTokens.request_apple()
	if token.is_empty():
		_status.text = "Apple sign-in was cancelled."
		_profile_panel.say(_status.text)
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
		_profile_panel.say(_status.text)
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
		_status.text = "First game: let's start with the tutorial…"
		_in_lobby = await Net.start_tutorial()
		return
	_status.text = "Finding a game…"
	_in_lobby = await Net.quick_play()


func _on_play_bots(count: int) -> void:
	_bots_sheet.visible = false
	# Leave a lobby we are waiting in first, as for an invite below.
	if not Net.match_id.is_empty():
		await Net.leave_match()
		_in_lobby = false
		_room_code = ""
		_friends_panel.room_code = ""
	_status.text = "Starting a game against bots…"
	_in_lobby = await Net.play_bots(count)


func _on_help() -> void:
	# One rules sheet at a time (one fading out does not count).
	if find_children("*", "HelpScreen", false, false).all(func(h: Node) -> bool: return h._closing):
		HelpScreen.open_over(self)


func _on_tutorial() -> void:
	_status.text = "Starting the tutorial…"
	_in_lobby = await Net.start_tutorial()


func _on_create_room() -> void:
	_status.text = "Creating room…"
	var code: String = await Net.create_room()
	if code.is_empty():
		return
	_in_lobby = true
	_room_code = code
	_friends_panel.room_code = code
	# The code shows once, in the well below; this line says what to do with it.
	_status.text = "Share the code with a friend"
	_room_label.text = "Room code  %s" % code
	_copy_button.text = "Copy"
	_room_row.visible = true
	_ready_button.visible = true
	_show_room_box(true)


func _on_join_room() -> void:
	_status.text = "Joining…"
	_in_lobby = await Net.join_room(_code_edit.text)
	if _in_lobby:
		_join_sheet.visible = false
		_code_edit.release_focus()
		_ready_button.visible = true
		_show_room_box(true)


func _on_lobby(lobby: Dictionary) -> void:
	var lines := PackedStringArray()
	var seats: Array = lobby.get("seats", [])
	var is_private: bool = lobby.get("isPrivate", false)
	lines.append("%s room · %d of %d players" % ["Private" if is_private else "Public", seats.size(), int(lobby.get("maxSeats", 0))])
	for s in seats:
		lines.append("  %s%s" % [s.get("name", "?"), " · ready" if s.get("ready", false) else ""])
	var starts := float(lobby.get("startsAt", 0))
	if starts > 0:
		var secs := maxi(0, int((starts - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
		lines.append("Starting in %ds. Empty seats become bots." % secs)
	elif is_private:
		lines.append("Starts when everyone is ready (2 or more players).")
	_lobby_label.text = "\n".join(lines)
	_lobby_label.visible = true
	_show_room_box(true)
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


## Waiting in a room swaps the play buttons for the room's own.
func _show_room_box(waiting: bool) -> void:
	_play_box.visible = not waiting
	_room_box.visible = waiting


func _on_leave_room() -> void:
	if not Net.match_id.is_empty():
		await Net.leave_match()
	_in_lobby = false
	_room_code = ""
	_friends_panel.room_code = ""
	_room_row.visible = false
	_lobby_label.visible = false
	_ready_button.visible = false
	_ready_button.disabled = false
	_start_now_button.visible = false
	_start_now_button.disabled = false
	_status.text = _connected_text() if _connected else "Not connected"
	_show_room_box(false)
