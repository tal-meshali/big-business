class_name QuestsPanel
extends PanelContainer
## Quests overlay for the lobby: today's and this week's quests with progress
## bars (a finished quest pays its XP when its game ends; the button only
## collects a leftover), the free cosmetic track, and a picker for the card
## back and table felt (only unlocked ones enabled), on two tabs (Quests,
## Looks) so neither needs scrolling on a phone. Built in code on a royal
## panel; fed by the `get_profile` dictionary through `apply_profile`.

signal closed
## Emitted after a cosmetic is picked, once `Cosmetics` already reflects it.
signal cosmetic_changed(slot: String, id: String)

const ROW_HEIGHT := 56.0
## Px per design point for the sheet and tabs.
## WHY fixed: this panel is laid out in canvas px on the 720-wide canvas
## (23 px text, 56 px rows); 1.35 matches the tabs to that text size.
const K := 1.35
const HINTS := [
	"A finished quest pays out when the game ends. New ones at midnight UTC; weekly on Monday.",
	"Every XP you earn moves the track toward the next look.",
]
## Text on the royal sheet.
const CREAM := Color("#FFF6DE")

## One entry per quest row: {id, claimable, claimed, label, bar, count, button}.
var rows: Array[Dictionary] = []
## XP counted toward the cosmetic track.
var track_xp := 0
var unlocked: Array = []
var track: Array = []
var _daily_box: VBoxContainer
var _weekly_box: VBoxContainer
var _track_label: Label
var _track_bar: ProgressBar
var _back_buttons: Dictionary = {}
var _table_buttons: Dictionary = {}
var _status: Label
## Quests / Looks tabs and their two pages.
var tabs: TabStrip
var quests_page: VBoxContainer
var looks_page: VBoxContainer
var _scroll: ScrollContainer
var _status_is_hint := true


func _init() -> void:
	# The same royal sheet as the rules, so the overlays read as one family.
	add_theme_stylebox_override("panel", UiTheme.royal_sheet_style(K))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)
	# No title: the dock button and the tabs already say Quests; the
	# track line leads.
	# Track summary stays visible above the scrolling list.
	_track_label = Label.new()
	_track_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_track_label.add_theme_font_size_override("font_size", 24)
	_track_label.add_theme_color_override("font_color", CREAM)
	column.add_child(_track_label)
	_track_bar = _make_bar(UiTheme.MINT)
	column.add_child(_track_bar)

	# Two pages instead of one long list: the quests, and the looks the
	# track unlocks. The status line stays under both.
	tabs = TabStrip.new()
	tabs.setup([{"label": "Quests"}, {"label": "Looks"}], K)
	tabs.tab_selected.connect(func(i: int) -> void: select_tab(i))
	column.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	quests_page = VBoxContainer.new()
	quests_page.add_theme_constant_override("separation", 8)
	pages.add_child(quests_page)
	looks_page = VBoxContainer.new()
	looks_page.add_theme_constant_override("separation", 8)
	looks_page.visible = false
	pages.add_child(looks_page)
	_scroll = scroll

	quests_page.add_child(_heading("Today"))
	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override("separation", 6)
	quests_page.add_child(_daily_box)
	quests_page.add_child(_heading("This week"))
	_weekly_box = VBoxContainer.new()
	_weekly_box.add_theme_constant_override("separation", 6)
	quests_page.add_child(_weekly_box)

	looks_page.add_child(_heading("Card back"))
	var backs := HFlowContainer.new()
	backs.add_theme_constant_override("h_separation", 8)
	backs.add_theme_constant_override("v_separation", 8)
	looks_page.add_child(backs)
	for e in Cosmetics.CARD_BACKS:
		_back_buttons[e["id"]] = _make_pick_button(backs, "cardBack", e["id"])
	looks_page.add_child(_heading("Table felt"))
	var felts := HFlowContainer.new()
	felts.add_theme_constant_override("h_separation", 8)
	felts.add_theme_constant_override("v_separation", 8)
	looks_page.add_child(felts)
	for e in Cosmetics.TABLES:
		_table_buttons[e["id"]] = _make_pick_button(felts, "table", e["id"])

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_color", UiTheme.LILAC)
	column.add_child(_status)
	_show_hint()
	# Opening from the dock always starts on the quests, where the badge
	# points; the pill is already there when the sheet appears.
	# A message from last time (an unlock) gives way to the hint again.
	visibility_changed.connect(func() -> void:
		if is_inside_tree():
			# WHY: Android back closes the sheet instead of quitting the app.
			get_tree().quit_on_go_back = not visible
		if visible:
			_status_is_hint = true
			select_tab(0, false))

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	close.theme_type_variation = "GhostButton"
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)
	_refresh_track()
	_refresh_picker()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", UiTheme.LILAC)
	return l


func _make_bar(fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = UiTheme.NIGHT
	back.border_color = UiTheme.OUTLINE
	back.set_border_width_all(2)
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


## The phone's back gesture or button closes the sheet.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		visible = false
		closed.emit()


## Shows the Quests (0) or Looks (1) page and moves the tab pill there.
func select_tab(i: int, animate := true) -> void:
	if tabs.current != i or not animate:
		tabs.select(i, animate and is_inside_tree())
	quests_page.visible = i == 0
	looks_page.visible = i == 1
	_scroll.scroll_vertical = 0
	if _status_is_hint:
		_show_hint()


## The status line's resting text, for the page on show. Messages (an
## unlock, an error) replace it until the next profile load.
func _show_hint() -> void:
	_status.text = HINTS[1 if looks_page.visible else 0]
	_status_is_hint = true


## Feeds the whole `get_profile` result (or any dictionary with the same keys).
func apply_profile(data: Dictionary) -> void:
	track_xp = int(data.get("trackXp", 0))
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
		_status_is_hint = false
	else:
		_show_hint()
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
	label.text = "%s  (+%d XP)" % [String(q.get("text", "")), int(q.get("xp", 0))]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", CREAM)
	col.add_child(label)
	var bar := _make_bar(UiTheme.GOLD)
	bar.max_value = maxf(1.0, float(q.get("target", 1)))
	bar.value = float(q.get("progress", 0))
	col.add_child(bar)
	var count := Label.new()
	count.text = "%d / %d" % [int(q.get("progress", 0)), int(q.get("target", 1))]
	count.add_theme_font_size_override("font_size", 17)
	count.add_theme_color_override("font_color", UiTheme.LILAC)
	col.add_child(count)
	var button := Button.new()
	# Wide enough for "Collected", so every row's bar is the same length.
	button.custom_minimum_size = Vector2(160, ROW_HEIGHT)
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
	button.theme_type_variation = ""
	if entry["claimed"]:
		button.text = "Collected"
		button.disabled = true
	elif entry["claimable"]:
		# WHY still a button: quests are collected when a game ends, but one
		# finished before that existed (or whose game end failed) waits here.
		button.text = "Collect"
		button.disabled = false
		# Mint for rewards: a quest ready to collect stands out from the rest.
		button.theme_type_variation = "GreenButton"
	else:
		button.text = "Collect"
		button.disabled = true


func _on_claim(id: String) -> void:
	var entry := _row_by_id(id)
	if entry.is_empty() or not entry["claimable"] or entry["claimed"]:
		return
	entry["button"].disabled = true
	var res: Dictionary = await Net.claim_quest(id)
	if res.is_empty() or not res.get("ok", false):
		entry["button"].disabled = false
		_status.text = "Could not collect right now. Try again in a moment."
		_status_is_hint = false
		return
	_apply_claim(id, int(res.get("trackXp", track_xp)), res.get("unlocked", unlocked))


## Marks a row claimed and updates the track from the server's answer.
func _apply_claim(id: String, new_track_xp: int, new_unlocked: Array) -> void:
	var entry := _row_by_id(id)
	if not entry.is_empty():
		entry["claimed"] = true
		entry["claimable"] = false
		_refresh_row(entry)
	var before := unlocked.size()
	track_xp = new_track_xp
	unlocked = new_unlocked
	_refresh_track()
	_refresh_picker()
	if unlocked.size() > before:
		_status.text = "Unlocked: %s" % Cosmetics.name_of(String(unlocked.back()))
		_status_is_hint = false


func _row_by_id(id: String) -> Dictionary:
	for r in rows:
		if r["id"] == id:
			return r
	return {}


## Track summary: XP so far and the next unlock.
func _refresh_track() -> void:
	var prev := 0
	var next: Dictionary = {}
	for step in track:
		if track_xp < int(step.get("xp", 0)):
			next = step
			break
		prev = int(step.get("xp", 0))
	if next.is_empty():
		_track_label.text = "Track: %s XP. Every look unlocked!" % EarningsReport.grouped(track_xp) if not track.is_empty() else "Track: %s XP" % EarningsReport.grouped(track_xp)
		_track_bar.min_value = 0
		_track_bar.max_value = maxf(1.0, float(track_xp))
		_track_bar.value = track_xp
		return
	_track_label.text = "Track: %s XP  •  next: %s at %s" % [EarningsReport.grouped(track_xp), Cosmetics.name_of(String(next.get("cosmeticId", ""))), EarningsReport.grouped(int(next.get("xp", 0)))]
	_track_bar.min_value = prev
	_track_bar.max_value = int(next.get("xp", 0))
	_track_bar.value = track_xp


func _unlock_xp(id: String) -> int:
	for step in track:
		if String(step.get("cosmeticId", "")) == id:
			return int(step.get("xp", 0))
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
	# The look in use is gold, so it stands apart from the other unlocked ones.
	b.theme_type_variation = "PrimaryButton" if id == current else ""
	var at := _unlock_xp(id)
	if is_unlocked or (at == 0 and not Cosmetics.is_paid(id) and not Cosmetics.is_plus(id)):
		b.text = Cosmetics.name_of(id)
	elif Cosmetics.is_paid(id):
		b.text = "%s  (shop)" % Cosmetics.name_of(id)
	elif Cosmetics.is_plus(id):
		b.text = "%s  (Plus)" % Cosmetics.name_of(id)
	else:
		b.text = "%s  (%s XP)" % [Cosmetics.name_of(id), EarningsReport.grouped(at)]


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
