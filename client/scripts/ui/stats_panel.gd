class_name StatsPanel
extends PanelContainer
## Lifetime stats from `get_stats`. Everyone sees games and wins; Plus
## members see the full breakdown (win rate, average and best capital,
## podiums, games with people, majorities by company and recent form).
## Opened from the shop.

signal closed

var _body: Label


func _init() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var deed := UiTheme.panel(UiTheme.VIOLET, "Your stats")
	deed["panel"].size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(deed["panel"])
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.dp(12))
	deed["body"].add_child(column)
	_body = UiTheme.body("", UiTheme.dp(UiTheme.TYPE_BODY))
	_body.add_theme_constant_override("line_spacing", UiTheme.dp(6))
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	var close := UiTheme.button("Close", UiTheme.dp(UiTheme.TYPE_LABEL), UiTheme.dp(44), "ghost")
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	column.add_child(close)


func open() -> void:
	visible = true
	_body.text = "Loading..."
	var data: Dictionary = await DesignerApi.stats()
	_body.text = "Connect to see your stats." if data.is_empty() else describe(data)


## The stats as text: a short line without Plus, the breakdown with it.
static func describe(data: Dictionary) -> String:
	var games := int(data.get("games", 0))
	var wins := int(data.get("wins", 0))
	if not data.get("plus", false):
		return "%d games, %d wins.\n\nPlus shows your win rate, average and best capital, which companies you corner most, and your recent form." % [games, wins]
	if games == 0:
		return "No games yet. Your stats start with your next game."
	var lines: Array[String] = []
	lines.append("%d games, %d wins (%s%%)" % [games, wins, str(data.get("winRate", 0))])
	lines.append("Average capital %s, best %d" % [str(data.get("averageScore", 0)), int(data.get("bestScore", 0))])
	lines.append("Top three finishes: %d" % int(data.get("podiums", 0)))
	lines.append("Games with other people: %d" % int(data.get("peopleGames", 0)))
	var maj: Array = data.get("majorities", [])
	var parts: Array[String] = []
	for c in mini(6, maj.size()):
		if int(maj[c]) > 0:
			parts.append("%s %d" % [Companies.short_name_of(c), int(maj[c])])
	lines.append("Majorities: " + (", ".join(parts) if not parts.is_empty() else "none yet"))
	var form: Array[String] = []
	for g in data.get("recent", []).slice(0, 10):
		form.append("#%d" % int(g.get("rank", 0)))
	if not form.is_empty():
		lines.append("Recent places: " + " ".join(form))
	return "\n".join(lines)
