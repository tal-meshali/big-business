class_name StatsPanel
extends PanelContainer
## Lifetime stats from `get_stats`. Everyone sees games and wins; Plus
## members see the full breakdown (win rate, average and best capital,
## podiums, games with people, majorities by company and recent form).
## Opened from the shop.

signal closed

## Loading, the empty state, or what Plus adds.
var _body: Label
var _rows: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.panel(UiTheme.VIOLET, "Your stats")
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.dp(8))
	deed["body"].add_child(column)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", UiTheme.dp(8))
	scroll.add_child(content)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", UiTheme.dp(6))
	content.add_child(_rows)
	_body = UiTheme.body("", UiTheme.dp(UiTheme.TYPE_BODY), UiTheme.TEXT_SOFT)
	content.add_child(_body)
	var close := UiTheme.button("Close", UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.dp(44), "ghost")
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)


func open() -> void:
	visible = true
	apply({})
	_body.text = "Loading…"
	var data: Dictionary = await DesignerApi.stats()
	apply(data)


## Shows a `get_stats` answer ({} while offline): one row per figure, the
## name on the left and the number in gold on the right, then majorities
## as one coloured count per company.
func apply(data: Dictionary) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_body.text = "Connect to see your stats." if data.is_empty() else note(data)
	_body.visible = not _body.text.is_empty()
	for fact in facts(data):
		var row := UiTheme.well()
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", UiTheme.dp(8))
		row.add_child(line)
		var name_label := UiTheme.body(fact[0], UiTheme.dp(UiTheme.TYPE_BODY))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value := UiTheme.title(fact[1], UiTheme.dp(UiTheme.TYPE_HEADING), UiTheme.GOLD)
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(value)
		_rows.add_child(row)
	var maj: Array = data.get("majorities", [])
	if not data.get("plus", false) or int(data.get("games", 0)) == 0 or maj.is_empty():
		return
	var row := UiTheme.well()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.dp(6))
	row.add_child(col)
	col.add_child(UiTheme.body("Majorities won", UiTheme.dp(UiTheme.TYPE_BODY)))
	var counts := HFlowContainer.new()
	counts.add_theme_constant_override("h_separation", UiTheme.dp(12))
	counts.add_theme_constant_override("v_separation", UiTheme.dp(4))
	col.add_child(counts)
	for c in mini(6, maj.size()):
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", UiTheme.dp(4))
		var dot := TextureRect.new()
		dot.texture = UiTheme.dot_icon(Companies.color_of(c), UiTheme.dp(12))
		dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		item.add_child(dot)
		item.add_child(UiTheme.label(Companies.short_name_of(c), UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.TEXT_SOFT))
		item.add_child(UiTheme.title(str(int(maj[c])), UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.GOLD))
		counts.add_child(item)
	_rows.add_child(row)


## The figures to list, as [name, value] pairs: games and wins for
## everyone, the breakdown with Plus.
static func facts(data: Dictionary) -> Array:
	if data.is_empty():
		return []
	var games := int(data.get("games", 0))
	var out := [["Games", str(games)], ["Wins", str(int(data.get("wins", 0)))]]
	if not data.get("plus", false) or games == 0:
		return out
	out.append(["Win rate", "%s%%" % str(data.get("winRate", 0))])
	out.append(["Average capital", str(data.get("averageScore", 0))])
	out.append(["Best capital", str(int(data.get("bestScore", 0)))])
	out.append(["Top three finishes", str(int(data.get("podiums", 0)))])
	out.append(["Games with other people", str(int(data.get("peopleGames", 0)))])
	var form := PackedStringArray()
	for g in data.get("recent", []).slice(0, 10):
		form.append(str(int(g.get("rank", 0))))
	if not form.is_empty():
		out.append(["Recent places", " · ".join(form)])
	return out


## The sentence under the figures: what Plus adds, or the empty state.
static func note(data: Dictionary) -> String:
	if not data.get("plus", false):
		return "Plus shows your win rate, average and best capital, which companies you corner most, and your recent form."
	if int(data.get("games", 0)) == 0:
		return "No games yet. Your stats start with your next game."
	return ""
