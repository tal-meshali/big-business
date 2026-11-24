class_name QuestsPanel
extends PanelContainer
## Quests overlay for the lobby: today's and this week's quests with progress
## bars and Claim buttons, the free cosmetic track, and a picker for the card
## back and table felt (only unlocked ones enabled), on two tabs (Quests,
## Looks) so neither needs scrolling on a phone. Built in code on a royal
## sheet with the night scheme's text roles, wells and meters; fed by the
## `get_profile` dictionary through `apply_profile`.

signal closed
## Emitted after a cosmetic is picked, once `Cosmetics` already reflects it.
signal cosmetic_changed(slot: String, id: String)

const HINTS := [
	"Quests reset at midnight UTC; weekly ones on Monday.",
	"Points from quests unlock new looks along the track.",
]
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
## Quests / Looks tabs and their two pages.
var tabs: TabStrip
var quests_page: VBoxContainer
var looks_page: VBoxContainer
var _scroll: ScrollContainer
var _status_is_hint := true


func _init() -> void:
	# The same royal sheet as the rules, so the overlays read as one family;
	# sheet, tabs and text all follow the screen's design-point scale.
	var k := UiTheme.dp_scale()
	add_theme_stylebox_override("panel", UiTheme.royal_sheet_style(k))
	theme = UiTheme.night_theme()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.dp(8))
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)
	# No title: the dock button and the tabs already say Quests; the
	# track line leads.
	# Track summary stays visible above the scrolling list.
	_track_label = UiTheme.body("", UiTheme.dp(UiTheme.TYPE_BODY))
	column.add_child(_track_label)
	_track_bar = UiTheme.meter(UiTheme.GOLD, UiTheme.dp(10))
	column.add_child(_track_bar)

	# Two pages instead of one long list: the quests, and the looks the
	# track unlocks. The status line stays under both.
	tabs = TabStrip.new()
	tabs.setup([{"label": "Quests"}, {"label": "Looks"}], k)
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
	quests_page.add_theme_constant_override("separation", UiTheme.dp(6))
	pages.add_child(quests_page)
	looks_page = VBoxContainer.new()
	looks_page.add_theme_constant_override("separation", UiTheme.dp(6))
	looks_page.visible = false
	pages.add_child(looks_page)
	_scroll = scroll

	quests_page.add_child(_heading("Today"))
	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override("separation", UiTheme.dp(6))
	quests_page.add_child(_daily_box)
	quests_page.add_child(_heading("This week"))
	_weekly_box = VBoxContainer.new()
	_weekly_box.add_theme_constant_override("separation", UiTheme.dp(6))
	quests_page.add_child(_weekly_box)

	looks_page.add_child(_heading("Card back"))
	var backs := HFlowContainer.new()
	backs.add_theme_constant_override("h_separation", UiTheme.dp(6))
	backs.add_theme_constant_override("v_separation", UiTheme.dp(6))
	looks_page.add_child(backs)
	for e in Cosmetics.CARD_BACKS:
		_back_buttons[e["id"]] = _make_pick_button(backs, "cardBack", e["id"])
	looks_page.add_child(_heading("Table felt"))
	var felts := HFlowContainer.new()
	felts.add_theme_constant_override("h_separation", UiTheme.dp(6))
	felts.add_theme_constant_override("v_separation", UiTheme.dp(6))
	looks_page.add_child(felts)
	for e in Cosmetics.TABLES:
		_table_buttons[e["id"]] = _make_pick_button(felts, "table", e["id"])

	# WHY outside the pages: this line also answers a tap on Claim, and at
	# the end of a scrolling list nobody saw it.
	_status = UiTheme.body("", UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT)
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

	var close := UiTheme.button("Close", UiTheme.dp(14), UiTheme.dp(44), "ghost")
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)
	_refresh_track()
	_refresh_picker()


## A section name, with air above it to part it from the section before.
func _heading(text: String) -> Control:
	var l := UiTheme.caption(text, UiTheme.dp(UiTheme.TYPE_CAPTION))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", UiTheme.dp(6))
	pad.add_child(l)
	return pad


func _make_pick_button(parent: Control, slot: String, id: String) -> Button:
	var b := UiTheme.button(Cosmetics.name_of(id), UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.dp(44))
	b.toggle_mode = true
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
		_status_is_hint = false
	else:
		_show_hint()
	_refresh_track()
	_refresh_picker()


## One quest in a well: what to do, how far along, and what it pays, with
## Claim on the right (mint once the quest is done).
func _add_row(parent: Control, q: Dictionary) -> void:
	var row := UiTheme.well()
	parent.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UiTheme.dp(10))
	row.add_child(line)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", UiTheme.dp(4))
	line.add_child(col)
	var label := UiTheme.label(String(q.get("text", "")), UiTheme.dp(UiTheme.TYPE_BODY), UiTheme.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(label)
	var bar := UiTheme.meter(UiTheme.MINT, UiTheme.dp(8))
	bar.max_value = maxf(1.0, float(q.get("target", 1)))
	bar.value = float(q.get("progress", 0))
	col.add_child(bar)
	var count := UiTheme.body("%d of %d  ·  +%d track points" % [int(q.get("progress", 0)), int(q.get("target", 1)), int(q.get("points", 0))], UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT)
	col.add_child(count)
	var button := UiTheme.button("Claim", UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.dp(44))
	button.custom_minimum_size.x = UiTheme.dp(84)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := String(q.get("id", ""))
	button.pressed.connect(func() -> void: _on_claim(id))
	line.add_child(button)
	var entry := {"id": id, "claimable": bool(q.get("claimable", false)), "claimed": bool(q.get("claimed", false)),
		"label": label, "bar": bar, "count": count, "button": button, "row": row}
	rows.append(entry)
	_refresh_row(entry)


func _refresh_row(entry: Dictionary) -> void:
	var button: Button = entry["button"]
	# Mint, the reward colour, only while there is something to collect.
	button.theme_type_variation = "GreenButton" if entry["claimable"] and not entry["claimed"] else ""
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
		_status_is_hint = false
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
		_status_is_hint = false


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
		_track_label.text = "%d track points. Every cosmetic unlocked!" % track_points if not track.is_empty() else "%d track points" % track_points
		_track_bar.min_value = 0
		_track_bar.max_value = maxf(1.0, float(track_points))
		_track_bar.value = track_points
		return
	_track_label.text = "%d track points. Next unlock: %s at %d." % [track_points, Cosmetics.name_of(String(next.get("cosmeticId", ""))), int(next.get("points", 0))]
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
	# The one in use is gold; a pressed violet button alone was hard to spot.
	b.theme_type_variation = "PrimaryButton" if id == current else ""
	var pts := _unlock_points(id)
	if is_unlocked or (pts == 0 and not Cosmetics.is_paid(id) and not Cosmetics.is_plus(id)):
		b.text = Cosmetics.name_of(id)
	elif Cosmetics.is_paid(id):
		b.text = "%s · shop" % Cosmetics.name_of(id)
	elif Cosmetics.is_plus(id):
		b.text = "%s · Plus" % Cosmetics.name_of(id)
	else:
		b.text = "%s · %d pts" % [Cosmetics.name_of(id), pts]


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
