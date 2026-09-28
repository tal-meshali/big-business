class_name Coach
extends Control
## Tutorial coach: watches views and events during a game against bots and
## explains each rule the first time it matters, after the design canvas: a
## dark shade with a spotlight cut out around the thing being explained, and
## a deed card with an orange band, a step counter with dots, the text, and
## either "Got it" (a rule) or a hint row with a tapping hand (a guided
## move, where the spotlight stays interactive so the learner acts through it).
##
## The learner's first GUIDED_TURNS turns are guided: the coach picks one
## action per step (forced_action), the table enables only that action
## (allows) and pulses the card to tap (highlight_card_id).

signal step_shown(step_id: String)
signal finished

## Learner turns during which only the coached action is enabled.
const GUIDED_TURNS := 2
## Distinct cards a run can show (the two "second turn" pairs are alternates).
const SLOTS := 11
const SHADE := Color("#08120D", 0.64)

## Each step: `spot` names the table region to spotlight ("supply", "market",
## "hand", "bar" or "full"); a `hint` marks a guided move and is shown in
## place of "Got it" ({name} is the company).
const STEPS := [
	{
		"id": "welcome",
		"title": "Welcome to Big Business",
		"spot": "full",
		"body": "Six companies are up for grabs. Collect shares, and on dividend day whoever holds the most shares of a company gets paid by everyone else who holds that company. Most capital wins.\n\nYou play against two bots. Take your time: there is no timer in the tutorial. For your first two turns the coach picks the move; after that you are on your own.",
	},
	{
		"id": "first_take",
		"title": "Your turn: take a share",
		"spot": "supply",
		"hint": "Tap the glowing supply",
		"body": "Every turn has two steps: take one share, then play one share.\n\nThe Market is empty right now, so there is nothing to take: draw from the supply. Later, drawing costs 1 coin for every share sitting in the Market.",
	},
	{
		"id": "first_play",
		"title": "Now play a share",
		"spot": "hand",
		"hint": "Tap {name}, then Keep",
		"body": "Tap a card in your hand. You can keep it in your portfolio (face up, it counts toward majorities) or sell it to the Market (anyone can take it later).\n\nStart with the company you hold most of. Keep the %s share: tap it, then Keep.",
	},
	{
		"id": "second_take",
		"title": "Your second turn: grab the coins",
		"spot": "market",
		"hint": "Tap the {name} share",
		"body": "Taking from the Market is free, and the coins sitting on a share go to whoever takes it.\n\nTake the %s share and pocket its %d coins: tap it in the Market.",
	},
	{
		"id": "second_take_draw",
		"title": "Your second turn: take a share",
		"spot": "supply",
		"hint": "Tap the glowing supply",
		"body": "No Market share carries coins yet, so there is nothing to pocket.\n\nDraw from the supply again.",
	},
	{
		"id": "second_play",
		"title": "Now sell a share",
		"spot": "hand",
		"hint": "Tap {name}, then Sell to Market",
		"body": "A lone share of a company you are not collecting only costs you on dividend day, so get it out of your hand. Selling puts it in the Market, where anyone can take it.\n\nSell the %s share: tap it, then Sell to Market. Remember: you can't sell the company you just took.",
	},
	{
		"id": "second_play_keep",
		"title": "Keep building",
		"spot": "hand",
		"hint": "Tap {name}, then Keep",
		"body": "Selling a share to the Market gets a lone company out of your hand, but you can't sell the company you just took, and every other card you hold is one you are collecting.\n\nKeep the %s share: tap it, then Keep.",
	},
	{
		"id": "bot_paid",
		"title": "Drawing costs coins",
		"spot": "market",
		"body": "%s drew from the supply and paid 1 coin onto every share in the Market.\n\nThose coins stay on the shares. Whoever takes a share from the Market collects its coins.",
	},
	{
		"id": "take_with_coins",
		"title": "Free money in the Market",
		"spot": "market",
		"body": "A Market share with coins on it is worth grabbing: taking from the Market is free and you pocket the coins.\n\nDrawing from the supply instead would cost you 1 coin per Market share.",
	},
	{
		"id": "token_first",
		"title": "The regulator token",
		"spot": "bar",
		"body": "%s now holds the most %s shares and gets that company's regulator token: the R on the marker.\n\nWhile you hold a token you can't take that company from the Market, but you also don't pay onto its shares when you draw.",
	},
	{
		"id": "token_blocks",
		"title": "Your token at work",
		"spot": "market",
		"body": "You hold the %s token, so that striped %s share in the Market is off limits for you. Everyone else can take it.\n\nThe upside: drawing is cheaper for you while those shares sit there.",
	},
	{
		"id": "endgame_near",
		"title": "The supply is almost empty",
		"spot": "supply",
		"body": "When the last share is drawn, the game ends after that player's turn.\n\nThe three cards still in your hand join your portfolio, so they count. Plan the final reveal.",
	},
	{
		"id": "dividend",
		"title": "Dividend day",
		"spot": "full",
		"body": "For each company, the sole majority holder collects 1 coin per share from every other holder. Coins received flip to gold and are worth 3.\n\nTies pay nothing. You now know every rule: press Play again for a real game.",
	},
]

var enabled := true
var seen: Dictionary = {}
## Card the table should pulse while an action is forced; -1 when none.
var highlight_card_id := -1
## Spotlight regions (global px) by name, refreshed by the table each render.
var targets: Dictionary = {}
var _queue: Array = []
var _showing := false
var _current: Dictionary = {}
var _panel: PanelContainer
var _title: Label
var _meta: Label
var _dots: HBoxContainer
var _body: Label
var _got_it: Button
var _skip: Button
var _skip_small: Button
var _hint_row: HBoxContainer
var _hint_label: Label
var _buttons_row: HBoxContainer
var _view: Dictionary = {}
var _my_seat := -1
## Number of the learner's own turns seen so far (1 during the first turn).
var _learner_turns := 0
var _last_turn := -1
## The coached action in wire form, or {} when nothing is forced.
var _forced: Dictionary = {}
var _time := 0.0
var _placing := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _build() -> void:
	var p := UiTheme.SCALE
	var deed := UiTheme.deed_panel(Companies.CHANCE, "", Companies.INK)
	_panel = deed["panel"]
	_panel.name = "Card"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_title = deed["title"]
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(10 * p))
	deed["body"].add_child(box)

	var meta_row := HBoxContainer.new()
	box.add_child(meta_row)
	_meta = UiTheme.label("TUTORIAL", 11, "bold", Companies.CAPTION)
	_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_meta)
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", int(4 * p))
	meta_row.add_child(_dots)
	for i in SLOTS:
		var dot := PanelContainer.new()
		dot.add_theme_stylebox_override("panel", UiTheme.flat(Companies.PANEL, Companies.INK, 1.5 * p, 3 * p))
		dot.custom_minimum_size = Vector2(14 * p, 6 * p)
		_dots.add_child(dot)

	_body = UiTheme.label("", 15, "body")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)

	_buttons_row = HBoxContainer.new()
	_buttons_row.alignment = BoxContainer.ALIGNMENT_END
	_buttons_row.add_theme_constant_override("separation", int(8 * p))
	box.add_child(_buttons_row)
	_skip = UiTheme.button("Skip tutorial", "GhostButton", 44)
	_skip.pressed.connect(_on_skip)
	_buttons_row.add_child(_skip)
	_got_it = UiTheme.button("Got it", "PrimaryButton", 44)
	_got_it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_got_it.pressed.connect(_on_got_it)
	_buttons_row.add_child(_got_it)

	_hint_row = HBoxContainer.new()
	_hint_row.add_theme_constant_override("separation", int(8 * p))
	box.add_child(_hint_row)
	var hint_box := PanelContainer.new()
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color.TRANSPARENT
	hint_style.border_color = Companies.CHANCE
	hint_style.set_border_width_all(int(2 * p))
	hint_style.set_corner_radius_all(int(10 * p))
	hint_style.content_margin_left = 12 * p
	hint_style.content_margin_right = 12 * p
	hint_style.anti_aliasing = true
	hint_box.add_theme_stylebox_override("panel", hint_style)
	hint_box.custom_minimum_size = Vector2(0, 44 * p)
	hint_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_row.add_child(hint_box)
	var hint_inner := HBoxContainer.new()
	hint_inner.add_theme_constant_override("separation", int(8 * p))
	hint_box.add_child(hint_inner)
	var hand := GlyphIcon.new("hand", 22 * p)
	hand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_inner.add_child(hand)
	_hint_label = UiTheme.label("", 14, "bold")
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_inner.add_child(_hint_label)
	_skip_small = UiTheme.button("Skip", "GhostButton", 44)
	_skip_small.pressed.connect(_on_skip)
	_hint_row.add_child(_skip_small)
	visible = false


## Blocks input everywhere except inside the spotlight of a guided step.
func _has_point(point: Vector2) -> bool:
	if _current.is_empty() or not _current.has("hint"):
		return true
	var cut := _cutout()
	return not (cut.size.x > 0 and cut.has_point(point + global_position))


## Spotlight rectangle (global px) for the current step, or a zero rect.
func _cutout() -> Rect2:
	var spot := String(_current.get("spot", "full"))
	if spot == "full" or not targets.has(spot):
		return Rect2()
	return targets[spot]


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	var cut := _cutout()
	if cut.size.x <= 0:
		draw_rect(full, SHADE, true)
		return
	cut = Rect2(cut.position - global_position, cut.size)
	# Four shade rectangles around the spotlight.
	draw_rect(Rect2(0, 0, size.x, maxf(cut.position.y, 0)), SHADE, true)
	draw_rect(Rect2(0, cut.end.y, size.x, maxf(size.y - cut.end.y, 0)), SHADE, true)
	draw_rect(Rect2(0, cut.position.y, maxf(cut.position.x, 0), cut.size.y), SHADE, true)
	draw_rect(Rect2(cut.end.x, cut.position.y, maxf(size.x - cut.end.x, 0), cut.size.y), SHADE, true)
	if _current.has("hint"):
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color.TRANSPARENT
		ring.border_color = Color(Companies.CHANCE, 0.75 + 0.25 * sin(_time * TAU * 0.9))
		ring.set_border_width_all(int(UiTheme.px(3)))
		ring.set_corner_radius_all(int(UiTheme.px(18)))
		ring.anti_aliasing = true
		draw_style_box(ring, cut)


## Place the card clear of the spotlight: below the top bar when the target
## is in the lower half of the screen, else above the hand and bar.
## WHY: the card's height depends on how its text wraps at the card's width,
## which the layout only knows a frame later, so the final position is set
## after two frames while the card stays invisible.
func _place_card() -> void:
	var p := UiTheme.SCALE
	var w := (size.x if size.x > 0 else 720.0) - 28 * p
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(14 * p, 0)
	_panel.size = Vector2(w, 0)
	_panel.modulate.a = 0.0
	_placing += 1
	_finish_place(_placing)


func _finish_place(token: int) -> void:
	var p := UiTheme.SCALE
	var w := (size.x if size.x > 0 else 720.0) - 28 * p
	# WHY: a Control outside a container never shrinks on its own; once the
	# text has wrapped at the right width, setting the size to zero snaps it
	# to the new, smaller minimum.
	for i in 2:
		await get_tree().process_frame
		if token != _placing or not visible or _current.is_empty():
			return
		_panel.size = Vector2(w, 0)
	await get_tree().process_frame
	if token != _placing or not visible or _current.is_empty():
		return
	var cut := _cutout()
	var h := size.y if size.y > 0 else 1280.0
	# Only the supply sits high enough for the card to go under it; every
	# other target (Market, hand, your row) is cleared by a card at the top.
	var at_top := String(_current.get("spot", "full")) != "supply"
	var y: float
	if at_top:
		y = (56 + 8) * p if cut.size.x > 0 else (56 + 60) * p
	else:
		var bar_rect: Rect2 = targets.get("bar", Rect2(0, h - 240 * p, 0, 0))
		y = bar_rect.position.y - global_position.y - 4 * p - _panel.size.y
	_panel.position = Vector2(14 * p, maxf(y, 8 * p))
	_panel.pivot_offset = Vector2(_panel.size.x / 2.0, _panel.size.y)
	_panel.scale = Vector2(0.94, 0.94)
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.35)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.2)


func _on_skip() -> void:
	enabled = false
	_queue.clear()
	_showing = false
	_current = {}
	visible = false
	_forced = {}
	highlight_card_id = -1
	finished.emit()


func _on_got_it() -> void:
	_showing = false
	_current = {}
	visible = false
	_show_next()


func _show_next() -> void:
	if _showing or _queue.is_empty() or not enabled:
		return
	var item: Dictionary = _queue.pop_front()
	_showing = true
	_current = item
	_title.text = item["title"]
	_body.text = item["body"]
	var n := int(item.get("n", 1))
	_meta.text = "TUTORIAL · %d OF %d" % [mini(n, SLOTS), SLOTS]
	for i in _dots.get_child_count():
		var dot: PanelContainer = _dots.get_child(i)
		dot.add_theme_stylebox_override("panel", UiTheme.flat(Companies.CHANCE if i < n else Companies.PANEL, Companies.INK, 1.5 * UiTheme.SCALE, 3 * UiTheme.SCALE))
	var guided: bool = item.has("hint")
	_hint_row.visible = guided
	_hint_label.text = String(item.get("hint", ""))
	_buttons_row.visible = not guided
	visible = true
	_place_card()
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
	var item := {"id": id, "title": step["title"], "body": body, "spot": step.get("spot", "full"), "n": seen.size()}
	if step.has("hint"):
		var hint := String(step["hint"])
		if args.size() > 0:
			hint = hint.replace("{name}", str(args[0]))
		item["hint"] = hint
		item["action"] = _forced.duplicate()
	_queue.append(item)
	_show_next()


## A guided card stays up while its move is the one being asked for; once
## the view moves on (the move was made, or the turn ended) it goes away.
func _retire_stale_hint() -> void:
	if _showing and _current.has("hint") and _current.get("action", {}) != _forced:
		_showing = false
		_current = {}
		visible = false
		_show_next()


# ---------------------------------------------------------------------------
# Guided turns
# ---------------------------------------------------------------------------

## The coached action in wire form ({"type": "take_supply"},
## {"type": "take_market", "cardId": n}, {"type": "play_portfolio", "cardId": n}
## or {"type": "play_market", "cardId": n}), or {} when nothing is forced:
## guided phase over, tutorial skipped, or not the learner's turn.
func forced_action() -> Dictionary:
	return _forced.duplicate()


## True when the learner may send this action: anything while nothing is
## forced, otherwise only the forced action itself (same type and card).
func allows(action: Dictionary) -> bool:
	if _forced.is_empty():
		return true
	return String(action.get("type", "")) == String(_forced.get("type", "")) \
		and int(action.get("cardId", -1)) == int(_forced.get("cardId", -1))


## Records the view so forced_action(), allows() and highlight_card_id
## reflect it, without firing any step. on_view does this too; the table
## calls it before it builds the cards, because on_view runs after the render.
func track(view: Dictionary) -> void:
	_view = view
	_my_seat = int(view.get("you", -1)) if view.get("you") != null else -1
	if not enabled:
		_forced = {}
		highlight_card_id = -1
		return
	if _is_my_turn():
		# WHY: the server's turn counter advances once per seat turn, so a new
		# value while the learner is active means a new learner turn.
		var turn := int(view.get("turn", 0))
		if turn != _last_turn:
			_last_turn = turn
			_learner_turns += 1
	_forced = _compute_forced()
	highlight_card_id = int(_forced.get("cardId", -1))
	_retire_stale_hint()


func _is_my_turn() -> bool:
	return _my_seat >= 0 and int(_view.get("active", -1)) == _my_seat and String(_view.get("phase", "")) != "ended"


func _compute_forced() -> Dictionary:
	if not _is_my_turn() or _learner_turns < 1 or _learner_turns > GUIDED_TURNS:
		return {}
	var action: Dictionary = {}
	var phase := String(_view.get("phase", ""))
	if phase == "take":
		var rich := _richest_takeable()
		if not rich.is_empty() and int(rich.get("coins", 0)) > 0:
			action = Protocol.take_market(int(rich["card"]["id"]))
		else:
			action = Protocol.take_supply()
	elif phase == "play":
		if _learner_turns >= 2:
			var lone := _lone_card()
			if not lone.is_empty():
				action = Protocol.play_market(int(lone["id"]))
		if action.is_empty():
			var majority := _majority_card()
			if not majority.is_empty():
				action = Protocol.play_portfolio(int(majority["id"]))
	# WHY: never force what the server would reject; the learner would be stuck.
	if action.is_empty() or not _is_legal(action):
		return {}
	return action


func _is_legal(action: Dictionary) -> bool:
	for a in _view.get("legal", []):
		if String(a.get("type", "")) == String(action["type"]) and int(a.get("cardId", -1)) == int(action.get("cardId", -1)):
			return true
	return false


func _my_seat_state() -> Dictionary:
	var seats: Array = _view.get("seats", [])
	return seats[_my_seat] if _my_seat >= 0 and _my_seat < seats.size() else {}


## Shares of a company the learner holds in hand plus portfolio.
func _held(company: int) -> int:
	var me := _my_seat_state()
	var n := 0
	for c in me.get("hand", []):
		if int(c.get("company", -1)) == company:
			n += 1
	for c in me.get("portfolio", []):
		if int(c.get("company", -1)) == company:
			n += 1
	return n


## Takeable Market slot with the most coins (first one on a tie), or {}.
func _richest_takeable() -> Dictionary:
	var best: Dictionary = {}
	for slot in _view.get("market", []):
		var id := int(slot.get("card", {}).get("id", -1))
		if not _is_legal(Protocol.take_market(id)):
			continue
		if best.is_empty() or int(slot.get("coins", 0)) > int(best.get("coins", 0)):
			best = slot
	return best


## Hand card of the company the learner holds most of; tie -> the larger
## company by share count.
func _majority_card() -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for card in _my_seat_state().get("hand", []):
		var company := int(card.get("company", 0))
		var score := _held(company) * 100 + int(Companies.get_company(company)["shares"])
		if score > best_score:
			best_score = score
			best = card
	return best


## Hand card of a company the learner holds only one of, not the company
## taken this turn; tie -> the smaller company. {} when there is none.
func _lone_card() -> Dictionary:
	var took = _view.get("tookCompany")
	var took_company := int(took) if took != null else -1
	var best: Dictionary = {}
	for card in _my_seat_state().get("hand", []):
		var company := int(card.get("company", 0))
		if company == took_company or _held(company) != 1:
			continue
		if best.is_empty() or company < int(best.get("company", 0)):
			best = card
	return best


## Fires the guided step for the current forced action, naming the card.
func _fire_guided() -> void:
	if _forced.is_empty():
		return
	var type := String(_forced["type"])
	var card_id := int(_forced.get("cardId", -1))
	if _learner_turns == 1:
		if type == "take_supply":
			_fire("first_take")
		elif type == "play_portfolio":
			_fire("first_play", [_company_name_of_card(card_id)])
	elif _learner_turns == 2:
		if type == "take_market":
			var slot := _market_slot(card_id)
			_fire("second_take", [_company_name_of_card(card_id), int(slot.get("coins", 0))])
		elif type == "take_supply":
			_fire("second_take_draw")
		elif type == "play_market":
			_fire("second_play", [_company_name_of_card(card_id)])
		elif type == "play_portfolio":
			_fire("second_play_keep", [_company_name_of_card(card_id)])


func _market_slot(card_id: int) -> Dictionary:
	for slot in _view.get("market", []):
		if int(slot.get("card", {}).get("id", -1)) == card_id:
			return slot
	return {}


func _company_name_of_card(card_id: int) -> String:
	for card in _my_seat_state().get("hand", []):
		if int(card.get("id", -1)) == card_id:
			return Companies.name_of(int(card.get("company", 0)))
	var slot := _market_slot(card_id)
	if not slot.is_empty():
		return Companies.name_of(int(slot["card"].get("company", 0)))
	return "right"


# ---------------------------------------------------------------------------
# Reactive steps
# ---------------------------------------------------------------------------

## Called by the table with every view (after events have been animated).
func on_view(view: Dictionary) -> void:
	track(view)
	if not enabled:
		return
	var phase := String(view.get("phase", ""))
	var my_turn := _is_my_turn()
	var market: Array = view.get("market", [])
	var seats: Array = view.get("seats", [])

	_fire("welcome")
	if phase == "ended":
		_fire("dividend")
		return
	if not my_turn:
		return
	if phase == "take":
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
	# WHY: the guided card comes last so it is the one on screen when the
	# learner acts; the rule cards above give the reason for the move.
	_fire_guided()


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
