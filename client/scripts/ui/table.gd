extends Control
## The game table (portrait), after the "3D table" design canvas. Renders a
## PlayerView from the server, animates the events that precede each view,
## and sends intents.
##
## Layout (design px on a 390-wide artboard, times UiTheme.SCALE):
##   top bar        brand plate, whose turn, timer, sound / emotes / leave
##   stage          the tilted felt (TableSurface) with the supply stack,
##                  the Market, your Portfolio and the opponents' hands laid
##                  on it; opponents' plates float above their hands
##   hand           your 3-4 cards, upright, fanned in front of the table
##   bottom bar     your row (avatar, capital, pips), the prompt, the actions
## The stage shrinks (STAGE_MIN_SCALE..1) on screens shorter than the
## design so the hand still clears the bar.

const FLY_TIME := 0.35
const COIN_TIME := 0.3
## Seconds left on my turn at which the edge glow and ticks start.
const GLOW_SECONDS := 5
## Design px.
const TOP_H := 56.0
const BAR_H_TALL := 140.0
const BAR_H_SHORT := 118.0
## Height of the stage in the 844 px tall design (844 - top bar - bar).
const DESIGN_STAGE_H := 648.0
## Plane centre below the top bar in the design (400 - 56).
const PLANE_CENTER_Y := 344.0
const STAGE_MIN_SCALE := 0.7
## Card scales on the plane, relative to the 100x140 design card.
const HAND_SCALE := 0.84
const MARKET_SCALE := 0.48
const SUPPLY_SCALE := 0.48
const PORTFOLIO_SCALE := 0.36
const OPP_HAND_SCALE := 0.42
const HAND_V := 228.0
const HAND_Z := 36.0
const SUPPLY_POS := Vector2(0, -140)
## Opponent hands sit on an arc around the far side of the table: angle 0
## is straight across, +-90 the sides. Plates float above each hand.
const SEAT_ANGLES := {
	1: [0.0], 2: [-45.0, 45.0], 3: [-90.0, 0.0, 90.0], 4: [-90.0, -30.0, 30.0, 90.0],
	5: [-90.0, -45.0, 0.0, 45.0, 90.0], 6: [-90.0, -54.0, -18.0, 18.0, 54.0, 90.0],
}
## Plate centres relative to the plane centre, design px.
const PLATE_OFFSETS := {
	1: [Vector2(0, -280)],
	2: [Vector2(-105, -275), Vector2(105, -275)],
	3: [Vector2(-128, -205), Vector2(0, -280), Vector2(128, -205)],
	4: [Vector2(-133, -205), Vector2(-65, -292), Vector2(65, -292), Vector2(133, -205)],
	5: [Vector2(-128, -160), Vector2(-98, -256), Vector2(0, -312), Vector2(98, -256), Vector2(128, -160)],
	6: [Vector2(-128, -150), Vector2(-122, -235), Vector2(-62, -305), Vector2(62, -305), Vector2(122, -235), Vector2(128, -150)],
}

var view: Dictionary = {}
var _my_seat: int = -1
var _step_seconds: float = 30.0

# Widgets
var _room: TextureRect
var _top: HBoxContainer
var _status: Label
var _timer_label: Label
var _stage: Control
var _surface: TableSurface
var _seats_layer: Control
var _plates: Array[SeatView] = []
var _me_view: SeatView
var _seat_views: Array[SeatView] = []
var _opp_hands_layer: Control
var _portfolio_layer: Control
var _market_row: Control
var _supply_layer: Control
var _supply_stack: Array[CardView] = []
var _supply_pile: CardView
var _hand_layer: Control
var _hand_cards: Array[CardView] = []
var _bar: PanelContainer
var _bar_box: VBoxContainer
var _draw_button: Button
var _prompt: Label
var _keep_button: Button
var _sell_button: Button
var _cancel_button: Button
var _fx_layer: Control
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _result_panel: PanelContainer
var _result_backdrop: ColorRect
var _result_label: Label
var _result_rows: VBoxContainer

var _selected_card: int = -1
var _pending_events: Array = []
var _animating: bool = false
var _last_view: Dictionary = {}
var coach: Coach = null
var _emote_button: Button
var _emote_bar: PanelContainer
var _emote_bubbles: Dictionary = {}
var _seat_menu: PopupMenu
var _seat_menu_target: int = -1
var _reconnect_overlay: ColorRect
var _reconnect_label: Label
var _sound_button: Button
var _timer_glow: TimerGlow
## Turn-timer juice state: chime once when the turn becomes mine, tick once
## per remaining second under GLOW_SECONDS, fanfare once per dividend day.
var _was_my_turn: bool = false
var _last_tick_second: int = -1
var _timer_urgent: bool = false
var _fanfare_played: bool = false
var _last_toast_seat: int = -1
## Layout state: design px -> px, stage scale, bar height in design px,
## seat index -> arc angle for the last render.
var _k0: float = UiTheme.SCALE
var _g: float = 1.0
var _bar_h: float = BAR_H_TALL
var _seat_angles: Dictionary = {}


func _ready() -> void:
	_build_layout()
	_relayout()
	resized.connect(_relayout)
	if Net.tutorial_mode:
		enable_coach()
	Net.view_updated.connect(_on_view)
	Net.events_received.connect(_on_events)
	Net.server_error.connect(_on_error)
	Net.connection_failed.connect(_on_connection_failed)
	Net.emote_shown.connect(_on_emote_shown)
	Net.reconnecting.connect(_on_reconnecting)
	Net.reconnected.connect(_on_reconnected)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _px(design: float) -> float:
	return roundf(design * _k0)


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_room = UiTheme.room_background(Cosmetics.table_bg_color())
	add_child(_room)

	# Stage: the felt and everything lying on it.
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_stage)
	_surface = TableSurface.new()
	_surface.set_colors(Cosmetics.table_bg_color(), Cosmetics.table_edge_color())
	_stage.add_child(_surface)
	_opp_hands_layer = _layer(_stage)
	_portfolio_layer = _layer(_stage)
	_market_row = _layer(_stage)
	_supply_layer = _layer(_stage)
	for i in 3:
		var back := CardView.new()
		back.setup(-1, 0, 0, false)
		back.selectable = false
		_supply_layer.add_child(back)
		_supply_stack.append(back)
	_supply_pile = CardView.new()
	_supply_pile.setup(-1, 0, 0, false)
	_supply_pile.selectable = false
	_supply_pile.card_pressed.connect(func(_id: int) -> void: _on_draw_pressed())
	_supply_layer.add_child(_supply_pile)
	_seats_layer = _layer(_stage)

	# Top bar.
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", int(_px(10)))
	add_child(_top)
	var brand := PanelContainer.new()
	var brand_style := HardBox.new(Companies.ALERT, _px(6), _px(2))
	brand_style.border_width = _px(2)
	brand_style.set_content_margin_all(_px(5))
	brand_style.content_margin_left = _px(8)
	brand_style.content_margin_right = _px(8)
	brand.add_theme_stylebox_override("panel", brand_style)
	brand.add_child(UiTheme.label("BIG BUSINESS", 10.5, "heavy", Color.WHITE))
	_top.add_child(brand)
	_status = UiTheme.label("Connecting...", 14, "bold", Companies.CARD_FACE)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top.add_child(_status)
	_timer_label = UiTheme.label("", 15, "display", Companies.PRIMARY)
	_top.add_child(_timer_label)
	_sound_button = UiTheme.button("", "GhostButton", 36)
	_sound_button.toggle_mode = true
	_sound_button.button_pressed = Sfx.enabled
	_sound_button.tooltip_text = "Sound on/off"
	_sound_button.custom_minimum_size = Vector2(_px(40), _px(36))
	var speaker := GlyphIcon.new("speaker" if Sfx.enabled else "speaker_off", _px(20))
	_centre_icon(speaker, _px(20))
	_sound_button.add_child(speaker)
	_sound_button.toggled.connect(func(on: bool) -> void:
		Sfx.enabled = on
		speaker.set_kind("speaker" if on else "speaker_off"))
	_top.add_child(_sound_button)
	_emote_button = UiTheme.button("", "GhostButton", 36)
	_emote_button.tooltip_text = "Emotes"
	_emote_button.custom_minimum_size = Vector2(_px(40), _px(36))
	_emote_button.pressed.connect(_toggle_emote_bar)
	_emote_button.add_child(_make_emote_icon("laugh", _px(20)))
	_top.add_child(_emote_button)
	var leave := UiTheme.button("Leave", "GhostButton", 36)
	leave.add_theme_font_size_override("font_size", int(_px(12)))
	leave.pressed.connect(_on_leave)
	_top.add_child(leave)

	# Bottom bar: my row, the prompt, the actions.
	_bar = PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Companies.CARD_FACE
	bar_style.border_color = Companies.INK
	bar_style.border_width_top = int(_px(2))
	bar_style.corner_radius_top_left = int(_px(20))
	bar_style.corner_radius_top_right = int(_px(20))
	bar_style.shadow_color = Color(0, 0, 0, 0.3)
	bar_style.shadow_size = int(_px(14))
	bar_style.shadow_offset = Vector2(0, -_px(6))
	bar_style.content_margin_left = _px(14)
	bar_style.content_margin_right = _px(14)
	bar_style.content_margin_top = _px(10)
	bar_style.content_margin_bottom = _px(14)
	bar_style.anti_aliasing = true
	_bar.add_theme_stylebox_override("panel", bar_style)
	add_child(_bar)
	_bar_box = VBoxContainer.new()
	_bar_box.add_theme_constant_override("separation", int(_px(7)))
	_bar.add_child(_bar_box)
	_me_view = SeatView.new()
	_me_view.compact = true
	_me_view.custom_minimum_size = Vector2(0, _px(26))
	_me_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_me_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_box.add_child(_me_view)
	_prompt = UiTheme.label("", 14, "body")
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(0, _px(36))
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_box.add_child(_prompt)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(_px(8)))
	_bar_box.add_child(buttons)
	_draw_button = _make_button(buttons, "Draw from supply", _on_draw_pressed, "PrimaryButton")
	_keep_button = _make_button(buttons, "Keep", _on_keep_pressed, "PrimaryButton")
	_sell_button = _make_button(buttons, "Sell to Market", _on_sell_pressed, "")
	_cancel_button = _make_button(buttons, "Cancel", _on_cancel_pressed, "GhostButton")
	_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END

	# Hand: upright cards in front of the table, above the bar.
	_hand_layer = Control.new()
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_layer)

	# Effects overlay (flying cards and coins).
	_fx_layer = Control.new()
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	# Turn-timer glow: red vignette along the edges under GLOW_SECONDS.
	_timer_glow = TimerGlow.new()
	_timer_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_timer_glow)
	_build_social_layer()

	# Toast pill: "Intern Ivy's turn".
	_toast = PanelContainer.new()
	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Companies.INK
	toast_style.set_corner_radius_all(int(_px(20)))
	toast_style.content_margin_left = _px(16)
	toast_style.content_margin_right = _px(16)
	toast_style.content_margin_top = _px(10)
	toast_style.content_margin_bottom = _px(10)
	toast_style.shadow_color = Color(0, 0, 0, 0.35)
	toast_style.shadow_size = int(_px(6))
	toast_style.anti_aliasing = true
	_toast.add_theme_stylebox_override("panel", toast_style)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_toast_label = UiTheme.label("", 14, "bold", Companies.CARD_FACE)
	_toast.add_child(_toast_label)
	add_child(_toast)

	# Result panel (dividend day): dimmed backdrop + centred deed-style panel.
	_result_backdrop = ColorRect.new()
	_result_backdrop.color = Color("#0A1610", 0.6)
	_result_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_backdrop.visible = false
	add_child(_result_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_backdrop.add_child(center)
	var deed := UiTheme.deed_panel(Companies.GOLD, "Dividend day", Companies.INK)
	_result_panel = deed["panel"]
	_result_panel.custom_minimum_size = Vector2(_px(350), 0)
	deed["title"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	deed["title"].add_theme_font_size_override("font_size", int(_px(20)))
	center.add_child(_result_panel)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", int(_px(8)))
	deed["body"].add_child(result_box)
	_result_label = UiTheme.label("", 11, "body", Companies.CAPTION)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_box.add_child(_result_label)
	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", 0)
	result_box.add_child(_result_rows)
	var result_buttons := HBoxContainer.new()
	result_buttons.add_theme_constant_override("separation", int(_px(8)))
	result_box.add_child(result_buttons)
	_make_button(result_buttons, "Play again", _on_play_again, "PrimaryButton").visible = true
	_make_button(result_buttons, "Leave", _on_leave, "GhostButton").visible = true


func _layer(parent: Control) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(c)
	return c


## Fit the top bar, stage, hand and bar to the current size and re-project.
func _relayout() -> void:
	var w := size.x if size.x > 0 else 720.0
	var h := size.y if size.y > 0 else 1280.0
	_k0 = w / 390.0
	var design_h := h / _k0
	_bar_h = BAR_H_TALL if design_h >= 800.0 else BAR_H_SHORT
	_g = clampf((design_h - TOP_H - _bar_h) / DESIGN_STAGE_H, STAGE_MIN_SCALE, 1.0)
	_top.position = Vector2(_px(12), 0)
	_top.size = Vector2(w - _px(24), _px(TOP_H))
	var stage_top := _px(TOP_H)
	var bar_top := h - _px(_bar_h)
	_stage.position = Vector2(0, stage_top)
	_stage.size = Vector2(w, bar_top - stage_top)
	for layer in [_surface, _opp_hands_layer, _portfolio_layer, _market_row, _supply_layer, _seats_layer]:
		layer.position = Vector2.ZERO
		layer.size = _stage.size
	_hand_layer.position = _stage.position
	_hand_layer.size = _stage.size
	_surface.k = _k0 * _g
	_surface.center = Vector2(w / 2.0, PLANE_CENTER_Y * _g * _k0)
	_bar.position = Vector2(0, bar_top)
	_bar.size = Vector2(w, _px(_bar_h))
	_bar.custom_minimum_size = Vector2(0, _px(_bar_h))
	_toast.position = Vector2(w / 2.0 - _toast.size.x / 2.0, _px(TOP_H + 8))
	_emote_bar.position = Vector2(_px(12), _px(TOP_H + 6))
	_emote_bar.size = Vector2(w - _px(24), 0)
	if not view.is_empty() and not _animating:
		_render()


func _build_social_layer() -> void:
	# Emote bar: a deed-style strip of preset emotes and phrases under the top bar.
	_emote_bar = PanelContainer.new()
	_emote_bar.visible = false
	var bar_style := HardBox.new(Companies.CARD_FACE, _px(10), _px(3))
	bar_style.border_width = _px(2)
	bar_style.set_content_margin_all(_px(6))
	_emote_bar.add_theme_stylebox_override("panel", bar_style)
	add_child(_emote_bar)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", int(_px(4)))
	grid.add_theme_constant_override("v_separation", int(_px(6)))
	_emote_bar.add_child(grid)
	for e in Protocol.EMOTES:
		var b := Button.new()
		var id: String = e["id"]
		if Protocol.is_icon(id):
			b.add_child(_make_emote_icon(id, _px(18)))
		else:
			b.text = e["text"]
		b.custom_minimum_size = Vector2(0, _px(36))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", int(_px(11)))
		b.pressed.connect(func() -> void:
			Net.send_emote(id)
			_emote_bar.visible = false)
		grid.add_child(b)

	# Seat menu: mute, report, block. Opened by tapping an opponent's plate.
	_seat_menu = PopupMenu.new()
	_seat_menu.add_item("Mute", 0)
	_seat_menu.add_item("Report", 1)
	_seat_menu.add_item("Block", 2)
	_seat_menu.id_pressed.connect(_on_seat_menu)
	add_child(_seat_menu)

	# Reconnect overlay.
	_reconnect_overlay = ColorRect.new()
	_reconnect_overlay.color = Color("#0A1610", 0.6)
	_reconnect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reconnect_overlay.visible = false
	add_child(_reconnect_overlay)
	var rc := CenterContainer.new()
	rc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reconnect_overlay.add_child(rc)
	var deed := UiTheme.deed_panel(Companies.CHEST, "Reconnecting", Color.WHITE)
	deed["panel"].custom_minimum_size = Vector2(_px(300), 0)
	_reconnect_label = UiTheme.label("", 15, "body")
	_reconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reconnect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deed["body"].add_child(_reconnect_label)
	rc.add_child(deed["panel"])


func _toggle_emote_bar() -> void:
	_emote_bar.visible = not _emote_bar.visible


## A drawn emote centred inside a button. It ignores the mouse so the
## button underneath still gets the tap.
func _make_emote_icon(id: String, px: float) -> EmoteIcon:
	var icon := EmoteIcon.new(id)
	icon.custom_minimum_size = Vector2(px, px)
	_centre_icon(icon, px)
	return icon


## Centre a px-square icon inside its parent button.
## WHY: explicit offsets rather than set_anchors_and_offsets_preset, whose
## MINSIZE mode ignores custom_minimum_size on a plain Control and would
## leave the icon in the button's bottom-right quadrant.
func _centre_icon(icon: Control, px: float) -> void:
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.offset_left = -px / 2.0
	icon.offset_top = -px / 2.0
	icon.offset_right = px / 2.0
	icon.offset_bottom = px / 2.0


func _on_emote_shown(seat: int, emote: String) -> void:
	var seats: Array = view.get("seats", [])
	if seat < 0 or seat >= seats.size():
		return
	if Net.is_muted(String(seats[seat].get("id", ""))):
		return
	if not Protocol.is_emote(emote):
		return
	_show_bubble(seat, emote)


## A speech bubble over a seat: a drawn icon for icon emotes, text for phrases.
func _show_bubble(seat: int, emote: String) -> void:
	var old = _emote_bubbles.get(seat)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var bubble := PanelContainer.new()
	var style := HardBox.new(Companies.PANEL, _px(10), _px(2))
	style.border_width = _px(2)
	style.set_content_margin_all(_px(6))
	bubble.add_theme_stylebox_override("panel", style)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Protocol.is_icon(emote):
		var icon := EmoteIcon.new(emote)
		icon.custom_minimum_size = Vector2(_px(24), _px(24))
		bubble.add_child(icon)
	else:
		bubble.add_child(UiTheme.label(Protocol.emote_text(emote), 13, "bold"))
	_fx_layer.add_child(bubble)
	var anchor := _seat_anchor(seat)
	bubble.global_position = anchor + Vector2(_px(16), -_px(30))
	bubble.modulate.a = 0.0
	_emote_bubbles[seat] = bubble
	var tw := create_tween()
	tw.tween_property(bubble, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bubble.queue_free)


func _on_seat_pressed(seat_idx: int, at: Vector2) -> void:
	if seat_idx == _my_seat:
		return
	var seats: Array = view.get("seats", [])
	if seat_idx >= seats.size() or seats[seat_idx].get("isBot", false):
		return
	_seat_menu_target = seat_idx
	var uid := String(seats[seat_idx].get("id", ""))
	_seat_menu.set_item_text(0, "Unmute" if Net.is_muted(uid) else "Mute")
	_seat_menu.position = Vector2i(at)
	_seat_menu.popup()


func _on_seat_menu(id: int) -> void:
	var seats: Array = view.get("seats", [])
	if _seat_menu_target < 0 or _seat_menu_target >= seats.size():
		return
	var uid := String(seats[_seat_menu_target].get("id", ""))
	var who := String(seats[_seat_menu_target].get("name", "player"))
	match id:
		0:
			Net.mute_player(uid, not Net.is_muted(uid))
			_show_toast("%s %s" % [who, "muted" if Net.is_muted(uid) else "unmuted"])
		1:
			var ok: bool = await Net.report_player(uid, "behaviour")
			_show_toast("Report sent. Thank you." if ok else "Report failed, try again")
		2:
			await Net.block_player(uid)
			_show_toast("%s blocked" % who)


func _on_reconnecting(attempt: int) -> void:
	_reconnect_overlay.visible = true
	_reconnect_label.text = "Connection lost. Trying again (%d/5)..." % attempt


func _on_reconnected() -> void:
	_reconnect_overlay.visible = false
	if Net.match_id.is_empty():
		_status.text = "Could not rejoin the game"


func _on_connection_failed(reason: String) -> void:
	_reconnect_overlay.visible = false
	_status.text = reason


func _make_button(parent: Control, text: String, handler: Callable, variation: String) -> Button:
	var b := UiTheme.button(text, variation, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(handler)
	b.visible = false
	parent.add_child(b)
	return b


## Attach the tutorial coach overlay (idempotent).
func enable_coach() -> void:
	if coach != null:
		return
	coach = Coach.new()
	# Skipping the coach counts as done, like leaving the tutorial early does.
	coach.finished.connect(Net.mark_tutorial_done)
	add_child(coach)


## A short dark pill under the top bar that fades on its own.
func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast.modulate.a = 0.0
	_toast.reset_size()
	_toast.position = Vector2(size.x / 2.0 - _toast.size.x / 2.0, _px(TOP_H + 8))
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_draw_pressed() -> void:
	if not _is_my_turn() or view.get("phase") != "take" or not _legal("take_supply"):
		return
	if coach != null and not coach.allows(Protocol.take_supply()):
		return
	Net.send_action(Protocol.take_supply())
	_set_buttons_enabled(false)


func _on_market_card_pressed(card_id: int) -> void:
	if not _is_my_turn() or view.get("phase") != "take":
		return
	Net.send_action(Protocol.take_market(card_id))
	_set_buttons_enabled(false)


func _on_hand_card_pressed(card_id: int) -> void:
	if not _is_my_turn() or view.get("phase") != "play":
		return
	_selected_card = -1 if _selected_card == card_id else card_id
	for cv in _hand_cards:
		cv.selected = cv.card_id == _selected_card
	_update_prompt()


func _on_keep_pressed() -> void:
	if _selected_card >= 0:
		Net.send_action(Protocol.play_portfolio(_selected_card))
		_set_buttons_enabled(false)


func _on_sell_pressed() -> void:
	if _selected_card >= 0:
		Net.send_action(Protocol.play_market(_selected_card))
		_set_buttons_enabled(false)


func _on_cancel_pressed() -> void:
	_selected_card = -1
	for cv in _hand_cards:
		cv.selected = false
	_update_prompt()


func _on_leave() -> void:
	Sfx.stop_all()
	await Net.leave_match()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_play_again() -> void:
	await Net.leave_match()
	_status.text = "Finding a new game..."
	_result_backdrop.visible = false
	var ok: bool = await Net.quick_play()
	if not ok:
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _set_buttons_enabled(enabled: bool) -> void:
	for b in [_draw_button, _keep_button, _sell_button, _cancel_button]:
		b.disabled = not enabled


# ---------------------------------------------------------------------------
# Server messages
# ---------------------------------------------------------------------------

func _on_error(message: String) -> void:
	_show_toast("Error: %s" % message)
	_set_buttons_enabled(true)


func _on_events(_seq: int, events: Array) -> void:
	_pending_events.append_array(events)
	if coach != null:
		coach.on_events(events)


func _on_view(v: Dictionary) -> void:
	_last_view = view
	view = v
	_my_seat = int(v.get("you", -1)) if v.get("you") != null else -1
	if not _last_view.is_empty() and not _pending_events.is_empty():
		_play_events_then_render()
	else:
		_pending_events.clear()
		_render()


func _process(_delta: float) -> void:
	if view.is_empty():
		return
	var deadline := float(view.get("deadline", 0))
	if deadline <= 0 or view.get("phase") == "ended":
		_timer_label.text = ""
		_set_glow(false)
		return
	var remaining := int(ceil((deadline - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	_timer_label.text = "%ds" % maxi(remaining, 0)
	# Under GLOW_SECONDS on my turn: pulse the edge glow and tick once per second.
	var urgent := _is_my_turn() and remaining > 0 and remaining <= GLOW_SECONDS
	# WHY: a theme override re-shapes the label, so apply it only on a change.
	if urgent != _timer_urgent:
		_timer_urgent = urgent
		_timer_label.add_theme_color_override("font_color", Companies.ALERT if urgent else Companies.PRIMARY)
	_set_glow(urgent)
	if urgent and remaining != _last_tick_second:
		_last_tick_second = remaining
		Sfx.play("timer_tick")


func _set_glow(on: bool) -> void:
	if _timer_glow.visible != on:
		_timer_glow.visible = on
	if not on:
		_last_tick_second = -1


func _is_my_turn() -> bool:
	return _my_seat >= 0 and int(view.get("active", -1)) == _my_seat and view.get("phase") != "ended"


func _legal(type: String, card_id: int = -1) -> bool:
	for a in view.get("legal", []):
		if a.get("type") != type:
			continue
		if card_id < 0 or int(a.get("cardId", -1)) == card_id:
			return true
	return false


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render() -> void:
	if view.is_empty():
		return
	var phase := String(view.get("phase", ""))
	var seats: Array = view.get("seats", [])
	var active := int(view.get("active", 0))
	_selected_card = -1

	if coach != null:
		# WHY: the supply, Market and hand below ask the coach what is allowed,
		# and coach.on_view only runs at the end of the render; track() gives
		# it the view first, so a forced move never leaves the previous turn's
		# target tappable.
		coach.track(view)
	_render_status(phase, seats, active)
	_notify_turn_start()
	_render_seats(seats, active, phase)
	_render_supply(phase)
	_render_market(phase)
	_render_portfolio(seats)
	_render_hand(seats, phase)
	_update_prompt()
	_render_result(seats)
	if coach != null:
		coach.targets = _coach_targets()
		coach.on_view(view)


## Chime and a short buzz when the active seat becomes mine.
## WHY: compared against a flag, not _last_view, because the same view
## dictionary may be re-rendered (tests, reconnect) and must not re-chime.
func _notify_turn_start() -> void:
	var mine := _is_my_turn()
	if mine and not _was_my_turn:
		Sfx.play("turn_chime")
		Input.vibrate_handheld(40)
	_was_my_turn = mine


func _render_status(phase: String, seats: Array, active: int) -> void:
	if phase == "ended":
		_status.text = "Dividend day"
		return
	if _is_my_turn():
		_status.text = "Your turn"
		_last_toast_seat = -1
		return
	var who: Dictionary = seats[active] if active < seats.size() else {}
	var name := String(who.get("name", "?"))
	_status.text = "%s's turn" % name
	if active != _last_toast_seat and not _last_view.is_empty():
		_show_toast("%s's turn" % name)
	_last_toast_seat = active


## Opponents' plates float above their hands on the far side of the table;
## my own row lives in the bottom bar.
func _render_seats(seats: Array, active: int, phase: String) -> void:
	# Opponents are listed clockwise starting after me so the arc reads in turn order.
	var order: Array[int] = []
	var n := seats.size()
	var start := _my_seat if _my_seat >= 0 else 0
	for k in range(1, n):
		order.append((start + k) % n)
	var count := mini(order.size(), 6)
	var angles: Array = SEAT_ANGLES.get(count, SEAT_ANGLES[6])
	var offsets: Array = PLATE_OFFSETS.get(count, PLATE_OFFSETS[6])
	while _plates.size() < order.size():
		var sv := SeatView.new()
		sv.seat_pressed.connect(_on_seat_pressed)
		_seats_layer.add_child(sv)
		_plates.append(sv)
	for sv in _plates:
		sv.visible = false
	_seat_angles.clear()
	var plate_scale := _g * (0.85 if count >= 5 else 1.0)
	var deadline := float(view.get("deadline", 0))
	for i in order.size():
		var seat_idx := order[i]
		var sv := _plates[i]
		var slot: Vector2 = offsets[mini(i, offsets.size() - 1)]
		_seat_angles[seat_idx] = float(angles[mini(i, angles.size() - 1)])
		sv.scale = Vector2(plate_scale, plate_scale)
		var c := _surface.center + slot * _surface.k
		sv.position = c - Vector2(SeatView.W, SeatView.H) * plate_scale / 2.0
		sv.visible = true
		sv.update(seat_idx, seats[seat_idx], seat_idx == active and phase != "ended", false, deadline, _step_seconds)
	_seat_views = _plates.duplicate()
	_seat_views.append(_me_view)
	if _my_seat >= 0 and _my_seat < n:
		_me_view.visible = true
		_me_view.update(_my_seat, seats[_my_seat], _my_seat == active and phase != "ended", true, deadline, _step_seconds)
	else:
		_me_view.visible = false
	_render_opponent_hands(seats, order)


## Face-down fans on the felt, one per opponent, at that seat's arc angle.
func _render_opponent_hands(seats: Array, order: Array[int]) -> void:
	for child in _opp_hands_layer.get_children():
		_opp_hands_layer.remove_child(child)
		child.queue_free()
	for seat_idx in order:
		var count := int(seats[seat_idx].get("handCount", 0))
		var a := float(_seat_angles.get(seat_idx, 0.0))
		var hand_pos := _hand_pos_for_angle(a)
		var ang := 180.0 + a
		var rad := deg_to_rad(ang)
		for i in count:
			var off := i - (count - 1) / 2.0
			var lx := off * 20.0
			var ly := off * off * 2.5
			var u := hand_pos.x + lx * cos(rad) - ly * sin(rad)
			var v := hand_pos.y + lx * sin(rad) + ly * cos(rad)
			var cv := CardView.new()
			cv.setup(-1, 0, 0, false)
			cv.selectable = false
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_opp_hands_layer.add_child(cv)
			_place_flat(cv, u, v, 10.0, OPP_HAND_SCALE, ang + off * 9.0, cos(deg_to_rad(10.0)))


func _hand_pos_for_angle(a_deg: float) -> Vector2:
	var a := deg_to_rad(a_deg)
	return Vector2(150.0 * sin(a), -150.0 - 112.0 * cos(a))


## Size and place a card lying on the felt at table point (u, v), height z,
## design scale s, rotated (screen space) by rot_deg and foreshortened by
## `squash`.
func _place_flat(cv: CardView, u: float, v: float, z: float, s: float, rot_deg: float, squash: float) -> void:
	var f := _surface.factor(v, z)
	var w := 100.0 * s * f * _surface.k
	var h := 140.0 * s * f * _surface.k * squash
	cv.set_card_size(w, h)
	var c := _surface.project(u, v, z)
	cv.set_rest_position(c - Vector2(w, h) / 2.0)
	cv.rotation = deg_to_rad(rot_deg)


func _render_supply(phase: String) -> void:
	var supply := int(view.get("supplyCount", 0))
	_surface.supply_count = supply
	_surface.queue_redraw()
	var tilts := [-1.6, 0.8, -0.4]
	for i in _supply_stack.size():
		var back := _supply_stack[i]
		back.visible = supply > i + 1
		_place_flat(back, SUPPLY_POS.x, SUPPLY_POS.y - i * 0.9, 0.5 + i * 0.35, SUPPLY_SCALE, tilts[i], _surface.squash())
	_supply_pile.visible = supply > 0
	_place_flat(_supply_pile, SUPPLY_POS.x, SUPPLY_POS.y - 2.7, 1.6, SUPPLY_SCALE, 0.0, _surface.squash())
	var draw_ok := _is_my_turn() and phase == "take" and _legal("take_supply") \
		and (coach == null or coach.allows(Protocol.take_supply()))
	_supply_pile.selectable = draw_ok
	_surface.set_glow("supply", draw_ok)


func _render_market(phase: String) -> void:
	for child in _market_row.get_children():
		_market_row.remove_child(child)
		child.queue_free()
	var seats: Array = view.get("seats", [])
	var my_tokens: Array = seats[_my_seat].get("tokens", []) if _my_seat >= 0 and _my_seat < seats.size() else []
	var market: Array = view.get("market", [])
	var m := market.size()
	for k in m:
		var slot: Dictionary = market[k]
		var card: Dictionary = slot.get("card", {})
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), int(card.get("company", 0)), int(slot.get("coins", 0)))
		cv.locked = my_tokens.has(cv.company)
		cv.selectable = _is_my_turn() and phase == "take" and _legal("take_market", cv.card_id) \
			and (coach == null or coach.allows(Protocol.take_market(cv.card_id)))
		cv.card_pressed.connect(_on_market_card_pressed)
		_market_row.add_child(cv)
		var p := _market_pos(k, m)
		_place_flat(cv, p.x, p.y, 1.0, MARKET_SCALE, ((cv.card_id * 5) % 3 - 1) * 1.5, _surface.squash())
		if coach != null and cv.selectable and coach.highlight_card_id == cv.card_id:
			cv.pulse()


## Market slot k of m on the felt: up to five per row, two rows.
func _market_pos(k: int, m: int) -> Vector2:
	var per := maxi(5, int(ceil(m / 2.0)))
	var row := k / per
	var in_row := mini(per, m) if row == 0 else m - per
	var col := k % per
	var sp := minf(54.0, 264.0 / per)
	return Vector2((col - (in_row - 1) / 2.0) * sp, -52.0 + row * 72.0)


## My kept shares, face up in small stacks grouped by company.
func _render_portfolio(seats: Array) -> void:
	for child in _portfolio_layer.get_children():
		_portfolio_layer.remove_child(child)
		child.queue_free()
	if _my_seat < 0 or _my_seat >= seats.size():
		return
	var groups: Array = []
	for company in 6:
		var l: Array = []
		for card in seats[_my_seat].get("portfolio", []):
			if int(card.get("company", 0)) == company:
				l.append(card)
		if not l.is_empty():
			groups.append(l)
	for gi in groups.size():
		var l: Array = groups[gi]
		for j in l.size():
			var cv := CardView.new()
			cv.setup(int(l[j].get("id", -1)), int(l[j].get("company", 0)))
			cv.selectable = false
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_portfolio_layer.add_child(cv)
			_place_flat(cv, (gi - (groups.size() - 1) / 2.0) * 46.0, 92.0 + j * 10.0, 1.0 + j * 0.6, PORTFOLIO_SCALE, 0.0, _surface.squash())


func _render_hand(seats: Array, phase: String) -> void:
	for cv in _hand_cards:
		_hand_layer.remove_child(cv)
		cv.queue_free()
	_hand_cards.clear()
	if _my_seat < 0 or _my_seat >= seats.size():
		return
	var me: Dictionary = seats[_my_seat]
	var hand: Array = me.get("hand", [])
	hand = hand.duplicate()
	# WHY: sorted by company so same-company shares sit together in the fan.
	hand.sort_custom(func(a, b) -> bool:
		if int(a.get("company", 0)) != int(b.get("company", 0)):
			return int(a.get("company", 0)) < int(b.get("company", 0))
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	var count := hand.size()
	for i in count:
		var card: Dictionary = hand[i]
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), int(card.get("company", 0)))
		var off := i - (count - 1) / 2.0
		_place_hand_card(cv, off)
		var can_play := _is_my_turn() and phase == "play"
		cv.selectable = can_play and (coach == null or coach.allows(Protocol.play_portfolio(cv.card_id)) \
			or coach.allows(Protocol.play_market(cv.card_id)))
		cv.card_pressed.connect(_on_hand_card_pressed)
		_hand_layer.add_child(cv)
		_hand_cards.append(cv)
		if coach != null and cv.selectable and coach.highlight_card_id == cv.card_id:
			cv.pulse()


## An upright card in the fan: fanned by 7 degrees per slot, on a shallow arc.
func _place_hand_card(cv: CardView, off: float) -> void:
	var v := HAND_V + off * off * 4.0
	var f := _surface.factor(v, HAND_Z)
	var w := 100.0 * HAND_SCALE * f * _surface.k
	var h := 140.0 * HAND_SCALE * f * _surface.k
	cv.set_card_size(w, h)
	var c := _surface.project(off * 54.0, v, HAND_Z)
	cv.set_rest_position(c - Vector2(w, h) / 2.0)
	cv.rotation = deg_to_rad(off * 7.0)


func _update_prompt() -> void:
	var phase := String(view.get("phase", ""))
	var mine := _is_my_turn()
	_draw_button.visible = false
	_keep_button.visible = false
	_sell_button.visible = false
	_cancel_button.visible = false
	_set_buttons_enabled(true)
	_surface.set_glow("market", false)
	_surface.set_glow("portfolio", false)
	if phase == "ended":
		_prompt.text = "The supply is empty. Dividends are paid."
		return
	if not mine:
		var seats: Array = view.get("seats", [])
		var active := int(view.get("active", 0))
		var who := String(seats[active].get("name", "?")) if active < seats.size() else "?"
		_prompt.text = "%s is %s" % [who, "choosing a share…" if phase == "take" else "playing a share…"]
		return
	if phase == "take":
		var market: Array = view.get("market", [])
		var cost = view.get("drawCost")
		var can_draw := _legal("take_supply")
		if market.is_empty():
			_prompt.text = "Tap the supply to draw a share. The Market is empty, so it costs nothing."
		elif can_draw:
			var n := int(cost) if cost != null else 0
			_prompt.text = "Draw from the supply (%s onto the Market), or tap a Market share to take it with its coins." % ("free" if n == 0 else "%d capital" % n)
		else:
			_prompt.text = "Not enough capital to draw. Take a share from the Market."
		_draw_button.visible = true
		_draw_button.disabled = not can_draw or not (coach == null or coach.allows(Protocol.take_supply()))
		return
	# Play step.
	if _selected_card < 0:
		_prompt.text = "Tap a share in your hand to play it."
		return
	var company := -1
	for cv in _hand_cards:
		if cv.card_id == _selected_card:
			company = cv.company
	_prompt.text = "%s: keep it in your Portfolio or sell it to the Market?" % Companies.name_of(company)
	_keep_button.visible = true
	_sell_button.visible = true
	_cancel_button.visible = true
	_keep_button.disabled = not _legal("play_portfolio", _selected_card) \
		or not (coach == null or coach.allows(Protocol.play_portfolio(_selected_card)))
	_sell_button.disabled = not _legal("play_market", _selected_card) \
		or not (coach == null or coach.allows(Protocol.play_market(_selected_card)))
	_surface.set_glow("portfolio", not _keep_button.disabled)
	_surface.set_glow("market", not _sell_button.disabled)


func _render_result(seats: Array) -> void:
	var result = view.get("result")
	_result_backdrop.visible = result != null
	if result == null:
		_fanfare_played = false
		return
	if not _fanfare_played:
		_fanfare_played = true
		Sfx.play("dividend_fanfare")
	var lines := PackedStringArray()
	for div in result.get("companies", []):
		var company := int(div.get("company", 0))
		var majority = div.get("majority")
		if majority == null:
			lines.append("%s: no majority, no dividend" % Companies.name_of(company))
		else:
			var paid := 0
			for p in div.get("payments", []):
				paid += int(p.get("coins", 0))
			lines.append("%s: %s collects %d" % [Companies.name_of(company), seats[int(majority)].get("name", "?"), paid])
	_result_label.text = "\n".join(lines)
	for child in _result_rows.get_children():
		_result_rows.remove_child(child)
		child.queue_free()
	var scores: Array = result.get("scores", []).duplicate()
	scores.sort_custom(func(a, b) -> bool: return int(a.get("rank", 0)) < int(b.get("rank", 0)))
	for sc in scores:
		var seat: Dictionary = seats[int(sc.get("seat", 0))]
		var rank := int(sc.get("rank", 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(_px(10)))
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color.TRANSPARENT
		row_style.border_color = Color(Companies.INK, 0.2)
		row_style.border_width_bottom = 1
		row_style.content_margin_top = _px(8)
		row_style.content_margin_bottom = _px(8)
		var wrap := PanelContainer.new()
		wrap.add_theme_stylebox_override("panel", row_style)
		wrap.add_child(row)
		var place := UiTheme.label(str(rank), 16, "display")
		place.custom_minimum_size = Vector2(_px(22), 0)
		row.add_child(place)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var who := String(seat.get("name", "?")) + (" (you)" if int(sc.get("seat", -1)) == _my_seat else "")
		names.add_child(UiTheme.label(who, 14, "bold" if rank == 1 else "body"))
		names.add_child(UiTheme.label("%d bronze + %d gold" % [int(sc.get("bronze", 0)), int(sc.get("gold", 0))], 11, "body", Companies.CAPTION))
		row.add_child(names)
		row.add_child(UiTheme.label(str(int(sc.get("score", 0))), 18, "display"))
		_result_rows.add_child(wrap)


## Screen regions the tutorial coach can spotlight (global px).
func _coach_targets() -> Dictionary:
	var stage_origin := _stage.global_position
	var supply_rect := Rect2(_supply_pile.global_position, _supply_pile.size).grow(_px(12))
	var market_rect := _surface.zone_rect("market")
	market_rect.position += stage_origin
	market_rect = market_rect.grow(_px(6))
	var bar_rect := Rect2(_bar.global_position, _bar.size)
	var hand_rect := bar_rect
	for cv in _hand_cards:
		hand_rect = hand_rect.merge(Rect2(cv.global_position, cv.size).grow(_px(10)))
	var me_rect := Rect2(_me_view.global_position, _me_view.size).grow(_px(8))
	return {"supply": supply_rect, "market": market_rect, "hand": hand_rect, "bar": me_rect}


# ---------------------------------------------------------------------------
# Animations: play the events between the previous and the current view,
# then render the new view. Positions come from the previous layout.
# ---------------------------------------------------------------------------

func _seat_anchor(seat_idx: int) -> Vector2:
	if seat_idx == _my_seat and _me_view.visible:
		return _me_view.avatar_center()
	for sv in _plates:
		if sv.visible and sv.seat_index == seat_idx:
			return sv.avatar_center()
	return _stage.global_position + _surface.center


func _card_center(cv: CardView) -> Vector2:
	return cv.global_position + cv.size / 2.0


func _market_card_anchor(card_id: int) -> Vector2:
	for cv in _market_row.get_children():
		if cv is CardView and cv.card_id == card_id:
			return _card_center(cv)
	return _card_center(_supply_pile)


func _hand_anchor(card_id: int) -> Vector2:
	for cv in _hand_cards:
		if cv.card_id == card_id:
			return _card_center(cv)
	return _stage.global_position + _surface.project(0, HAND_V, HAND_Z)


## Where a card flies to when `seat` takes it: my hand, or the fan of an opponent.
func _target_for_seat(seat: int) -> Vector2:
	if seat == _my_seat:
		return _stage.global_position + _surface.project(0, HAND_V, HAND_Z)
	var hp := _hand_pos_for_angle(float(_seat_angles.get(seat, 0.0)))
	return _stage.global_position + _surface.project(hp.x, hp.y, 10.0)


func _market_drop_anchor() -> Vector2:
	var m: int = view.get("market", []).size()
	var p := _market_pos(m, m + 1)
	return _stage.global_position + _surface.project(p.x, p.y, 1.0)


func _play_events_then_render() -> void:
	if _animating:
		return
	_animating = true
	var events := _pending_events.duplicate()
	_pending_events.clear()
	var small := 100.0 * MARKET_SCALE * _surface.k
	var big := 100.0 * HAND_SCALE * _surface.k
	var mini_w := 100.0 * OPP_HAND_SCALE * _surface.k
	for e in events:
		match String(e.get("type", "")):
			"took_supply":
				var seat := int(e.get("seat", 0))
				var cost := int(e.get("cost", 0))
				if cost > 0:
					for cv in _market_row.get_children():
						if cv is CardView:
							_fly_coin(_seat_anchor(seat), _card_center(cv))
					await get_tree().create_timer(COIN_TIME).timeout
				Sfx.play("card_deal")
				await _fly_card(_card_center(_supply_pile), _target_for_seat(seat), 0, false, small, big if seat == _my_seat else mini_w)
			"took_market":
				var seat := int(e.get("seat", 0))
				var card: Dictionary = e.get("card", {})
				Sfx.play("card_deal")
				await _fly_card(_market_card_anchor(int(card.get("id", -1))), _target_for_seat(seat), int(card.get("company", 0)), true, small, big if seat == _my_seat else mini_w)
			"played":
				var seat := int(e.get("seat", 0))
				var card: Dictionary = e.get("card", {})
				var from := _hand_anchor(int(card.get("id", -1))) if seat == _my_seat else _target_for_seat(seat)
				var to_portfolio: bool = e.get("to") == "portfolio"
				var to := (_stage.global_position + _surface.project(0, 100, 1.0)) if (to_portfolio and seat == _my_seat) \
					else (_seat_anchor(seat) if to_portfolio else _market_drop_anchor())
				Sfx.play("card_place")
				await _fly_card(from, to, int(card.get("company", 0)), true, big if seat == _my_seat else mini_w, small)
			"game_ended":
				await _animate_dividends(e.get("result", {}))
	_animating = false
	_render()
	if not _pending_events.is_empty():
		_play_events_then_render()


## A ghost card slides between two screen centres, changing size on the way.
func _fly_card(from: Vector2, to: Vector2, company: int, face_up: bool, from_w: float, to_w: float) -> void:
	var ghost := CardView.new()
	ghost.setup(-1, company, 0, face_up)
	ghost.selectable = false
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(ghost)
	ghost.set_card_size(from_w)
	ghost.global_position = from - ghost.size / 2.0
	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ghost, "global_position", to - Vector2(to_w, to_w * 1.4) / 2.0, FLY_TIME)
	tw.parallel().tween_property(ghost, "size", Vector2(to_w, to_w * 1.4), FLY_TIME)
	await tw.finished
	ghost.queue_free()


func _fly_coin(from: Vector2, to: Vector2, gold: bool = false) -> void:
	var coin := CoinView.new(gold, _px(18))
	_fx_layer.add_child(coin)
	coin.global_position = from - coin.size / 2.0
	Sfx.play("coin_gold" if gold else "coin_slide")
	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(coin, "global_position", to - coin.size / 2.0, COIN_TIME)
	tw.parallel().tween_property(coin, "scale", Vector2(1.5, 1.5), COIN_TIME / 2.0)
	tw.tween_property(coin, "scale", Vector2(1.0, 1.0), COIN_TIME / 2.0)
	tw.tween_callback(coin.queue_free)


## Dividend day: for each company, coins fly from every payer to the
## majority holder, flipping to gold on arrival.
func _animate_dividends(result: Dictionary) -> void:
	var seats: Array = view.get("seats", [])
	for div in result.get("companies", []):
		var majority = div.get("majority")
		if majority == null:
			continue
		var company := int(div.get("company", 0))
		_status.text = "%s pays out to %s" % [Companies.name_of(company), seats[int(majority)].get("name", "?")]
		var to := _seat_anchor(int(majority))
		var any := false
		for p in div.get("payments", []):
			for i in mini(int(p.get("coins", 0)), 8):
				_fly_coin(_seat_anchor(int(p.get("from", 0))), to, true)
				any = true
				await get_tree().create_timer(0.05).timeout
		if any:
			await get_tree().create_timer(0.45).timeout
	_status.text = "Dividend day"
