class_name QuestsPanel
extends PanelContainer
## Quests overlay for the lobby: today's and this week's quests with progress
## bars and Claim buttons, the free cosmetic track, and a picker for the card
## back and table felt (only unlocked ones enabled). Built in code on a deed
## panel; fed by the `get_profile` dictionary through `apply_profile`.

signal closed
## Emitted after a cosmetic is picked, once `Cosmetics` already reflects it.
signal cosmetic_changed(slot: String, id: String)

const ROW_HEIGHT := 48.0

## One entry per quest row: {id, claimable, claimed, label, bar, count, button}.
var rows: Array[Dictionary] = []
var track_points := 0
var unlocked: Array = []
var track: Array = []
var _daily_box: VBoxContainer
var _weekly_box: VBoxContainer
var _track_label: Label
var _track_bar: ProgressBar
var _back_buttons: Dictionary = {}
var _table_buttons: Dictionary = {}
var _status: Label


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.deed_panel(Companies.CHANCE, "Quests", Color.WHITE)
	deed["title"].add_theme_font_size_override("font_size", 28)
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var body: MarginContainer = deed["body"]
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(column)

	# Track summary stays visible above the scrolling list.
	_track_label = Label.new()
	_track_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_track_label.add_theme_font_size_override("font_size", 19)
	column.add_child(_track_label)
	_track_bar = _make_bar(Companies.CHANCE)
	column.add_child(_track_bar)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	content.add_child(_heading("Today"))
	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override("separation", 6)
	content.add_child(_daily_box)
	content.add_child(_heading("This week"))
	_weekly_box = VBoxContainer.new()
	_weekly_box.add_theme_constant_override("separation", 6)
	content.add_child(_weekly_box)

	content.add_child(_heading("Card back"))
	var backs := HFlowContainer.new()
	backs.add_theme_constant_override("h_separation", 8)
	backs.add_theme_constant_override("v_separation", 8)
	content.add_child(backs)
	for e in Cosmetics.CARD_BACKS:
		_back_buttons[e["id"]] = _make_pick_button(backs, "cardBack", e["id"])
	content.add_child(_heading("Table felt"))
	var felts := HFlowContainer.new()
	felts.add_theme_constant_override("h_separation", 8)
	felts.add_theme_constant_override("v_separation", 8)
	content.add_child(felts)
	for e in Cosmetics.TABLES:
		_table_buttons[e["id"]] = _make_pick_button(felts, "table", e["id"])

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 17)
	_status.text = "Quests reset at midnight UTC; weekly ones on Monday."
	content.add_child(_status)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)
	_refresh_track()
	_refresh_picker()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Companies.INK_SOFT)
	return l


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#E8E8E8")
	back.border_color = Companies.INK
	back.set_border_width_all(1)
	back.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _make_pick_button(parent: Control, slot: String, id: String) -> Button:
	var b := Button.new()
	b.text = Cosmetics.name_of(id)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(150, ROW_HEIGHT)
	b.pressed.connect(func() -> void: _on_pick(slot, id))
	parent.add_child(b)
	return b


## Feeds the whole `get_profile` result (or any dictionary with the same keys).
func apply_profile(data: Dictionary) -> void:
	track_points = int(data.get("trackPoints", 0))
	unlocked = data.get("unlocked", [Cosmetics.DEFAULT_CARD_BACK, Cosmetics.DEFAULT_TABLE])
	track = data.get("track", [])
	Cosmetics.apply_equipped(data.get("equipped", {}))
	var quests: Dictionary = data.get("quests", {})
	for r in rows:
		r["row"].queue_free()
	rows.clear()
	for q in quests.get("daily", []):
		_add_row(_daily_box, q)
	for q in quests.get("weekly", []):
		_add_row(_weekly_box, q)
	if rows.is_empty():
		_status.text = "No quests loaded yet. Connect to see today's quests."
	_refresh_track()
	_refresh_picker()


func _add_row(parent: Control, q: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var label := Label.new()
	label.text = "%s  (+%d pts)" % [String(q.get("text", "")), int(q.get("points", 0))]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	col.add_child(label)
	var bar := _make_bar(Companies.GOLD)
	bar.max_value = maxf(1.0, float(q.get("target", 1)))
	bar.value = float(q.get("progress", 0))
	col.add_child(bar)
	var count := Label.new()
	count.text = "%d / %d" % [int(q.get("progress", 0)), int(q.get("target", 1))]
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", Companies.INK_SOFT)
	col.add_child(count)
	var button := Button.new()
	button.custom_minimum_size = Vector2(104, ROW_HEIGHT)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := String(q.get("id", ""))
	button.pressed.connect(func() -> void: _on_claim(id))
	row.add_child(button)
	var entry := {"id": id, "claimable": bool(q.get("claimable", false)), "claimed": bool(q.get("claimed", false)),
		"label": label, "bar": bar, "count": count, "button": button, "row": row}
	rows.append(entry)
	_refresh_row(entry)


func _refresh_row(entry: Dictionary) -> void:
	var button: Button = entry["button"]
	if entry["claimed"]:
		button.text = "Claimed"
		button.disabled = true
	elif entry["claimable"]:
		button.text = "Claim"
		button.disabled = false
	else:
		button.text = "Claim"
		button.disabled = true


func _on_claim(id: String) -> void:
	var entry := _row_by_id(id)
	if entry.is_empty() or not entry["claimable"] or entry["claimed"]:
		return
	entry["button"].disabled = true
	var res: Dictionary = await Net.claim_quest(id)
	if res.is_empty() or not res.get("ok", false):
		entry["button"].disabled = false
		_status.text = "Could not claim right now. Try again in a moment."
		return
	_apply_claim(id, int(res.get("trackPoints", track_points)), res.get("unlocked", unlocked))


## Marks a row claimed and updates the track from the server's answer.
func _apply_claim(id: String, new_points: int, new_unlocked: Array) -> void:
	var entry := _row_by_id(id)
	if not entry.is_empty():
		entry["claimed"] = true
		entry["claimable"] = false
		_refresh_row(entry)
	var before := unlocked.size()
	track_points = new_points
	unlocked = new_unlocked
	_refresh_track()
	_refresh_picker()
	if unlocked.size() > before:
		_status.text = "Unlocked: %s" % Cosmetics.name_of(String(unlocked.back()))


func _row_by_id(id: String) -> Dictionary:
	for r in rows:
		if r["id"] == id:
			return r
	return {}


## Track summary: points so far and the next unlock.
func _refresh_track() -> void:
	var prev := 0
	var next: Dictionary = {}
	for step in track:
		if track_points < int(step.get("points", 0)):
			next = step
			break
		prev = int(step.get("points", 0))
	if next.is_empty():
		_track_label.text = "Track: %d points. Every cosmetic unlocked!" % track_points if not track.is_empty() else "Track: %d points" % track_points
		_track_bar.min_value = 0
		_track_bar.max_value = maxf(1.0, float(track_points))
		_track_bar.value = track_points
		return
	_track_label.text = "Track: %d points  •  next: %s at %d" % [track_points, Cosmetics.name_of(String(next.get("cosmeticId", ""))), int(next.get("points", 0))]
	_track_bar.min_value = prev
	_track_bar.max_value = int(next.get("points", 0))
	_track_bar.value = track_points


func _unlock_points(id: String) -> int:
	for step in track:
		if String(step.get("cosmeticId", "")) == id:
			return int(step.get("points", 0))
	return 0


## Picker buttons: locked items disabled and labelled with their threshold,
## the current selection shown pressed.
func _refresh_picker() -> void:
	for id in _back_buttons:
		_refresh_pick_button(_back_buttons[id], id, Cosmetics.card_back)
	for id in _table_buttons:
		_refresh_pick_button(_table_buttons[id], id, Cosmetics.table)


func _refresh_pick_button(b: Button, id: String, current: String) -> void:
	var is_unlocked := unlocked.has(id)
	b.disabled = not is_unlocked
	b.set_pressed_no_signal(id == current)
	var pts := _unlock_points(id)
	if is_unlocked or (pts == 0 and not Cosmetics.is_paid(id) and not Cosmetics.is_plus(id)):
		b.text = Cosmetics.name_of(id)
	elif Cosmetics.is_paid(id):
		b.text = "%s  (shop)" % Cosmetics.name_of(id)
	elif Cosmetics.is_plus(id):
		b.text = "%s  (Plus)" % Cosmetics.name_of(id)
	else:
		b.text = "%s  (%d pts)" % [Cosmetics.name_of(id), pts]


## Applies the pick locally first so the lobby and cards change at once,
## then tells the server; a refusal reverts to what the server has.
func _on_pick(slot: String, id: String) -> void:
	if not unlocked.has(id) or not Cosmetics.set_slot(slot, id):
		_refresh_picker()
		return
	_refresh_picker()
	cosmetic_changed.emit(slot, id)
	var res: Dictionary = await Net.equip_cosmetic(slot, id)
	if not res.is_empty() and not res.get("ok", false):
		Cosmetics.apply_equipped(res.get("equipped", {}))
		_refresh_picker()
		cosmetic_changed.emit(slot, Cosmetics.card_back if slot == "cardBack" else Cosmetics.table)
