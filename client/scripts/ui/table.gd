extends Control
## The game table. Renders a PlayerView from the server and sends intents.
## Layout is built in code for the spike; a designed scene replaces it later.

var view: Dictionary = {}
var _my_seat: int = -1
var _status: Label
var _market_row: HBoxContainer
var _hand_row: HBoxContainer
var _seats_box: VBoxContainer
var _supply_label: Label
var _draw_button: Button
var _leave_button: Button
var _play_mode: String = "portfolio"
var _mode_button: Button
var _result_label: Label
var _timer_label: Label


func _ready() -> void:
	_build_layout()
	Net.view_updated.connect(_on_view)
	Net.events_received.connect(_on_events)
	Net.server_error.connect(_on_error)
	set_process(true)


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Companies.TABLE_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 24
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_status = Label.new()
	_status.text = "Connecting..."
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 22)
	top.add_child(_status)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 22)
	top.add_child(_timer_label)
	_leave_button = Button.new()
	_leave_button.text = "Leave"
	_leave_button.pressed.connect(_on_leave)
	top.add_child(_leave_button)

	_seats_box = VBoxContainer.new()
	_seats_box.add_theme_constant_override("separation", 4)
	root.add_child(_seats_box)

	var market_title := Label.new()
	market_title.text = "The Market"
	market_title.add_theme_font_size_override("font_size", 18)
	root.add_child(market_title)

	var market_scroll := ScrollContainer.new()
	market_scroll.custom_minimum_size = Vector2(0, CardView.H + 16)
	market_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	market_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(market_scroll)
	_market_row = HBoxContainer.new()
	_market_row.add_theme_constant_override("separation", 8)
	market_scroll.add_child(_market_row)

	var supply_row := HBoxContainer.new()
	root.add_child(supply_row)
	_supply_label = Label.new()
	_supply_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supply_row.add_child(_supply_label)
	_draw_button = Button.new()
	_draw_button.text = "Draw from supply"
	_draw_button.custom_minimum_size = Vector2(0, 56)
	_draw_button.pressed.connect(func() -> void: Net.send_action(Protocol.take_supply()))
	supply_row.add_child(_draw_button)

	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.visible = false
	root.add_child(_result_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var hand_title_row := HBoxContainer.new()
	root.add_child(hand_title_row)
	var hand_title := Label.new()
	hand_title.text = "Your hand"
	hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_title.add_theme_font_size_override("font_size", 18)
	hand_title_row.add_child(hand_title)
	_mode_button = Button.new()
	_mode_button.custom_minimum_size = Vector2(0, 48)
	_mode_button.pressed.connect(_toggle_mode)
	hand_title_row.add_child(_mode_button)
	_update_mode_button()

	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 8)
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_hand_row)


func _toggle_mode() -> void:
	_play_mode = "market" if _play_mode == "portfolio" else "portfolio"
	_update_mode_button()
	_render()


func _update_mode_button() -> void:
	_mode_button.text = "Tap a card to: Keep" if _play_mode == "portfolio" else "Tap a card to: Sell to Market"


func _process(_delta: float) -> void:
	if view.is_empty() or _timer_label == null:
		return
	var deadline := float(view.get("deadline", 0))
	if deadline <= 0 or view.get("phase") == "ended":
		_timer_label.text = ""
		return
	var remaining := int(ceil((deadline - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	_timer_label.text = "%ds" % maxi(remaining, 0)


func _on_view(v: Dictionary) -> void:
	view = v
	_my_seat = int(v.get("you", -1)) if v.get("you") != null else -1
	_render()


func _on_events(_seq: int, events: Array) -> void:
	# Animation hooks go here. For the spike, only log big moments.
	for e in events:
		if e.get("type") == "game_ended":
			print("game ended")


func _on_error(message: String) -> void:
	_status.text = "Error: %s" % message


func _on_leave() -> void:
	await Net.leave_match()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _is_my_turn() -> bool:
	return _my_seat >= 0 and int(view.get("active", -1)) == _my_seat and view.get("phase") != "ended"


func _legal(type: String, card_id: int = -1) -> bool:
	for a in view.get("legal", []):
		if a.get("type") != type:
			continue
		if card_id < 0 or int(a.get("cardId", -1)) == card_id:
			return true
	return false


func _render() -> void:
	if view.is_empty():
		return
	var phase := String(view.get("phase", ""))
	var seats: Array = view.get("seats", [])
	var active := int(view.get("active", 0))

	# Status line.
	if phase == "ended":
		_status.text = "Dividend day!"
	elif _is_my_turn():
		_status.text = "Your turn: %s" % ("take a share" if phase == "take" else "play a share")
	else:
		var who: Dictionary = seats[active] if active < seats.size() else {}
		_status.text = "%s is %s" % [who.get("name", "?"), "taking" if phase == "take" else "playing"]

	# Seats.
	for child in _seats_box.get_children():
		child.queue_free()
	for i in seats.size():
		var s: Dictionary = seats[i]
		var line := Label.new()
		var counts := [0, 0, 0, 0, 0, 0]
		for c in s.get("portfolio", []):
			counts[int(c.get("company", 0))] += 1
		var pips := ""
		for c in 6:
			if counts[c] > 0:
				pips += " %s:%d" % [Companies.short_name_of(c), counts[c]]
		var tokens := ""
		for t in s.get("tokens", []):
			tokens += " [R:%s]" % Companies.short_name_of(int(t))
		var marker := "> " if i == active and phase != "ended" else "  "
		var you := " (you)" if i == _my_seat else ""
		var bot := " [bot]" if s.get("isBot", false) else ""
		var offline := "" if s.get("connected", true) or s.get("isBot", false) else " (away)"
		line.text = "%s%s%s%s%s  coins %d/%d  hand %d %s%s" % [
			marker, s.get("name", "?"), you, bot, offline,
			int(s.get("bronze", 0)), int(s.get("gold", 0)), int(s.get("handCount", 0)), pips, tokens]
		line.add_theme_font_size_override("font_size", 16)
		if i == active and phase != "ended":
			line.add_theme_color_override("font_color", Companies.GOLD)
		_seats_box.add_child(line)

	# Market.
	for child in _market_row.get_children():
		_market_row.remove_child(child)
		child.queue_free()
	for slot in view.get("market", []):
		var card: Dictionary = slot.get("card", {})
		var cv := CardView.new()
		cv.setup(int(card.get("id", -1)), int(card.get("company", 0)), int(slot.get("coins", 0)))
		cv.selectable = _is_my_turn() and phase == "take" and _legal("take_market", cv.card_id)
		cv.card_pressed.connect(func(id: int) -> void: Net.send_action(Protocol.take_market(id)))
		_market_row.add_child(cv)

	# Supply and draw button.
	var cost = view.get("drawCost")
	_supply_label.text = "Supply: %d shares" % int(view.get("supplyCount", 0))
	if cost != null:
		_supply_label.text += "   (draw costs %d)" % int(cost)
	_draw_button.disabled = not (_is_my_turn() and phase == "take" and _legal("take_supply"))
	_draw_button.visible = phase != "ended"
	_mode_button.visible = phase != "ended"

	# Hand.
	for child in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	if _my_seat >= 0 and _my_seat < seats.size():
		var me: Dictionary = seats[_my_seat]
		for card in me.get("hand", []):
			var cv := CardView.new()
			cv.setup(int(card.get("id", -1)), int(card.get("company", 0)))
			var action_type := "play_portfolio" if _play_mode == "portfolio" else "play_market"
			cv.selectable = _is_my_turn() and phase == "play" and _legal(action_type, cv.card_id)
			cv.card_pressed.connect(_on_hand_card_pressed)
			_hand_row.add_child(cv)

	# Result.
	var result = view.get("result")
	_result_label.visible = result != null
	if result != null:
		var lines := PackedStringArray()
		for sc in result.get("scores", []):
			var seat: Dictionary = seats[int(sc.get("seat", 0))]
			lines.append("#%d %s: %d  (bronze %d, gold %d)" % [int(sc.get("rank", 0)), seat.get("name", "?"), int(sc.get("score", 0)), int(sc.get("bronze", 0)), int(sc.get("gold", 0))])
		_result_label.text = "\n".join(lines)


func _on_hand_card_pressed(id: int) -> void:
	if _play_mode == "portfolio":
		Net.send_action(Protocol.play_portfolio(id))
	else:
		Net.send_action(Protocol.play_market(id))
