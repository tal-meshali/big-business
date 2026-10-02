class_name Coach
extends Control
## Tutorial coach: watches views and events during a game against bots and
## explains each rule the first time it matters. Each step fires once, in
## priority order, as a modal card the learner dismisses with "Got it". The
## table is dimmed except the area the step is about (the supply, the
## Market, your hand, the plates), and the card sits clear of that area.
##
## On the learner's first FORCED_TURNS turns only the coached move is
## enabled (see `restriction`): keep a share on turn one; on turn two take
## the Market share carrying coins if there is one, then sell a share.

signal step_shown(step_id: String)
signal finished

const STEPS := [
	{
		"id": "welcome",
		"spot": "",
		"title": "Welcome to Big Business",
		"body": "Six companies are up for grabs. Collect shares, and on dividend day whoever holds the most shares of a company gets paid by everyone else who holds that company. Most capital wins.\n\nYou play against two bots. Take your time: there is no timer in the tutorial.",
	},
	{
		"id": "first_take",
		"spot": "supply",
		"title": "Your turn: take a share",
		"body": "Every turn has two steps: take one share, then play one share.\n\nThe Market is empty right now, so draw from the supply. Later, drawing costs 1 coin for every share sitting in the Market.",
	},
	{
		"id": "first_play",
		"spot": "hand",
		"title": "Now play a share",
		"body": "Tap a card in your hand. You can keep it in your portfolio (face up, it counts toward majorities) or sell it to the Market (anyone can take it later).\n\nOne rule: you can't sell the company you just took.",
	},
	{
		"id": "first_sell",
		"spot": "hand",
		"title": "Selling to the Market",
		"body": "This time, sell a share. It goes into the Market with no coins on it, and anyone can take it later.\n\nSell companies you are not collecting: every share you hold of a company someone else leads costs you a coin on dividend day.",
	},
	{
		"id": "bot_paid",
		"spot": "market",
		"title": "Drawing costs coins",
		"body": "%s drew from the supply and paid 1 coin onto every share in the Market.\n\nThose coins stay on the shares. Whoever takes a share from the Market collects its coins.",
	},
	{
		"id": "take_with_coins",
		"spot": "market",
		"title": "Free money in the Market",
		"body": "A Market share with coins on it is worth grabbing: taking from the Market is free and you pocket the coins.\n\nDrawing from the supply instead would cost you 1 coin per Market share.",
	},
	{
		"id": "token_first",
		"spot": "plates",
		"title": "The regulator token",
		"body": "%s now holds the most %s shares and gets that company's regulator token.\n\nWhile you hold a token you can't take that company from the Market, but you also don't pay onto its shares when you draw.",
	},
	{
		"id": "token_blocks",
		"spot": "market",
		"title": "Your token at work",
		"body": "You hold the %s token, so that %s share in the Market is off limits for you. Everyone else can take it.\n\nThe upside: drawing is cheaper for you while those shares sit there.",
	},
	{
		"id": "endgame_near",
		"spot": "supply",
		"title": "The supply is almost empty",
		"body": "When the last share is drawn, the game ends after that player's turn.\n\nThe three cards still in your hand join your portfolio, so they count. Plan the final reveal.",
	},
	{
		"id": "dividend",
		"spot": "",
		"title": "Dividend day",
		"body": "For each company, the sole majority holder collects 1 coin per share from every other holder. Coins received flip to gold and are worth 3.\n\nTies pay nothing. You now know every rule: press Play again for a real game.",
	},
]

const FORCED_TURNS := 2

var enabled := true
var seen: Dictionary = {}
## Returns the screen rect to point at for a step's "spot" key (the table's
## coach_spot); an empty rect means no spotlight.
var spot_provider: Callable
var _queue: Array = []
var _showing := false
var _panel: PanelContainer
var _title: Label
var _body: Label
var _meta: Label
var _dots: HBoxContainer
var _got_it: Button
var _skip: Button
var _view: Dictionary = {}
var _my_seat := -1
var _first_play_seen := false
var _s := 1.85
## The lit-up area; everything else is dimmed.
var _spot := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Modal: the dimmed table under the card takes no taps.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_s = UiTheme.layout_scale(get_viewport_rect().size)
	_build()


func _build() -> void:
	var deed := UiTheme.deed_panel(UiTheme.RING, "", Companies.INK)
	_panel = deed["panel"]
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 14 * _s
	_panel.offset_right = -14 * _s
	add_child(_panel)
	_title = deed["title"]
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", int(18 * _s))
	var band_box: StyleBoxFlat = deed["band"].get_theme_stylebox("panel").duplicate()
	band_box.content_margin_top = 11 * _s
	band_box.content_margin_bottom = 11 * _s
	band_box.content_margin_left = 14 * _s
	deed["band"].add_theme_stylebox_override("panel", band_box)
	var margins: MarginContainer = deed["body"]
	margins.add_theme_constant_override("margin_left", int(14 * _s))
	margins.add_theme_constant_override("margin_right", int(14 * _s))
	margins.add_theme_constant_override("margin_top", int(10 * _s))
	margins.add_theme_constant_override("margin_bottom", int(14 * _s))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(10 * _s))
	margins.add_child(box)
	# "TUTORIAL · 3 OF 10" and one dot per step.
	var meta := HBoxContainer.new()
	box.add_child(meta)
	_meta = UiTheme.label("TUTORIAL", int(11 * _s), UiTheme.MUTED)
	_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_meta)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", int(4 * _s))
	_dots.alignment = BoxContainer.ALIGNMENT_END
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(_dots)
	for i in STEPS.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 6) * _s
		_dots.add_child(dot)
	_body = UiTheme.label("", int(15 * _s))
	_body.add_theme_font_override("font", UiTheme.body_font())
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(8 * _s))
	box.add_child(buttons)
	_skip = UiTheme.button("Skip tutorial", int(14 * _s), 44 * _s, "ghost")
	_skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip.pressed.connect(_on_skip)
	buttons.add_child(_skip)
	_got_it = UiTheme.button("Got it", int(14 * _s), 44 * _s, "primary")
	_got_it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_got_it.pressed.connect(_on_got_it)
	buttons.add_child(_got_it)
	visible = false


## Dims the table except the spotlit area, which gets an orange ring.
func _draw() -> void:
	var dim := Color(0.03, 0.07, 0.05, 0.64)
	var full := Rect2(Vector2.ZERO, size)
	if _spot.size == Vector2.ZERO:
		draw_rect(full, dim)
		return
	var r := _spot.intersection(full)
	draw_rect(Rect2(0, 0, size.x, r.position.y), dim)
	draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), dim)
	draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
	draw_rect(Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y), dim)
	# Round the hole's corners to match the ring.
	var rad := 18.0 * _s
	for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [r.end, Vector2(-1, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]:
		var at: Vector2 = corner[0]
		var dir: Vector2 = corner[1]
		var center := at + dir * rad
		var patch := PackedVector2Array([at])
		for i in 9:
			patch.append(center + Vector2(-dir.x * cos(PI / 2.0 * i / 8.0), -dir.y * sin(PI / 2.0 * i / 8.0)) * rad)
		draw_colored_polygon(patch, dim)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = UiTheme.RING
	ring.set_border_width_all(int(3 * _s))
	ring.set_corner_radius_all(int(18 * _s))
	ring.anti_aliasing = true
	draw_style_box(ring, r)


func _on_skip() -> void:
	enabled = false
	_queue.clear()
	_showing = false
	visible = false
	finished.emit()


func _on_got_it() -> void:
	_showing = false
	visible = false
	_show_next()


func _show_next() -> void:
	if _showing or _queue.is_empty() or not enabled:
		return
	var item: Dictionary = _queue.pop_front()
	_showing = true
	_title.text = item["title"]
	_body.text = item["body"]
	var n: int = item.get("n", 1)
	_meta.text = "TUTORIAL · %d OF %d" % [n, STEPS.size()]
	for i in _dots.get_child_count():
		var dot := StyleBoxFlat.new()
		dot.bg_color = UiTheme.RING if i < n else Companies.PANEL
		dot.border_color = Companies.INK
		dot.set_border_width_all(2)
		dot.set_corner_radius_all(int(3 * _s))
		_dots.get_child(i).add_theme_stylebox_override("panel", dot)
	var key := String(item.get("spot", ""))
	_spot = spot_provider.call(key) if key != "" and spot_provider.is_valid() else Rect2()
	visible = true
	_panel.modulate.a = 0.0
	_place_card()
	queue_redraw()
	step_shown.emit(item["id"])


## Puts the card where it does not cover the spotlight: under a spot in the
## top half of the screen, near the top for one lower down, centred without.
func _place_card() -> void:
	# WHY: the wrapped text only knows its height once the card has its
	# width, so let one layout pass run before measuring.
	_panel.offset_bottom = _panel.offset_top
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var screen := get_viewport_rect().size
	var h := _panel.get_combined_minimum_size().y
	var top := (screen.y - h) / 2.0
	if _spot.size != Vector2.ZERO:
		if _spot.get_center().y < screen.y / 2.0:
			top = minf(_spot.end.y + 16 * _s, screen.y - h - 16 * _s)
		else:
			top = maxf(64 * _s, minf(_spot.position.y - h - 16 * _s, 64 * _s))
	_panel.offset_top = top
	_panel.offset_bottom = top + h
	_panel.pivot_offset = Vector2(_panel.size.x / 2.0, h / 2.0)
	_panel.scale = Vector2.ONE * 0.92
	_panel.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.3)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)


func _step(id: String) -> Dictionary:
	for s in STEPS:
		if s["id"] == id:
			return s
	return {}


func _fire(id: String, args: Array = []) -> void:
	if not enabled or seen.has(id):
		return
	var step := _step(id)
	if step.is_empty():
		return
	seen[id] = true
	var body: String = step["body"]
	if args.size() > 0:
		body = body % args
	_queue.append({"id": id, "title": step["title"], "body": body, "spot": step.get("spot", ""), "n": seen.size()})
	_show_next()


## Which of my turns this view is (1 for my first), or 0 when it is not my
## turn. Seats act in order from turn 1, so it follows from the turn number.
static func my_turn_index(view: Dictionary) -> int:
	if view.get("you") == null or view.get("phase") == "ended":
		return 0
	var me := int(view["you"])
	var n: int = view.get("seats", []).size()
	if n == 0 or int(view.get("active", -1)) != me:
		return 0
	return floori(float(int(view.get("turn", 1)) - 1 - me) / n) + 1


## The coached move on the learner's first turns, or {} for free play.
## Keys: "take" = "supply" | "market_coins", "play" = "portfolio" | "market",
## "hint" = one line for the prompt. Only restricts to moves that are legal.
func restriction(view: Dictionary) -> Dictionary:
	if not enabled:
		return {}
	var index := my_turn_index(view)
	if index < 1 or index > FORCED_TURNS:
		return {}
	var legal: Array = view.get("legal", [])
	if view.get("phase") == "take":
		if index == 2:
			for slot in view.get("market", []):
				if int(slot.get("coins", 0)) > 0 and _has_legal(legal, "take_market", int(slot["card"]["id"])):
					return {"take": "market_coins", "hint": "Tutorial: take the Market share with coins on it."}
		if _has_legal(legal, "take_supply", -1):
			return {"take": "supply", "hint": "Tutorial: draw from the supply."}
		return {}
	if index == 1:
		return {"play": "portfolio", "hint": "Tutorial: keep a share this time. Tap a card, then Keep."}
	if _has_legal(legal, "play_market", -1):
		return {"play": "market", "hint": "Tutorial: sell a share to the Market this time."}
	return {}


static func _has_legal(legal: Array, type: String, card_id: int) -> bool:
	for a in legal:
		if a.get("type") == type and (card_id < 0 or int(a.get("cardId", -1)) == card_id):
			return true
	return false


## Called by the table with every view (after events have been animated).
func on_view(view: Dictionary) -> void:
	if not enabled:
		return
	_view = view
	_my_seat = int(view.get("you", -1)) if view.get("you") != null else -1
	var phase := String(view.get("phase", ""))
	var my_turn := _my_seat >= 0 and int(view.get("active", -1)) == _my_seat
	var market: Array = view.get("market", [])
	var seats: Array = view.get("seats", [])

	_fire("welcome")
	if phase == "ended":
		_fire("dividend")
		return
	if not my_turn:
		return
	if phase == "take":
		if market.is_empty():
			_fire("first_take")
		if int(view.get("supplyCount", 99)) <= 3:
			_fire("endgame_near", [])
		var my_tokens: Array = seats[_my_seat].get("tokens", []) if _my_seat < seats.size() else []
		for slot in market:
			var company := int(slot.get("card", {}).get("company", -1))
			if my_tokens.has(company):
				var cname := Companies.name_of(company)
				_fire("token_blocks", [cname, cname])
				break
		for slot in market:
			if int(slot.get("coins", 0)) > 0 and not my_tokens.has(int(slot.get("card", {}).get("company", -1))):
				_fire("take_with_coins")
				break
	elif phase == "play":
		_fire("first_play")
		if restriction(view).get("play", "") == "market":
			_fire("first_sell")


## Called by the table with each event batch, before animations play.
func on_events(events: Array) -> void:
	if not enabled:
		return
	var seats: Array = _view.get("seats", [])
	for e in events:
		var type := String(e.get("type", ""))
		var seat := int(e.get("seat", -1))
		if type == "took_supply" and seat != _my_seat and int(e.get("cost", 0)) > 0:
			var who := String(seats[seat].get("name", "A bot")) if seat < seats.size() else "A bot"
			_fire("bot_paid", [who])
		elif type == "token_moved":
			var to := int(e.get("to", -1))
			var who := "You" if to == _my_seat else (String(seats[to].get("name", "Someone")) if to < seats.size() else "Someone")
			_fire("token_first", [who, Companies.name_of(int(e.get("company", 0)))])
