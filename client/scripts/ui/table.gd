extends Control
## The game table (portrait). Renders a PlayerView from the server, animates
## the events that precede each view, and sends intents.
##
## Layout (720x1280 design size, scales with canvas_items stretch):
##   top bar        status + timer + leave
##   seat oval      opponents on a vertical oval, you at the bottom seat slot
##   market strip   supply pile | market cards (scrollable)
##   action area    contextual prompt (draw / keep / sell)
##   hand fan       your 3-4 cards

const FLY_TIME := 0.35
const COIN_TIME := 0.3
const HAND_SCALE := 1.35

var view: Dictionary = {}
var _my_seat: int = -1
var _step_seconds: float = 30.0

# Widgets
var _status: Label
var _timer_label: Label
var _seats_layer: Control
var _seat_views: Array[SeatView] = []
var _market_row: HBoxContainer
var _supply_pile: CardView
var _supply_count: Label
var _hand_layer: Control
var _hand_cards: Array[CardView] = []
var _draw_button: Button
var _prompt: Label
var _keep_button: Button
var _sell_button: Button
var _cancel_button: Button
var _fx_layer: Control
var _result_panel: PanelContainer
var _result_backdrop: ColorRect
var _result_label: Label

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


func _ready() -> void:
	_build_layout()
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

func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Companies.TABLE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Board edge: a darker green frame like the rim of a property board.
	var frame := ReferenceRect.new()
	frame.editor_only = false
	frame.border_color = Companies.TABLE_EDGE
	frame.border_width = 6.0
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	# Top bar.
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 16
	top.custom_minimum_size = Vector2(0, 48)
	add_child(top)
	_status = Label.new()
	_status.text = "Connecting..."
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 22)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_status)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 22)
	_timer_label.add_theme_color_override("font_color", Companies.ALERT)
	top.add_child(_timer_label)
	_emote_button = Button.new()
	_emote_button.text = "😊"
	_emote_button.tooltip_text = "Emotes"
	_emote_button.pressed.connect(_toggle_emote_bar)
	top.add_child(_emote_button)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_on_leave)
	top.add_child(leave)

	# Seat oval.
	_seats_layer = Control.new()
	_seats_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_seats_layer.offset_top = 72
	_seats_layer.offset_bottom = 72 + 430
	_seats_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_seats_layer)

	# Market strip.
	var market_box := VBoxContainer.new()
	market_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	market_box.offset_left = 16
	market_box.offset_right = -16
	market_box.offset_top = 520
	add_child(market_box)
	var market_title := Label.new()
	market_title.text = "The Market"
	market_title.add_theme_font_size_override("font_size", 16)
	market_title.add_theme_color_override("font_color", Companies.INK_SOFT)
	market_box.add_child(market_title)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	market_box.add_child(strip)

	var supply_box := VBoxContainer.new()
	supply_box.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_child(supply_box)
	_supply_pile = CardView.new()
	_supply_pile.setup(-1, 0, 0, false)
	_supply_pile.selectable = false
	supply_box.add_child(_supply_pile)
	_supply_count = Label.new()
	_supply_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_supply_count.add_theme_font_size_override("font_size", 14)
	supply_box.add_child(_supply_count)

	var sep := ColorRect.new()
	sep.color = Companies.TABLE_EDGE
	sep.custom_minimum_size = Vector2(2, CardView.H)
	strip.add_child(sep)

	var market_scroll := ScrollContainer.new()
	market_scroll.custom_minimum_size = Vector2(0, CardView.H + 12)
	market_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	market_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.add_child(market_scroll)
	_market_row = HBoxContainer.new()
	_market_row.add_theme_constant_override("separation", 8)
	market_scroll.add_child(_market_row)

	# Action area.
	var actions := VBoxContainer.new()
	actions.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	actions.offset_left = 16
	actions.offset_right = -16
	actions.offset_top = 740
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(_prompt)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	actions.add_child(buttons)
	_draw_button = _make_button(buttons, "Draw from supply", _on_draw_pressed)
	_keep_button = _make_button(buttons, "Keep", _on_keep_pressed)
	_sell_button = _make_button(buttons, "Sell to Market", _on_sell_pressed)
	_cancel_button = _make_button(buttons, "Cancel", _on_cancel_pressed)

	# Hand fan.
	_hand_layer = Control.new()
	_hand_layer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hand_layer.offset_top = -CardView.H * HAND_SCALE - 90
	_hand_layer.offset_bottom = -24
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_layer)

	# Effects overlay (flying cards and coins).
	_fx_layer = Control.new()
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	_build_social_layer()

	# Result panel (dividend day): dimmed backdrop + centered deed-style panel.
	_result_backdrop = ColorRect.new()
	_result_backdrop.color = Color(0, 0, 0, 0.45)
	_result_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_backdrop.visible = false
	add_child(_result_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_backdrop.add_child(center)
	var deed := UiTheme.deed_panel(Companies.GOLD, "Dividend day", Companies.INK)
	_result_panel = deed["panel"]
	_result_panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(_result_panel)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 12)
	deed["body"].add_child(result_box)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 18)
	result_box.add_child(_result_label)
	var result_buttons := HBoxContainer.new()
	result_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	result_buttons.add_theme_constant_override("separation", 12)
	result_box.add_child(result_buttons)
	_make_button(result_buttons, "Play again", _on_play_again).visible = true
	_make_button(result_buttons, "Leave", _on_leave).visible = true


func _build_social_layer() -> void:
	# Emote bar: a deed-style strip of preset emotes and phrases under the top bar.
	_emote_bar = PanelContainer.new()
	_emote_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_emote_bar.offset_left = 16
	_emote_bar.offset_right = -16
	_emote_bar.offset_top = 70
	_emote_bar.visible = false
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Companies.PANEL
	bar_style.border_color = Companies.INK
	bar_style.set_border_width_all(2)
	bar_style.set_corner_radius_all(8)
	bar_style.set_content_margin_all(8)
	_emote_bar.add_theme_stylebox_override("panel", bar_style)
	add_child(_emote_bar)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_emote_bar.add_child(grid)
	for e in Protocol.EMOTES:
		var b := Button.new()
		b.text = e["text"]
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		var id: String = e["id"]
		b.pressed.connect(func() -> void:
			Net.send_emote(id)
			_emote_bar.visible = false)
		grid.add_child(b)

	# Seat menu: mute, report, block. Opened by tapping an opponent's seat.
	_seat_menu = PopupMenu.new()
	_seat_menu.add_item("Mute", 0)
	_seat_menu.add_item("Report", 1)
	_seat_menu.add_item("Block", 2)
	_seat_menu.id_pressed.connect(_on_seat_menu)
	add_child(_seat_menu)

	# Reconnect overlay.
	_reconnect_overlay = ColorRect.new()
	_reconnect_overlay.color = Color(0, 0, 0, 0.5)
	_reconnect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reconnect_overlay.visible = false
	add_child(_reconnect_overlay)
	var rc := CenterContainer.new()
	rc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reconnect_overlay.add_child(rc)
	var deed := UiTheme.deed_panel(Companies.CHEST, "Reconnecting", Color.WHITE)
	deed["panel"].custom_minimum_size = Vector2(480, 0)
	_reconnect_label = Label.new()
	_reconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reconnect_label.add_theme_font_size_override("font_size", 18)
	deed["body"].add_child(_reconnect_label)
	rc.add_child(deed["panel"])


func _toggle_emote_bar() -> void:
	_emote_bar.visible = not _emote_bar.visible


func _on_emote_shown(seat: int, emote: String) -> void:
	var seats: Array = view.get("seats", [])
	if seat < 0 or seat >= seats.size():
		return
	if Net.is_muted(String(seats[seat].get("id", ""))):
		return
	var text := Protocol.emote_text(emote)
	if text.is_empty():
		return
	_show_bubble(seat, text)


func _show_bubble(seat: int, text: String) -> void:
	var old = _emote_bubbles.get(seat)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var bubble := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Companies.PANEL
	style.border_color = Companies.INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	bubble.add_theme_stylebox_override("panel", style)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	bubble.add_child(label)
	_fx_layer.add_child(bubble)
	var anchor := _seat_anchor(seat)
	bubble.global_position = anchor + Vector2(30, -54)
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
			_status.text = "%s %s" % [who, "muted" if Net.is_muted(uid) else "unmuted"]
		1:
			var ok: bool = await Net.report_player(uid, "behaviour")
			_status.text = "Report sent. Thank you." if ok else "Report failed, try again"
		2:
			await Net.block_player(uid)
			_status.text = "%s blocked" % who


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


func _make_button(parent: Control, text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 56)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	b.visible = false
	parent.add_child(b)
	return b


## Seat slot positions (fractions of the seats layer) for N opponents.
## Index 0 is the slot directly opposite you; slots fan out around the oval.
func _opponent_slots(n: int) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	match n:
		1: slots = [Vector2(0.5, 0.15)]
		2: slots = [Vector2(0.28, 0.15), Vector2(0.72, 0.15)]
		3: slots = [Vector2(0.18, 0.55), Vector2(0.5, 0.12), Vector2(0.82, 0.55)]
		4: slots = [Vector2(0.18, 0.62), Vector2(0.3, 0.14), Vector2(0.7, 0.14), Vector2(0.82, 0.62)]
		5: slots = [Vector2(0.16, 0.72), Vector2(0.2, 0.36), Vector2(0.5, 0.1), Vector2(0.8, 0.36), Vector2(0.84, 0.72)]
		_: slots = [Vector2(0.16, 0.78), Vector2(0.16, 0.44), Vector2(0.32, 0.12), Vector2(0.68, 0.12), Vector2(0.84, 0.44), Vector2(0.84, 0.78)]
	return slots


## Attach the tutorial coach overlay (idempotent).
func enable_coach() -> void:
	if coach != null:
		return
	coach = Coach.new()
	add_child(coach)


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_draw_pressed() -> void:
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
	_status.text = "Error: %s" % message
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
		return
	var remaining := int(ceil((deadline - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	_timer_label.text = "%ds" % maxi(remaining, 0)


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

	_render_status(phase, seats, active)
	_render_seats(seats, active, phase)
	_render_market(phase)
	_render_hand(seats, phase)
	_update_prompt()
	_render_result(seats)
	if coach != null:
		coach.on_view(view)


func _render_status(phase: String, seats: Array, active: int) -> void:
	if phase == "ended":
		_status.text = "Dividend day!"
	elif _is_my_turn():
		_status.text = "Your turn"
	else:
		var who: Dictionary = seats[active] if active < seats.size() else {}
		_status.text = "%s is %s..." % [who.get("name", "?"), "choosing a share" if phase == "take" else "playing"]


func _render_seats(seats: Array, active: int, phase: String) -> void:
	# Opponents are listed clockwise starting after me so the oval reads in turn order.
	var order: Array[int] = []
	var n := seats.size()
	var start := _my_seat if _my_seat >= 0 else 0
	for k in range(1, n):
		order.append((start + k) % n)
	var slots := _opponent_slots(order.size())
	while _seat_views.size() < n:
		var sv := SeatView.new()
		sv.seat_pressed.connect(_on_seat_pressed)
		_seats_layer.add_child(sv)
		_seat_views.append(sv)
	for sv in _seat_views:
		sv.visible = false
	var layer_size := _seats_layer.size
	if layer_size.x <= 0:
		layer_size = Vector2(720, 430)
	for i in order.size():
		var seat_idx := order[i]
		var sv := _seat_views[i]
		var slot := slots[i]
		sv.position = Vector2(slot.x * layer_size.x - SeatView.W / 2.0, slot.y * layer_size.y)
		sv.visible = true
		sv.update(seat_idx, seats[seat_idx], seat_idx == active and phase != "ended", false, float(view.get("deadline", 0)), _step_seconds)
	# My own seat card sits just above the hand.
	if _my_seat >= 0 and _my_seat < n:
		var me := _seat_views[order.size()]
		me.position = Vector2(layer_size.x / 2.0 - SeatView.W / 2.0, layer_size.y - SeatView.H - 4)
		me.visible = true
		me.update(_my_seat, seats[_my_seat], _my_seat == active and phase != "ended", true, float(view.get("deadline", 0)), _step_seconds)


func _render_market(phase: String) -> void:
	for child in _market_row.get_children():
		_market_row.remove_child(child)
		child.queue_free()
	for slot in view.get("market", []):
		var card: Dictionary = slot.get("card", {})
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), int(card.get("company", 0)), int(slot.get("coins", 0)))
		cv.selectable = _is_my_turn() and phase == "take" and _legal("take_market", cv.card_id)
		cv.card_pressed.connect(_on_market_card_pressed)
		_market_row.add_child(cv)
	var supply := int(view.get("supplyCount", 0))
	_supply_count.text = "%d left" % supply
	_supply_pile.modulate = Color(1, 1, 1, 1 if supply > 0 else 0.3)


func _render_hand(seats: Array, phase: String) -> void:
	for cv in _hand_cards:
		_hand_layer.remove_child(cv)
		cv.queue_free()
	_hand_cards.clear()
	if _my_seat < 0 or _my_seat >= seats.size():
		return
	var me: Dictionary = seats[_my_seat]
	var hand: Array = me.get("hand", [])
	var count := hand.size()
	if count == 0:
		return
	var layer_w := _hand_layer.size.x if _hand_layer.size.x > 0 else 720.0
	var card_w := CardView.W * HAND_SCALE
	var spacing := minf(card_w + 12, (layer_w - 48) / count)
	var total := spacing * (count - 1) + card_w
	var x0 := (layer_w - total) / 2.0
	for i in count:
		var card: Dictionary = hand[i]
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), int(card.get("company", 0)))
		cv.scale = Vector2(HAND_SCALE, HAND_SCALE)
		cv.pivot_offset = Vector2(CardView.W / 2.0, CardView.H)
		var t := 0.0 if count == 1 else (float(i) / (count - 1) - 0.5)
		cv.rotation = deg_to_rad(t * 12.0)
		cv.set_rest_position(Vector2(x0 + i * spacing, 50 + abs(t) * 20))
		var can_play := _is_my_turn() and phase == "play"
		cv.selectable = can_play
		cv.card_pressed.connect(_on_hand_card_pressed)
		_hand_layer.add_child(cv)
		_hand_cards.append(cv)


func _update_prompt() -> void:
	var phase := String(view.get("phase", ""))
	var mine := _is_my_turn()
	_draw_button.visible = false
	_keep_button.visible = false
	_sell_button.visible = false
	_cancel_button.visible = false
	_set_buttons_enabled(true)
	if phase == "ended":
		_prompt.text = ""
		return
	if not mine:
		_prompt.text = "Waiting for your turn"
		return
	if phase == "take":
		var cost = view.get("drawCost")
		var cost_text := ""
		if cost != null:
			cost_text = "free" if int(cost) == 0 else "%d coin%s onto the Market" % [int(cost), "" if int(cost) == 1 else "s"]
		_prompt.text = "Take a share from the Market, or draw from the supply (%s)" % cost_text
		_draw_button.visible = true
		_draw_button.disabled = not _legal("take_supply")
		return
	# Play step.
	if _selected_card < 0:
		_prompt.text = "Tap a card in your hand"
		return
	var company := -1
	for cv in _hand_cards:
		if cv.card_id == _selected_card:
			company = cv.company
	_prompt.text = "%s: keep it in your portfolio or sell it to the Market?" % Companies.name_of(company)
	_keep_button.visible = true
	_sell_button.visible = true
	_cancel_button.visible = true
	_keep_button.disabled = not _legal("play_portfolio", _selected_card)
	_sell_button.disabled = not _legal("play_market", _selected_card)


func _render_result(seats: Array) -> void:
	var result = view.get("result")
	_result_backdrop.visible = result != null
	if result == null:
		return
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
	lines.append("")
	for sc in result.get("scores", []):
		var seat: Dictionary = seats[int(sc.get("seat", 0))]
		var rank := int(sc.get("rank", 1))
		var medal: String = ["🥇", "🥈", "🥉"][rank - 1] if rank <= 3 else "  "
		lines.append("%s %s  %d  (%d bronze + %d gold)" % [medal, seat.get("name", "?"), int(sc.get("score", 0)), int(sc.get("bronze", 0)), int(sc.get("gold", 0))])
	_result_label.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# Animations: play the events between the previous and the current view,
# then render the new view. Positions come from the previous layout.
# ---------------------------------------------------------------------------

func _seat_anchor(seat_idx: int) -> Vector2:
	for sv in _seat_views:
		if sv.visible and sv.seat_index == seat_idx:
			return sv.avatar_center()
	return _seats_layer.global_position + _seats_layer.size / 2.0


func _market_card_anchor(card_id: int) -> Vector2:
	for cv in _market_row.get_children():
		if cv is CardView and cv.card_id == card_id:
			return cv.global_position
	return _supply_pile.global_position


func _hand_anchor(card_id: int) -> Vector2:
	for cv in _hand_cards:
		if cv.card_id == card_id:
			return cv.global_position
	return _hand_layer.global_position + Vector2(_hand_layer.size.x / 2.0 - CardView.W / 2.0, 40)


func _play_events_then_render() -> void:
	if _animating:
		return
	_animating = true
	var events := _pending_events.duplicate()
	_pending_events.clear()
	for e in events:
		match String(e.get("type", "")):
			"took_supply":
				var seat := int(e.get("seat", 0))
				var cost := int(e.get("cost", 0))
				if cost > 0:
					for cv in _market_row.get_children():
						if cv is CardView:
							_fly_coin(_seat_anchor(seat), cv.global_position + Vector2(CardView.W / 2.0, CardView.H / 2.0))
					await get_tree().create_timer(COIN_TIME).timeout
				await _fly_card(_supply_pile.global_position, _target_for_seat(seat), 0, false)
			"took_market":
				var seat := int(e.get("seat", 0))
				var card: Dictionary = e.get("card", {})
				await _fly_card(_market_card_anchor(int(card.get("id", -1))), _target_for_seat(seat), int(card.get("company", 0)), true)
			"played":
				var seat := int(e.get("seat", 0))
				var card: Dictionary = e.get("card", {})
				var from := _hand_anchor(int(card.get("id", -1))) if seat == _my_seat else _seat_anchor(seat) - Vector2(CardView.W / 2.0, CardView.H / 2.0)
				var to := _seat_anchor(seat) - Vector2(CardView.W / 2.0, CardView.H / 2.0) if e.get("to") == "portfolio" else _market_row.global_position + Vector2(_market_row.size.x, 0)
				await _fly_card(from, to, int(card.get("company", 0)), true)
			"game_ended":
				await _animate_dividends(e.get("result", {}))
	_animating = false
	_render()
	if not _pending_events.is_empty():
		_play_events_then_render()


func _target_for_seat(seat: int) -> Vector2:
	if seat == _my_seat:
		return _hand_layer.global_position + Vector2(_hand_layer.size.x / 2.0 - CardView.W / 2.0, 40)
	return _seat_anchor(seat) - Vector2(CardView.W / 2.0, CardView.H / 2.0)


func _fly_card(from: Vector2, to: Vector2, company: int, face_up: bool) -> void:
	var ghost := CardView.new()
	ghost.setup(-1, company, 0, face_up)
	ghost.selectable = false
	ghost.modulate = Color(1, 1, 1, 1)
	_fx_layer.add_child(ghost)
	ghost.global_position = from
	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ghost, "global_position", to, FLY_TIME)
	tw.parallel().tween_property(ghost, "scale", Vector2(0.9, 0.9), FLY_TIME)
	await tw.finished
	ghost.queue_free()


func _fly_coin(from: Vector2, to: Vector2, gold: bool = false) -> void:
	var coin := ColorRect.new()
	coin.color = Companies.GOLD if gold else Companies.BRONZE
	coin.size = Vector2(16, 16)
	coin.pivot_offset = Vector2(8, 8)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(coin)
	coin.global_position = from - Vector2(8, 8)
	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(coin, "global_position", to - Vector2(8, 8), COIN_TIME)
	tw.parallel().tween_property(coin, "rotation", TAU, COIN_TIME)
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
	_status.text = "Dividend day!"
