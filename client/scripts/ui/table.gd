extends Control
## The game table (portrait). Renders a PlayerView from the server, animates
## the events that precede each view, and sends intents.
##
## Layout, after the "3D table" design (sizes in design points, see
## UiTheme.layout_scale):
##   top bar      brand, whose turn it is, timer, Leave / Forfeit
##   plates       opponents around the far side of the felt
##   felt         tilted table (TableBoard): Supply, the Market, your Portfolio
##   hand         your 3-4 cards standing at the near edge of the felt
##   bottom bar   you (capital, holdings), emotes, rules, prompt and buttons
##
## Overlays: the get-ready countdown before the first turn, a forfeit
## confirmation, dividend day, reconnecting, and the close-up of a held card.

const FLY_TIME := 0.35
const COIN_TIME := 0.3
## Tilt of the hand cards per step from the middle, in degrees.
const HAND_TILT_DEG := 7.0
## Seconds left on your own step when the table starts to glow and tick.
const URGENT_SECONDS := 5
## Size of a held card's close-up, relative to an unscaled card.
const PEEK_SCALE := 2.2
## Card scales on the felt, as in the design (1 = a 100 dp wide card).
const MARKET_CARD := 0.5
const SUPPLY_CARD := 0.48
const PORTFOLIO_CARD := 0.36
const HAND_CARD := 0.9
## Opponent plates for 1..6 opponents, clockwise from your left:
## [anchor ("L" left edge, "R" right edge, "C" centre), x dp, y dp, width dp].
const PLATE_SLOTS := [
	[["C", 0, 92, 170]],
	[["L", 8, 110, 170], ["R", 8, 110, 170]],
	[["L", 8, 166, 118], ["C", 0, 92, 170], ["R", 8, 166, 118]],
	[["L", 8, 176, 118], ["C", -65, 92, 118], ["C", 65, 92, 118], ["R", 8, 176, 118]],
	[["L", 8, 252, 118], ["L", 8, 166, 118], ["C", 0, 92, 118], ["R", 8, 166, 118], ["R", 8, 252, 118]],
	[["L", 8, 252, 118], ["L", 8, 166, 118], ["C", -65, 92, 118], ["C", 65, 92, 118], ["R", 8, 166, 118], ["R", 8, 252, 118]],
]
const PLATE_H := 66.0

var view: Dictionary = {}
var _my_seat: int = -1
var _step_seconds: float = 30.0
## Design points to px for this screen.
var _s: float = 1.85
var _hand_scale: float = 1.5

# Widgets
var _room: TextureRect
var _board: TableBoard
var _status: Label
var _timer_label: Label
var _seats_layer: Control
var _seat_views: Array[SeatView] = []
var _me_view: SeatView
var _market_row: Control
var _portfolio_layer: Control
var _supply_pile: CardView
var _hand_layer: Control
var _hand_cards: Array[CardView] = []
var _bar: PanelContainer
var _draw_button: Button
var _prompt: Label
var _keep_button: Button
var _sell_button: Button
var _cancel_button: Button
var _fx_layer: Control
var _result_panel: PanelContainer
var _result_backdrop: ColorRect
var _result_rows: VBoxContainer
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
var sfx: Sfx
## Tutorial: the coached move for this view ({} = anything legal).
var _restriction: Dictionary = {}
var _glow: Panel
var _last_tick := -1
var _announced_turn := -1
var _leave_button: Button
var _forfeit_overlay: ColorRect
var _ready_overlay: ColorRect
var _ready_seats: Label
var _ready_first: Label
var _ready_count: Label
## Ticks (ms) when the get-ready countdown ends; 0 when play has begun.
var _ready_ends_msec: int = 0
var _ready_tween: Tween
var _peek_layer: Control
var _peek: CardView = null
## What the other players did last, shown in the prompt while you wait.
var _action_note := ""


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
	Net.player_forfeited.connect(_on_player_forfeited)
	Net.custom_deck_changed.connect(_on_room_look)
	get_viewport().size_changed.connect(_on_resized)
	# The lobby opened this scene on the game's first view; render it now.
	if not Net.last_view.is_empty():
		_on_view(Net.last_view)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

## A Plus host's felt arrives with the room's look (OP_DECK): repaint.
func _on_room_look() -> void:
	if _board == null:
		return
	_board.felt_color = Cosmetics.table_bg_color()
	_board.edge_color = Cosmetics.table_edge_color()
	UiTheme.paint_room(_room, Cosmetics.table_bg_color(), Vector2(0.5, 0.42))


func _px(dp: float) -> int:
	return int(round(dp * _s))


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_s = UiTheme.layout_scale(get_viewport_rect().size)
	_hand_scale = HAND_CARD * _s * 100.0 / CardView.W
	_room = UiTheme.room_background(Cosmetics.table_bg_color(), Vector2(0.5, 0.42))
	add_child(_room)

	# The felt and everything lying on it.
	_board = TableBoard.new()
	_board.s = _s
	_board.felt_color = Cosmetics.table_bg_color()
	_board.edge_color = Cosmetics.table_edge_color()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_board)
	_portfolio_layer = Control.new()
	_portfolio_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_portfolio_layer)
	_supply_pile = CardView.new()
	_supply_pile.setup(-1, 0, 0, false)
	_supply_pile.selectable = false
	_supply_pile.pivot_offset = Vector2(CardView.W, CardView.H) / 2.0
	_supply_pile.card_pressed.connect(func(_id: int) -> void: _on_draw_pressed())
	_board.add_child(_supply_pile)
	_market_row = Control.new()
	_market_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_market_row)

	# Opponent plates.
	_seats_layer = Control.new()
	_seats_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seats_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_seats_layer)

	_build_top_bar()
	_build_bottom_bar()

	# Hand fan, standing at the near edge of the felt above the bar.
	_hand_layer = Control.new()
	_hand_layer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_layer)

	# Urgency glow: a pulsing red rim while your own step runs out.
	_glow = Panel.new()
	var glow_style := StyleBoxFlat.new()
	glow_style.draw_center = false
	glow_style.border_color = Companies.ALERT
	glow_style.set_border_width_all(12)
	_glow.add_theme_stylebox_override("panel", glow_style)
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.visible = false
	add_child(_glow)
	sfx = Sfx.new()
	add_child(sfx)

	# Effects overlay (flying cards and coins).
	_fx_layer = Control.new()
	_fx_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)
	_build_social_layer()
	_build_result_panel()
	_build_get_ready()
	_build_forfeit_confirm()

	# Close-up of a held card, above everything else.
	_peek_layer = Control.new()
	_peek_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_peek_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_peek_layer)
	_layout()


## Brand, whose turn it is, the step timer and Leave (Forfeit in a live game).
func _build_top_bar() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = _px(12)
	top.offset_right = -_px(12)
	top.offset_top = _px(8)
	top.custom_minimum_size = Vector2(0, _px(48))
	top.add_theme_constant_override("separation", _px(10))
	add_child(top)
	var brand := UiTheme.label("BIG BUSINESS", _px(12), Color.WHITE, true)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var brand_box := UiTheme.card_box(Companies.ALERT, 6 * _s, 2 * _s)
	brand_box.content_margin_left = 8 * _s
	brand_box.content_margin_right = 8 * _s
	brand_box.content_margin_top = 5 * _s
	brand_box.content_margin_bottom = 5 * _s
	brand.add_theme_stylebox_override("normal", brand_box)
	top.add_child(brand)
	_status = UiTheme.label("Connecting...", _px(16), UiTheme.CREAM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	top.add_child(_status)
	_timer_label = UiTheme.label("", _px(16), Color("#FFB4A8"), true)
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_timer_label)
	_leave_button = UiTheme.button("Leave", _px(14), _px(44), "ghost")
	_leave_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_leave_button.pressed.connect(_on_leave_pressed)
	top.add_child(_leave_button)


## The cream bar at the bottom: you, then the prompt, then the move buttons.
func _build_bottom_bar() -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.CREAM
	style.border_color = Companies.INK
	style.border_width_top = 2
	style.corner_radius_top_left = _px(20)
	style.corner_radius_top_right = _px(20)
	style.content_margin_left = _px(14)
	style.content_margin_right = _px(14)
	style.content_margin_top = _px(8)
	style.content_margin_bottom = _px(14)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = _px(14)
	_bar.add_theme_stylebox_override("panel", style)
	add_child(_bar)
	_bar.resized.connect(_layout)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(6))
	_bar.add_child(column)

	var me_row := HBoxContainer.new()
	me_row.add_theme_constant_override("separation", _px(6))
	column.add_child(me_row)
	_me_view = SeatView.new()
	_me_view.s = _s
	_me_view.strip = true
	_me_view.avatar_color = SeatView.AVATARS[0]
	_me_view.custom_minimum_size = Vector2(0, _px(36))
	_me_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_me_view.visible = false
	me_row.add_child(_me_view)
	_seat_views.append(_me_view)
	_emote_button = UiTheme.button("😊", _px(16), _px(36), "ghost")
	_emote_button.tooltip_text = "Emotes"
	_emote_button.custom_minimum_size.x = maxf(48, _px(40))
	_emote_button.pressed.connect(_toggle_emote_bar)
	me_row.add_child(_emote_button)
	var help := UiTheme.button("?", _px(16), _px(36), "ghost")
	help.tooltip_text = "Rules"
	help.custom_minimum_size.x = maxf(48, _px(40))
	help.add_theme_font_override("font", UiTheme.display_font())
	help.pressed.connect(func() -> void: HelpScreen.open_over(self))
	me_row.add_child(help)

	_prompt = UiTheme.label("", _px(14))
	_prompt.add_theme_font_override("font", UiTheme.body_font())
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(0, _px(38))
	column.add_child(_prompt)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", _px(8))
	buttons.custom_minimum_size = Vector2(0, _px(44))
	column.add_child(buttons)
	_draw_button = _make_button(buttons, "Draw from supply", _on_draw_pressed, "primary")
	_keep_button = _make_button(buttons, "Keep", _on_keep_pressed, "primary")
	_sell_button = _make_button(buttons, "Sell to Market", _on_sell_pressed)
	_cancel_button = _make_button(buttons, "Cancel", _on_cancel_pressed, "ghost")
	_cancel_button.size_flags_horizontal = Control.SIZE_FILL


## Dividend day: a gold-banded panel with the standings and each payout.
func _build_result_panel() -> void:
	_result_backdrop = ColorRect.new()
	_result_backdrop.color = Color(0.04, 0.09, 0.06, 0.6)
	_result_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_backdrop.visible = false
	add_child(_result_backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_backdrop.add_child(center)
	var deed := UiTheme.deed_panel(Companies.GOLD, "Dividend day", Companies.INK)
	deed["title"].add_theme_font_size_override("font_size", _px(20))
	deed["title"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_result_panel = deed["panel"]
	_result_panel.custom_minimum_size = Vector2(minf(get_viewport_rect().size.x, 720.0) - _px(40), 0)
	center.add_child(_result_panel)
	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", _px(10))
	deed["body"].add_child(result_box)
	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", 0)
	result_box.add_child(_result_rows)
	_result_label = UiTheme.label("", _px(11), UiTheme.MUTED)
	_result_label.add_theme_font_override("font", UiTheme.body_font())
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_box.add_child(_result_label)
	var result_buttons := HBoxContainer.new()
	result_buttons.add_theme_constant_override("separation", _px(8))
	result_box.add_child(result_buttons)
	_make_button(result_buttons, "Play again", _on_play_again, "primary").visible = true
	var leave := _make_button(result_buttons, "Leave", _on_leave, "ghost")
	leave.visible = true
	leave.size_flags_horizontal = Control.SIZE_FILL


func _on_resized() -> void:
	_layout()
	if not view.is_empty():
		_render()


## Places the felt, the plates and the hand for the current screen size.
## The felt's centre sits midway between the top bar and the bottom bar,
## as on the design artboard.
func _layout() -> void:
	if _board == null or _bar == null:
		return
	var screen := get_viewport_rect().size
	if screen.x < 200:
		screen = Vector2(720, 1280)
	var top := 60.0 * _s
	var bar_top := screen.y - maxf(_bar.size.y, _bar.get_combined_minimum_size().y)
	_board.origin = Vector2(screen.x / 2.0, (top + bar_top) / 2.0 + 18.0 * _s)
	_board.queue_redraw()
	var hand_h := CardView.H * _hand_scale + 40.0 * _s
	_hand_layer.offset_bottom = bar_top - screen.y
	_hand_layer.offset_top = _hand_layer.offset_bottom - hand_h
	_emote_bar.offset_bottom = bar_top - screen.y - _px(6)
	_place_supply()


## The countdown before the first turn: seat order, who starts, 3-2-1.
## It sits below the top bar so rules, emotes and Forfeit stay in reach.
func _build_get_ready() -> void:
	_ready_overlay = ColorRect.new()
	_ready_overlay.color = Color(0, 0, 0, 0.45)
	_ready_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ready_overlay.offset_top = _px(60)
	_ready_overlay.visible = false
	add_child(_ready_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_overlay.add_child(center)
	var deed := UiTheme.deed_panel(Companies.CHEST, "Get ready", Color.WHITE)
	deed["panel"].custom_minimum_size = Vector2(520, 0)
	center.add_child(deed["panel"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	deed["body"].add_child(box)
	var order_title := Label.new()
	order_title.text = "Turn order"
	order_title.add_theme_font_size_override("font_size", 19)
	order_title.add_theme_color_override("font_color", Companies.INK_SOFT)
	box.add_child(order_title)
	_ready_seats = Label.new()
	_ready_seats.add_theme_font_size_override("font_size", 24)
	box.add_child(_ready_seats)
	_ready_first = Label.new()
	_ready_first.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_first.add_theme_font_size_override("font_size", 26)
	box.add_child(_ready_first)
	_ready_count = Label.new()
	_ready_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_count.add_theme_font_size_override("font_size", 72)
	box.add_child(_ready_count)
	var tip := Label.new()
	tip.text = "Collect shares, hold the most of a company, and cash in on dividend day."
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Companies.INK_SOFT)
	box.add_child(tip)


func _build_forfeit_confirm() -> void:
	_forfeit_overlay = ColorRect.new()
	_forfeit_overlay.color = Color(0, 0, 0, 0.45)
	_forfeit_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forfeit_overlay.visible = false
	add_child(_forfeit_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_forfeit_overlay.add_child(center)
	var deed := UiTheme.deed_panel(Companies.ALERT, "Forfeit this game?", Color.WHITE)
	deed["panel"].custom_minimum_size = Vector2(520, 0)
	center.add_child(deed["panel"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	deed["body"].add_child(box)
	var body := Label.new()
	body.text = "A bot plays your seat for the rest of the game and you can't come back to it. It counts as a game played, with no XP."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 22)
	box.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_make_button(buttons, "Forfeit", _on_forfeit_confirmed).visible = true
	_make_button(buttons, "Keep playing", func() -> void: _forfeit_overlay.visible = false, "primary").visible = true


func _build_social_layer() -> void:
	# Emote bar: a deed-style strip of preset emotes and phrases above the bottom bar.
	_emote_bar = PanelContainer.new()
	_emote_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_emote_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_emote_bar.offset_left = 16
	_emote_bar.offset_right = -16
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
		b.custom_minimum_size = Vector2(0, maxf(52, _px(40)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Emoji read at a glance only when larger than the phrase text.
		b.add_theme_font_size_override("font_size", 26 if Protocol.is_emoji(e["id"]) else 16)
		var id: String = e["id"]
		b.pressed.connect(func() -> void:
			Net.send_emote(id)
			_emote_bar.visible = false)
		grid.add_child(b)

	# Seat menu: mute, report, block. Opened by tapping an opponent's seat.
	_seat_menu = PopupMenu.new()
	# Touch-sized rows: the default popup rows are ~25 px tall.
	_seat_menu.add_theme_font_size_override("font_size", 24)
	_seat_menu.add_theme_constant_override("v_separation", 24)
	_seat_menu.add_theme_constant_override("item_start_padding", 24)
	_seat_menu.add_theme_constant_override("item_end_padding", 32)
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
	_reconnect_label.add_theme_font_size_override("font_size", 22)
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
	_show_bubble(seat, text, 32 if Protocol.is_emoji(emote) else 20)


func _show_bubble(seat: int, text: String, font_size: int = 24) -> void:
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
	label.add_theme_font_size_override("font_size", font_size)
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
	var blocked: bool = Net.is_blocked(uid)
	_seat_menu.set_item_text(0, "Unmute" if Net.muted.has(uid) else "Mute")
	_seat_menu.set_item_disabled(0, blocked)
	_seat_menu.set_item_text(2, "Blocked" if blocked else "Block")
	_seat_menu.set_item_disabled(2, blocked)
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
			Net.mute_player(uid, not Net.muted.has(uid))
			_status.text = "%s %s" % [who, "muted" if Net.muted.has(uid) else "unmuted"]
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


## A move or dialog button, hidden until a step shows it.
func _make_button(parent: Control, text: String, handler: Callable, kind := "") -> Button:
	var b := UiTheme.button(text, _px(14), _px(44), kind)
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
	coach.spot_provider = coach_spot
	add_child(coach)
	# Skipping lifts the first-turn restrictions straight away.
	coach.finished.connect(func() -> void:
		if not view.is_empty():
			_render())


## Screen area the coach points at for a step: "supply", "market", "hand",
## "bar" or "plates" (an empty rect for none).
func coach_spot(key: String) -> Rect2:
	match key:
		"supply":
			return _board.zone_rect(TableBoard.ZONE_SUPPLY).grow(10 * _s)
		"market":
			return _board.zone_rect(TableBoard.ZONE_MARKET).grow(8 * _s)
		"hand":
			var r := Rect2(_hand_layer.global_position, _hand_layer.size)
			return r.merge(_bar.get_global_rect()).grow(-2 * _s)
		"bar":
			return _bar.get_global_rect().grow(-4 * _s)
		"plates":
			var r := Rect2()
			for sv in _seat_views:
				if sv.visible and sv != _me_view:
					r = sv.get_global_rect() if r.size == Vector2.ZERO else r.merge(sv.get_global_rect())
			return r.grow(8 * _s)
	return Rect2()


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_draw_pressed() -> void:
	if not _allowed("take_supply"):
		return
	Net.send_action(Protocol.take_supply())
	_set_buttons_enabled(false)


func _on_market_card_pressed(card_id: int) -> void:
	if not _is_my_turn() or view.get("phase") != "take" or not _allowed("take_market", card_id):
		return
	Net.send_action(Protocol.take_market(card_id))
	_set_buttons_enabled(false)


func _on_hand_card_pressed(card_id: int) -> void:
	if not _is_my_turn() or view.get("phase") != "play" or not _card_playable(card_id):
		return
	_selected_card = -1 if _selected_card == card_id else card_id
	for cv in _hand_cards:
		cv.selected = cv.card_id == _selected_card
	_update_prompt()


func _on_keep_pressed() -> void:
	if _selected_card >= 0 and _allowed("play_portfolio", _selected_card):
		Net.send_action(Protocol.play_portfolio(_selected_card))
		_set_buttons_enabled(false)


func _on_sell_pressed() -> void:
	if _selected_card >= 0 and _allowed("play_market", _selected_card):
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


## True while you hold a seat in a real game that is not over yet.
func _can_forfeit() -> bool:
	return not Net.tutorial_mode and _my_seat >= 0 and not view.is_empty() and view.get("phase") != "ended"


func _on_leave_pressed() -> void:
	if _can_forfeit():
		_forfeit_overlay.visible = true
	else:
		_on_leave()


func _on_forfeit_confirmed() -> void:
	_forfeit_overlay.visible = false
	await Net.forfeit()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_player_forfeited(seat: int) -> void:
	var seats: Array = view.get("seats", [])
	if seat < 0 or seat >= seats.size() or seat == _my_seat:
		return
	_show_bubble(seat, "Forfeited")
	_status.text = "%s forfeited. A bot plays their seat." % seats[seat].get("name", "A player")


func _on_play_again() -> void:
	await Net.leave_match()
	# WHY: the next game reuses this scene; a tutorial coach left attached
	# would keep restricting moves and showing cards in a timed real game.
	if coach != null:
		coach.queue_free()
		coach = null
		_restriction = {}
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
	_update_get_ready(int(v.get("startsInMs", 0)))
	if not _last_view.is_empty() and not _pending_events.is_empty():
		_play_events_then_render()
	else:
		_pending_events.clear()
		_render()


func _process(_delta: float) -> void:
	if _ready_ends_msec > 0:
		_update_countdown()
	if view.is_empty():
		return
	var deadline := float(view.get("deadline", 0))
	if deadline <= 0 or view.get("phase") == "ended" or _ready_ends_msec > 0:
		_timer_label.text = ""
		_glow.visible = false
		return
	var remaining := int(ceil((deadline - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	_timer_label.text = "%ds" % maxi(remaining, 0)
	_update_urgency(remaining)


## Shows the countdown while the server holds the first turn back
## (startsInMs > 0), and ends it once play begins.
func _update_get_ready(starts_in_ms: int) -> void:
	if starts_in_ms > 0 and view.get("phase") != "ended":
		_ready_ends_msec = Time.get_ticks_msec() + starts_in_ms
		_fill_get_ready()
		if _ready_tween != null:
			_ready_tween.kill()
		_ready_overlay.modulate.a = 1.0
		_ready_overlay.visible = true
		_update_countdown()
	elif _ready_ends_msec > 0:
		_end_get_ready()


func _fill_get_ready() -> void:
	var seats: Array = view.get("seats", [])
	if seats.is_empty():
		return
	var first := int(view.get("active", 0))
	var lines := PackedStringArray()
	for k in seats.size():
		var i := (first + k) % seats.size()
		var seat: Dictionary = seats[i]
		var who := "You" if i == _my_seat else String(seat.get("name", "?"))
		lines.append("%d.  %s%s" % [k + 1, who, "  • bot" if seat.get("isBot", false) else ""])
	_ready_seats.text = "\n".join(lines)
	_ready_first.text = "You go first!" if first == _my_seat else "%s goes first" % seats[first].get("name", "?")


func _update_countdown() -> void:
	var left := _ready_ends_msec - Time.get_ticks_msec()
	if left > 0:
		_ready_count.text = str(ceili(left / 1000.0))
	else:
		_end_get_ready()


func _end_get_ready() -> void:
	_ready_ends_msec = 0
	_ready_count.text = "Go!"
	if _ready_tween != null:
		_ready_tween.kill()
	_ready_tween = create_tween()
	_ready_tween.tween_interval(0.35)
	_ready_tween.tween_property(_ready_overlay, "modulate:a", 0.0, 0.25)
	_ready_tween.tween_callback(func() -> void:
		_ready_overlay.visible = false
		_ready_overlay.modulate.a = 1.0)
	# The turn chime waited for the countdown.
	_announce_turn(String(view.get("phase", "")))


## Under URGENT_SECONDS on your own step: pulse the rim and tick each second.
func _update_urgency(remaining: int) -> void:
	var urgent := _is_my_turn() and remaining > 0 and remaining <= URGENT_SECONDS
	_glow.visible = urgent
	if not urgent:
		_last_tick = -1
		return
	_glow.modulate.a = 0.45 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)
	if remaining != _last_tick:
		_last_tick = remaining
		sfx.play("tick", -4.0)
		if remaining <= 2:
			Sfx.buzz(20)


func _is_my_turn() -> bool:
	return _my_seat >= 0 and int(view.get("active", -1)) == _my_seat and view.get("phase") != "ended"


func _legal(type: String, card_id: int = -1) -> bool:
	for a in view.get("legal", []):
		if a.get("type") != type:
			continue
		if card_id < 0 or int(a.get("cardId", -1)) == card_id:
			return true
	return false


## Legal, and the coached move while the tutorial restricts the first turns.
func _allowed(type: String, card_id: int = -1) -> bool:
	if not _legal(type, card_id):
		return false
	var take := String(_restriction.get("take", ""))
	var play := String(_restriction.get("play", ""))
	match type:
		"take_supply":
			return take != "market_coins"
		"take_market":
			if take == "supply":
				return false
			if take == "market_coins":
				for slot in view.get("market", []):
					if int(slot["card"]["id"]) == card_id:
						return int(slot.get("coins", 0)) > 0
				return false
		"play_portfolio":
			return play != "market"
		"play_market":
			return play != "portfolio"
	return true


## A hand card may be selected if the move the tutorial wants is possible with it.
func _card_playable(card_id: int) -> bool:
	if String(_restriction.get("play", "")) == "market":
		return _allowed("play_market", card_id)
	return _legal("play_portfolio", card_id)


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
	_restriction = coach.restriction(view) if coach != null else {}
	_hide_peek()
	_leave_button.text = "Forfeit" if _can_forfeit() else "Leave"
	if not _can_forfeit():
		_forfeit_overlay.visible = false

	_layout()
	_render_status(phase, seats, active)
	_render_seats(seats, active, phase)
	_render_market(phase)
	_render_portfolio(seats)
	_render_hand(seats, phase)
	_update_prompt()
	_render_result(seats)
	_announce_turn(phase)
	if coach != null:
		coach.on_view(view)


## A chime and a buzz once when your turn starts.
func _announce_turn(phase: String) -> void:
	if _ready_ends_msec > 0:
		return
	var turn := int(view.get("turn", 0))
	if phase == "take" and _is_my_turn() and turn != _announced_turn:
		_announced_turn = turn
		sfx.play("turn")
		Sfx.buzz(40)


func _render_status(phase: String, seats: Array, active: int) -> void:
	if phase == "ended":
		_status.text = "Dividend day!"
	elif _ready_ends_msec > 0:
		_status.text = "Get ready"
	elif _is_my_turn():
		_status.text = "Your turn"
	else:
		var who: Dictionary = seats[active] if active < seats.size() else {}
		_status.text = "%s is %s..." % [who.get("name", "?"), "choosing a share" if phase == "take" else "playing"]


## Opponents in turn order from your left, on plates around the far side of
## the felt, with their face-down hands on the felt in front of them; you in
## the bottom bar.
func _render_seats(seats: Array, active: int, phase: String) -> void:
	var order: Array[int] = []
	var n := seats.size()
	var start := _my_seat if _my_seat >= 0 else 0
	for k in range(1, n):
		order.append((start + k) % n)
	var plates: Array[SeatView] = []
	for sv in _seat_views:
		if sv != _me_view:
			plates.append(sv)
	while plates.size() < order.size():
		var sv := SeatView.new()
		sv.s = _s
		sv.seat_pressed.connect(_on_seat_pressed)
		_seats_layer.add_child(sv)
		_seat_views.append(sv)
		plates.append(sv)
	for sv in plates:
		sv.visible = false
	var screen := get_viewport_rect().size
	if screen.x < 200:
		screen = Vector2(720, 1280)
	var slots: Array = PLATE_SLOTS[clampi(order.size(), 1, PLATE_SLOTS.size()) - 1]
	var spots := TableBoard.hand_spots(order.size())
	var hands := []
	for i in mini(order.size(), slots.size()):
		var seat_idx := order[i]
		var slot: Array = slots[i]
		var sv := plates[i]
		var w: float = float(slot[3]) * _s
		var x: float = float(slot[1]) * _s
		match String(slot[0]):
			"R":
				x = screen.x - x - w
			"C":
				x = screen.x / 2.0 + x - w / 2.0
		sv.custom_minimum_size = Vector2(w, PLATE_H * _s)
		sv.size = sv.custom_minimum_size
		sv.position = Vector2(x, _board.origin.y + (float(slot[2]) - 400.0) * _s)
		sv.wide = int(slot[3]) >= 170
		sv.avatar_color = SeatView.AVATARS[(i + 1) % SeatView.AVATARS.size()]
		sv.visible = true
		sv.update(seat_idx, seats[seat_idx], seat_idx == active and phase != "ended", false, float(view.get("deadline", 0)), _step_seconds)
		if phase != "ended":
			hands.append({"at": spots[i]["at"], "angle": spots[i]["angle"], "count": int(seats[seat_idx].get("handCount", 0))})
	_board.hands = hands
	_me_view.visible = _my_seat >= 0 and _my_seat < n
	if _me_view.visible:
		_me_view.update(_my_seat, seats[_my_seat], _my_seat == active and phase != "ended", true, float(view.get("deadline", 0)), _step_seconds)


## Market slot k of m on the felt: rows of at least five, two rows at most,
## squeezed together as the Market grows (dp from the felt's centre).
static func _market_pos(k: int, m: int) -> Vector2:
	var per := maxi(5, ceili(m / 2.0))
	var row := k / per
	var in_row := mini(per, m) if row == 0 else m - per
	var col := k % per
	var spacing := minf(54.0, 264.0 / per)
	return Vector2((col - (in_row - 1) / 2.0) * spacing, -52.0 + row * 72.0)


## Lays a card on the felt at `p` (dp from the centre), `card` = its design
## scale before perspective.
func _place_on_felt(cv: CardView, p: Vector2, card: float, tilt_deg: float = 0.0) -> void:
	var k := card * _board.depth(p) * _s * 100.0 / CardView.W
	cv.pivot_offset = Vector2(CardView.W, CardView.H) / 2.0
	cv.scale = Vector2(k, k)
	cv.rotation = deg_to_rad(tilt_deg)
	cv.position = _board.project(p) - cv.pivot_offset


func _place_supply() -> void:
	if _supply_pile != null and _board != null:
		_place_on_felt(_supply_pile, TableBoard.SUPPLY_AT, SUPPLY_CARD, -1.0)


func _render_market(phase: String) -> void:
	for child in _market_row.get_children():
		_market_row.remove_child(child)
		child.queue_free()
	var market: Array = view.get("market", [])
	var tokens: Array = view.get("tokens", [])
	for k in market.size():
		var slot: Dictionary = market[k]
		var card: Dictionary = slot.get("card", {})
		var company := int(card.get("company", 0))
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), company, int(slot.get("coins", 0)))
		cv.selectable = _is_my_turn() and phase == "take" and _allowed("take_market", cv.card_id)
		cv.highlight = cv.selectable
		cv.blocked = _my_seat >= 0 and company < tokens.size() and tokens[company] != null and int(tokens[company]) == _my_seat
		cv.card_pressed.connect(_on_market_card_pressed)
		cv.card_held.connect(_on_card_held)
		cv.card_released.connect(_on_card_released)
		_market_row.add_child(cv)
		_place_on_felt(cv, _market_pos(k, market.size()), MARKET_CARD, ((cv.card_id * 5) % 3 - 1) * 1.5)
	var supply := int(view.get("supplyCount", 0))
	_board.supply_count = supply
	_supply_pile.visible = supply > 0
	_supply_pile.selectable = _is_my_turn() and phase == "take" and _allowed("take_supply")
	_supply_pile.highlight = _supply_pile.selectable
	_place_supply()


## Your kept shares, face up on the felt in one small stack per company.
func _render_portfolio(seats: Array) -> void:
	for child in _portfolio_layer.get_children():
		_portfolio_layer.remove_child(child)
		child.queue_free()
	if _my_seat < 0 or _my_seat >= seats.size():
		return
	var groups := []
	for company in 6:
		var ids := []
		for card in seats[_my_seat].get("portfolio", []):
			if int(card.get("company", -1)) == company:
				ids.append(int(card.get("id", -1)))
		if not ids.is_empty():
			groups.append([company, ids])
	for gi in groups.size():
		var company: int = groups[gi][0]
		var ids: Array = groups[gi][1]
		for j in ids.size():
			var cv := CardView.new()
			cv.setup(ids[j], company)
			cv.selectable = false
			cv.card_held.connect(_on_card_held)
			cv.card_released.connect(_on_card_released)
			_portfolio_layer.add_child(cv)
			_place_on_felt(cv, Vector2((gi - (groups.size() - 1) / 2.0) * 46.0, 92.0 + j * 10.0), PORTFOLIO_CARD)


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
	for i in count:
		var card: Dictionary = hand[i]
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), int(card.get("company", 0)))
		cv.scale = Vector2(_hand_scale, _hand_scale)
		cv.pivot_offset = Vector2(CardView.W / 2.0, CardView.H)
		var slot := _hand_slot(i, count)
		cv.rotation = slot["rot"]
		cv.set_rest_position(slot["pos"])
		cv.selectable = _is_my_turn() and phase == "play" and _card_playable(cv.card_id)
		cv.highlight = cv.selectable
		cv.card_pressed.connect(_on_hand_card_pressed)
		cv.card_held.connect(_on_card_held)
		cv.card_released.connect(_on_card_released)
		_hand_layer.add_child(cv)
		_hand_cards.append(cv)


## Resting place of hand card i of count: "pos" is its top-left in the hand
## layer (it scales and tilts about its bottom centre), "rot" its tilt.
func _hand_slot(i: int, count: int) -> Dictionary:
	var layer_w := _hand_layer.size.x if _hand_layer.size.x > 0 else 720.0
	var layer_h := _hand_layer.size.y if _hand_layer.size.y > 0 else CardView.H * _hand_scale + 40.0 * _s
	var card_w := CardView.W * _hand_scale
	var card_h := CardView.H * _hand_scale
	# WHY: cards scale and tilt about their bottom centre, so the outermost
	# top corner reaches card_w / 2 * cos + card_h * sin past the centre;
	# keep that on screen for a 4-card hand on every phone.
	var tilt_max := deg_to_rad(HAND_TILT_DEG * (count - 1) / 2.0)
	var reach := card_w / 2.0 * cos(tilt_max) + card_h * sin(tilt_max)
	var spacing := 62.0 * _s
	if count > 1:
		spacing = minf(spacing, (layer_w - 2.0 * (8.0 * _s + reach)) / (count - 1))
	var off := i - (count - 1) / 2.0
	var bottom := layer_h - 10.0 * _s + off * off * 4.0 * _s
	return {
		"pos": Vector2(layer_w / 2.0 + off * spacing - CardView.W / 2.0, bottom - CardView.H),
		"rot": deg_to_rad(off * HAND_TILT_DEG),
	}


## Press and hold any card to see it up close, above everything else.
func _on_card_held(cv: CardView) -> void:
	_hide_peek()
	var big := CardView.new()
	big.setup(cv.card_id, cv.company, cv.coins, cv.face_up)
	big.selectable = false
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.size = Vector2(CardView.W, CardView.H)
	big.pivot_offset = big.size / 2.0
	_peek_layer.add_child(big)
	var half := big.size * PEEK_SCALE / 2.0
	var held_center: Vector2 = cv.get_global_transform() * (big.size / 2.0)
	var held_half_h := CardView.H * cv.scale.y / 2.0
	var screen := get_viewport_rect().size
	# Above the held card when it fits, so the finger does not cover it.
	var center := Vector2(held_center.x, held_center.y - held_half_h - half.y - 16.0)
	center.x = clampf(center.x, half.x + 16.0, screen.x - half.x - 16.0)
	center.y = clampf(center.y, half.y + 80.0, screen.y - half.y - 16.0)
	big.position = center - big.size / 2.0
	big.scale = Vector2.ONE * PEEK_SCALE * 0.85
	var tw := big.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(big, "scale", Vector2.ONE * PEEK_SCALE, 0.14)
	_peek = big
	Sfx.buzz(15)


func _on_card_released(_cv: CardView) -> void:
	_hide_peek()


func _hide_peek() -> void:
	if _peek != null and is_instance_valid(_peek):
		_peek.queue_free()
	_peek = null


func _update_prompt() -> void:
	var phase := String(view.get("phase", ""))
	var mine := _is_my_turn()
	_draw_button.visible = false
	_keep_button.visible = false
	_sell_button.visible = false
	_cancel_button.visible = false
	_set_buttons_enabled(true)
	_board.glow = {}
	if phase == "ended":
		_prompt.text = "The supply is empty. Dividends are paid."
		return
	if not mine:
		if not _action_note.is_empty():
			_prompt.text = _action_note
		else:
			var seats: Array = view.get("seats", [])
			var active := int(view.get("active", 0))
			_prompt.text = "%s is thinking…" % (seats[active].get("name", "?") if active < seats.size() else "?")
		# A friend watching has no seat (Net.watch_friend).
		if _my_seat < 0:
			_prompt.text = "Watching. " + _prompt.text
		return
	if phase == "take":
		var cost = view.get("drawCost")
		var market_empty: bool = view.get("market", []).is_empty()
		if market_empty:
			_prompt.text = _hinted("Tap the supply to draw a share. The Market is empty, so it costs nothing.")
		elif cost == null:
			_prompt.text = _hinted("Not enough capital to draw. Take a share from the Market.")
		else:
			var cost_text := "free" if int(cost) == 0 else "%d capital onto the Market" % int(cost)
			_prompt.text = _hinted("Draw from the supply (%s), or tap a Market share to take it with its coins." % cost_text)
		_draw_button.visible = true
		_draw_button.disabled = not _allowed("take_supply")
		if not _draw_button.disabled:
			_board.glow = {"supply": true}
		return
	# Play step.
	if _selected_card < 0:
		_prompt.text = _hinted("Tap a share in your hand to play it.")
		return
	var company := -1
	for cv in _hand_cards:
		if cv.card_id == _selected_card:
			company = cv.company
	_prompt.text = _hinted("%s: keep it in your Portfolio or sell it to the Market?" % Companies.name_of(company))
	_keep_button.visible = true
	_sell_button.visible = true
	_cancel_button.visible = true
	_keep_button.disabled = not _allowed("play_portfolio", _selected_card)
	_sell_button.disabled = not _allowed("play_market", _selected_card)
	var glow := {}
	if not _keep_button.disabled:
		glow["portfolio"] = true
	if not _sell_button.disabled:
		glow["market"] = true
	_board.glow = glow


func _hinted(text: String) -> String:
	var hint := String(_restriction.get("hint", ""))
	return text if hint.is_empty() else "%s\n%s" % [hint, text]


func _render_result(seats: Array) -> void:
	var result = view.get("result")
	_result_backdrop.visible = result != null
	if result == null:
		return
	for child in _result_rows.get_children():
		_result_rows.remove_child(child)
		child.queue_free()
	var scores: Array = result.get("scores", []).duplicate()
	scores.sort_custom(func(a, b) -> bool: return int(a.get("rank", 1)) < int(b.get("rank", 1)))
	for sc in scores:
		var seat_idx := int(sc.get("seat", 0))
		var seat: Dictionary = seats[seat_idx] if seat_idx < seats.size() else {}
		var who := "You" if seat_idx == _my_seat else String(seat.get("name", "?"))
		_result_rows.add_child(_result_row(int(sc.get("rank", 1)), who, int(sc.get("bronze", 0)), int(sc.get("gold", 0)), int(sc.get("score", 0))))
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


## One standings row: place, name over "bronze + gold", score.
func _result_row(rank: int, who: String, bronze: int, gold: int, score: int) -> Control:
	var row := PanelContainer.new()
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = Color(Companies.INK, 0.2)
	line.border_width_bottom = 1
	line.content_margin_top = 8 * _s
	line.content_margin_bottom = 8 * _s
	row.add_theme_stylebox_override("panel", line)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(10))
	row.add_child(h)
	var place := UiTheme.label(str(rank), _px(16), Companies.INK, true)
	place.custom_minimum_size = Vector2(_px(22), 0)
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(place)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(names)
	names.add_child(UiTheme.label(who, _px(14), Companies.INK, rank == 1))
	var detail := UiTheme.label("%d bronze + %d gold" % [bronze, gold], _px(11), UiTheme.MUTED)
	detail.add_theme_font_override("font", UiTheme.body_font())
	names.add_child(detail)
	var total := UiTheme.label(str(score), _px(18), Companies.INK, true)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(total)
	return row


# ---------------------------------------------------------------------------
# Animations: play the events between the previous and the current view,
# then render the new view. Positions come from the previous layout.
# ---------------------------------------------------------------------------

func _seat_anchor(seat_idx: int) -> Vector2:
	for sv in _seat_views:
		if sv.visible and sv.seat_index == seat_idx:
			return sv.avatar_center()
	return get_viewport_rect().size / 2.0


func _center_of(cv: CardView) -> Vector2:
	return cv.get_global_transform() * (Vector2(CardView.W, CardView.H) / 2.0)


func _market_card_anchor(card_id: int) -> Vector2:
	for cv in _market_row.get_children():
		if cv is CardView and cv.card_id == card_id:
			return _center_of(cv)
	return _center_of(_supply_pile)


func _hand_anchor(card_id: int) -> Vector2:
	for cv in _hand_cards:
		if cv.card_id == card_id:
			return _center_of(cv)
	return _hand_layer.global_position + _hand_layer.size / 2.0


## Scale of a card on the felt at `p`, as `_place_on_felt` would set it.
func _felt_scale(p: Vector2, card: float) -> float:
	return card * _board.depth(p) * _s * 100.0 / CardView.W


func _seat_name(seat: int) -> String:
	var seats: Array = view.get("seats", [])
	return String(seats[seat].get("name", "Someone")) if seat >= 0 and seat < seats.size() else "Someone"


func _play_events_then_render() -> void:
	if _animating:
		return
	_animating = true
	var events := _pending_events.duplicate()
	_pending_events.clear()
	var supply_c := _center_of(_supply_pile)
	var supply_k := _felt_scale(TableBoard.SUPPLY_AT, SUPPLY_CARD)
	var small_k := 0.2 * _s * 100.0 / CardView.W
	for e in events:
		var seat := int(e.get("seat", 0))
		var mine := seat == _my_seat
		match String(e.get("type", "")):
			"took_supply":
				var cost := int(e.get("cost", 0))
				if cost > 0:
					sfx.play("coin")
					var d := 0.0
					for cv in _market_row.get_children():
						if cv is CardView and not cv.blocked:
							_fly_coin(_seat_anchor(seat), _center_of(cv), false, d)
							d = minf(d + 0.04, 0.12)
					await get_tree().create_timer(COIN_TIME + d).timeout
				_action_note = "" if mine else "%s draws from the supply%s." % [_seat_name(seat), " and pays %d capital onto the Market" % cost if cost > 0 else ""]
				sfx.play("deal")
				if mine:
					await _fly_to_hand(supply_c, supply_k)
				else:
					await _fly_card(supply_c, _seat_anchor(seat), 0, false, supply_k, small_k)
			"took_market":
				var card: Dictionary = e.get("card", {})
				var coins := int(e.get("coins", 0))
				var company := int(card.get("company", 0))
				sfx.play("coin" if coins > 0 else "deal")
				var from := _market_card_anchor(int(card.get("id", -1)))
				_action_note = "" if mine else "%s takes a %s share from the Market%s." % [_seat_name(seat), Companies.name_of(company), " with %d capital on it" % coins if coins > 0 else ""]
				for i in mini(coins, 8):
					_fly_coin(from, _seat_anchor(seat), false, i * 0.07)
				var market_k := _felt_scale(_market_pos(0, 1), MARKET_CARD)
				if mine:
					await _fly_to_hand(from, market_k)
				else:
					await _fly_card(from, _seat_anchor(seat), company, true, market_k, small_k)
			"played":
				var card: Dictionary = e.get("card", {})
				var company := int(card.get("company", 0))
				var to_market: bool = e.get("to") != "portfolio"
				var from := _hand_anchor(int(card.get("id", -1))) if mine else _seat_anchor(seat)
				var from_k := _hand_scale if mine else small_k
				var to := _seat_anchor(seat)
				var to_k := small_k
				if to_market:
					var m: int = _market_row.get_child_count()
					var p := _market_pos(m, m + 1)
					to = _board.get_global_transform() * _board.project(p)
					to_k = _felt_scale(p, MARKET_CARD)
				elif mine:
					var p := TableBoard.zone_center(TableBoard.ZONE_PORTFOLIO)
					to = _board.get_global_transform() * _board.project(p)
					to_k = _felt_scale(p, PORTFOLIO_CARD)
				if not mine:
					_action_note = "%s %s %s%s." % [_seat_name(seat), "sells" if to_market else "keeps", Companies.name_of(company), " to the Market" if to_market else ""]
				await _fly_card(from, to, company, true, from_k, to_k)
				sfx.play("place")
				if mine:
					Sfx.buzz(25)
			"token_moved":
				# WHY: not awaited, so the stamp lands while play carries on
				# instead of holding up the next view.
				_stamp_token(int(e.get("to", 0)), int(e.get("company", 0)))
			"game_ended":
				await _animate_dividends(e.get("result", {}))
	_animating = false
	_render()
	if not _pending_events.is_empty():
		_play_events_then_render()


## A regulator token changing hands: a gold seal stamps down on the new
## holder's seat, with the company named in a bubble.
func _stamp_token(seat: int, company: int) -> void:
	var seal := Label.new()
	seal.text = "R"
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_theme_font_override("font", UiTheme.display_font())
	seal.add_theme_font_size_override("font_size", _px(22))
	seal.add_theme_color_override("font_color", Companies.INK)
	var style := StyleBoxFlat.new()
	style.bg_color = Companies.GOLD
	style.border_color = Companies.color_of(company)
	style.set_border_width_all(_px(4))
	style.set_corner_radius_all(_px(40))
	seal.add_theme_stylebox_override("normal", style)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.size = Vector2(_px(44), _px(44))
	seal.pivot_offset = seal.size / 2.0
	_fx_layer.add_child(seal)
	seal.global_position = _seat_anchor(seat) - seal.size / 2.0
	seal.scale = Vector2.ONE * 2.2
	seal.modulate.a = 0.0
	_show_bubble(seat, "%s token" % Companies.short_name_of(company))
	sfx.play("place")
	var tw := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(seal, "scale", Vector2.ONE, 0.22)
	tw.parallel().tween_property(seal, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.45)
	tw.tween_property(seal, "modulate:a", 0.0, 0.25)
	await tw.finished
	seal.queue_free()


func _target_for_seat(seat: int) -> Vector2:
	if seat == _my_seat:
		return _hand_layer.global_position + _hand_layer.size / 2.0
	return _seat_anchor(seat)


## Where a share you just took will sit: the slot of the card in the new
## view's hand that the hand on screen does not show yet ({} if none).
func _new_hand_slot() -> Dictionary:
	var seats: Array = view.get("seats", [])
	if _my_seat < 0 or _my_seat >= seats.size():
		return {}
	var hand: Array = seats[_my_seat].get("hand", [])
	var shown := {}
	for cv in _hand_cards:
		shown[cv.card_id] = true
	for i in hand.size():
		if not shown.has(int(hand[i].get("id", -1))):
			var slot := _hand_slot(i, hand.size())
			slot["company"] = int(hand[i].get("company", 0))
			return slot
	return {}


## A share you took hops face up from `from` (its centre, at scale
## `from_k`) into its own slot in your hand, so the hand drawn next shows
## it exactly where it landed.
func _fly_to_hand(from: Vector2, from_k: float) -> void:
	var slot := _new_hand_slot()
	if slot.is_empty():
		await _fly_card(from, _target_for_seat(_my_seat), 0, false, from_k, _hand_scale)
		return
	var ghost := CardView.new()
	ghost.setup(-1, int(slot["company"]), 0, true)
	ghost.selectable = false
	ghost.pivot_offset = Vector2(CardView.W / 2.0, CardView.H)
	_fx_layer.add_child(ghost)
	ghost.scale = Vector2(from_k, from_k)
	var start := from - ghost.pivot_offset + Vector2(0, CardView.H / 2.0 * from_k)
	var end: Vector2 = _hand_layer.global_position + slot["pos"]
	ghost.global_position = start
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(t: float) -> void:
		ghost.global_position = start.lerp(end, t) + Vector2(0, -sin(t * PI) * 60.0 * _s), 0.0, 1.0, FLY_TIME)
	tw.tween_property(ghost, "scale", Vector2(_hand_scale, _hand_scale), FLY_TIME)
	tw.tween_property(ghost, "rotation", float(slot["rot"]), FLY_TIME)
	await tw.finished
	ghost.queue_free()


## A card hops from centre `from` to centre `to`, growing or shrinking
## from scale `from_k` to `to_k` on the way.
func _fly_card(from: Vector2, to: Vector2, company: int, face_up: bool, from_k: float = 1.0, to_k: float = 1.0) -> void:
	var ghost := CardView.new()
	ghost.setup(-1, company, 0, face_up)
	ghost.selectable = false
	ghost.pivot_offset = Vector2(CardView.W, CardView.H) / 2.0
	_fx_layer.add_child(ghost)
	ghost.scale = Vector2(from_k, from_k)
	var a := from - ghost.pivot_offset
	var b := to - ghost.pivot_offset
	ghost.global_position = a
	var hop := 40.0 * _s
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(t: float) -> void:
		ghost.global_position = a.lerp(b, t) + Vector2(0, -sin(t * PI) * hop), 0.0, 1.0, FLY_TIME)
	tw.tween_property(ghost, "scale", Vector2(to_k, to_k), FLY_TIME)
	await tw.finished
	ghost.queue_free()


## A bronze (or gold) coin hops from one point to another after `delay`.
func _fly_coin(from: Vector2, to: Vector2, gold: bool = false, delay: float = 0.0) -> void:
	var coin := Panel.new()
	var r := 9.0 * _s
	var face := StyleBoxFlat.new()
	face.bg_color = Companies.GOLD if gold else Companies.BRONZE
	face.border_color = Companies.INK
	face.set_border_width_all(2)
	face.border_width_bottom = 4
	face.set_corner_radius_all(int(r) + 2)
	coin.add_theme_stylebox_override("panel", face)
	coin.size = Vector2(r, r) * 2.0
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.visible = delay <= 0.0
	_fx_layer.add_child(coin)
	coin.global_position = from - Vector2(r, r)
	var a := from - Vector2(r, r)
	var b := to - Vector2(r, r)
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: coin.visible = true)
	tw.tween_method(func(t: float) -> void:
		coin.global_position = a.lerp(b, t) + Vector2(0, -sin(t * PI) * 50.0 * _s), 0.0, 1.0, COIN_TIME).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
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
		if not div.get("payments", []).is_empty():
			sfx.play("gold")
		for p in div.get("payments", []):
			for i in mini(int(p.get("coins", 0)), 8):
				_fly_coin(_seat_anchor(int(p.get("from", 0))), to, true)
				any = true
				await get_tree().create_timer(0.05).timeout
		if any:
			await get_tree().create_timer(0.45).timeout
	_status.text = "Dividend day!"
	sfx.play("fanfare")
