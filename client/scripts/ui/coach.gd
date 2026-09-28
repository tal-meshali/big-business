class_name Coach
extends Control
## Tutorial coach: watches views and events during a game against bots and
## explains each rule the first time it matters. Each step fires once, in
## priority order, as a modal card the learner dismisses with "Got it".
##
## The learner's first GUIDED_TURNS turns are guided: the coach picks one
## action per step (forced_action), the table enables only that action
## (allows) and pulses the card to tap (highlight_card_id).

signal step_shown(step_id: String)
signal finished

## Learner turns during which only the coached action is enabled.
const GUIDED_TURNS := 2

const STEPS := [
	{
		"id": "welcome",
		"title": "Welcome to Big Business",
		"body": "Six companies are up for grabs. Collect shares, and on dividend day whoever holds the most shares of a company gets paid by everyone else who holds that company. Most capital wins.\n\nYou play against two bots. Take your time: there is no timer in the tutorial. For your first two turns the coach picks the move; after that you are on your own.",
	},
	{
		"id": "first_take",
		"title": "Your turn: take a share",
		"body": "Every turn has two steps: take one share, then play one share.\n\nThe Market is empty right now, so there is nothing to take: press Draw from supply. Later, drawing costs 1 coin for every share sitting in the Market.",
	},
	{
		"id": "first_play",
		"title": "Now play a share",
		"body": "Tap a card in your hand. You can keep it in your portfolio (face up, it counts toward majorities) or sell it to the Market (anyone can take it later).\n\nStart with the company you hold most of. Keep the %s share: tap it, then Keep.",
	},
	{
		"id": "second_take",
		"title": "Your second turn: grab the coins",
		"body": "Taking from the Market is free, and the coins sitting on a share go to whoever takes it.\n\nTake the %s share and pocket its %d coins: tap it in the Market.",
	},
	{
		"id": "second_take_draw",
		"title": "Your second turn: take a share",
		"body": "No Market share carries coins yet, so there is nothing to pocket.\n\nDraw from the supply again: press Draw from supply.",
	},
	{
		"id": "second_play",
		"title": "Now sell a share",
		"body": "A lone share of a company you are not collecting only costs you on dividend day, so get it out of your hand. Selling puts it in the Market, where anyone can take it.\n\nSell the %s share: tap it, then Sell to Market. Remember: you can't sell the company you just took.",
	},
	{
		"id": "second_play_keep",
		"title": "Keep building",
		"body": "Selling a share to the Market gets a lone company out of your hand, but you can't sell the company you just took, and every other card you hold is one you are collecting.\n\nKeep the %s share: tap it, then Keep.",
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
## Card the table should pulse while an action is forced; -1 when none.
var highlight_card_id := -1
var _queue: Array = []
var _showing := false
var _panel: PanelContainer
var _title: Label
var _body: Label
var _got_it: Button
var _skip: Button
var _view: Dictionary = {}
var _my_seat := -1
## Number of the learner's own turns seen so far (1 during the first turn).
var _learner_turns := 0
var _last_turn := -1
## The coached action in wire form, or {} when nothing is forced.
var _forced: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.4)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(center)
	var deed := UiTheme.deed_panel(Companies.CHANCE, "", Color.WHITE)
	_panel = deed["panel"]
	_panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(_panel)
	_title = deed["title"]
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	deed["body"].add_child(box)
	var tag := Label.new()
	tag.text = "TUTORIAL"
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Companies.INK_SOFT)
	box.add_child(tag)
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
	_forced = {}
	highlight_card_id = -1
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
