class_name Coach
extends Control
## Tutorial coach: watches views and events during a game against bots and
## explains each rule the first time it matters. Each step fires once, in
## priority order, as a modal card the learner dismisses with "Got it".

signal step_shown(step_id: String)
signal finished

const STEPS := [
	{
		"id": "welcome",
		"title": "Welcome to Big Business",
		"body": "Six companies are up for grabs. Collect shares, and on dividend day whoever holds the most shares of a company gets paid by everyone else who holds that company. Most capital wins.\n\nYou play against two bots. Take your time: there is no timer in the tutorial.",
	},
	{
		"id": "first_take",
		"title": "Your turn: take a share",
		"body": "Every turn has two steps: take one share, then play one share.\n\nThe Market is empty right now, so draw from the supply. Later, drawing costs 1 coin for every share sitting in the Market.",
	},
	{
		"id": "first_play",
		"title": "Now play a share",
		"body": "Tap a card in your hand. You can keep it in your portfolio (face up, it counts toward majorities) or sell it to the Market (anyone can take it later).\n\nOne rule: you can't sell the company you just took.",
	},
	{
		"id": "bot_paid",
		"title": "Drawing costs coins",
		"body": "%s drew from the supply and paid 1 coin onto every share in the Market.\n\nThose coins stay on the shares. Whoever takes a share from the Market collects its coins.",
	},
	{
		"id": "take_with_coins",
		"title": "Free money in the Market",
		"body": "A Market share with coins on it is worth grabbing: taking from the Market is free and you pocket the coins.\n\nDrawing from the supply instead would cost you 1 coin per Market share.",
	},
	{
		"id": "token_first",
		"title": "The regulator token",
		"body": "%s now holds the most %s shares and gets that company's regulator token.\n\nWhile you hold a token you can't take that company from the Market, but you also don't pay onto its shares when you draw.",
	},
	{
		"id": "token_blocks",
		"title": "Your token at work",
		"body": "You hold the %s token, so that %s share in the Market is off limits for you. Everyone else can take it.\n\nThe upside: drawing is cheaper for you while those shares sit there.",
	},
	{
		"id": "endgame_near",
		"title": "The supply is almost empty",
		"body": "When the last share is drawn, the game ends after that player's turn.\n\nThe three cards still in your hand join your portfolio, so they count. Plan the final reveal.",
	},
	{
		"id": "dividend",
		"title": "Dividend day",
		"body": "For each company, the sole majority holder collects 1 coin per share from every other holder. Coins received flip to gold and are worth 3.\n\nTies pay nothing. You now know every rule: press Play again for a real game.",
	},
]

var enabled := true
var seen: Dictionary = {}
var _queue: Array = []
var _showing := false
var _panel: PanelContainer
var _title: Label
var _body: Label
var _got_it: Button
var _skip: Button
var _view: Dictionary = {}
var _my_seat := -1
var _first_play_seen := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1E2A44")
	style.border_color = Companies.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	var tag := Label.new()
	tag.text = "TUTORIAL"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(tag)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Companies.GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 19)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_skip = Button.new()
	_skip.text = "Skip tutorial"
	_skip.custom_minimum_size = Vector2(0, 52)
	_skip.pressed.connect(_on_skip)
	buttons.add_child(_skip)
	_got_it = Button.new()
	_got_it.text = "Got it"
	_got_it.custom_minimum_size = Vector2(160, 52)
	_got_it.add_theme_font_size_override("font_size", 18)
	_got_it.pressed.connect(_on_got_it)
	buttons.add_child(_got_it)
	visible = false


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
	visible = true
	step_shown.emit(item["id"])


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
	_queue.append({"id": id, "title": step["title"], "body": body})
	_show_next()


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
