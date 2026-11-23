class_name EarningsReport
extends PanelContainer
## The earnings report: what the game that just ended paid you. A night
## sheet with a gold band, shown after the Dividend day standings. It lists
## the XP line by line (capital first: XP follows the capital you ended
## with, decision D23), fills the level bar, and shows the season points,
## the quests the game moved and any look it unlocked.
##
## Fed by the server's receipt (OP_EARNINGS, EarningsMessage in
## server/src/match/protocol.ts). Nothing is computed here: the client only
## draws what the server paid.

signal play_again
signal leave

## The dark well rows sit in on the royal sheet.
const WELL := Color("#170F40")
## Hairline between two XP lines inside the well.
const RULE := Color("#2A1E66")
## Soft text on the brighter level-up plate, where lilac is too dim.
const SOFT_ON_GLOW := Color("#DAD4F7")
## The level bar: fill to the end of the old level, then into the new one.
const FILL_SECONDS := 0.55
const SPILL_SECONDS := 0.4
## At most this many XP lines; more finished quests fold into one line.
const MAX_QUEST_LINES := 2

## Px per design point (UiTheme.layout_scale).
var s := 1.85
## Set false to draw the final state at once (tests, screenshots).
var animate := true
var _content: VBoxContainer
var _again: Button
var _leave: Button
var _total: Label
var _level_title: Label
var _level_sub: Label
var _level_badge: LevelBadge
var _bar: XpBar
var _tween: Tween
var _earnings: Dictionary = {}


## Builds the empty sheet. Call once, before the first show_report.
func setup(px_per_dp: float) -> void:
	s = px_per_dp
	var face := StyleBoxFlat.new()
	face.bg_color = UiTheme.ROYAL
	face.border_color = UiTheme.OUTLINE
	face.set_border_width_all(_px(2))
	face.border_width_bottom = _px(5)
	face.set_corner_radius_all(_px(16))
	face.shadow_color = Color(0, 0, 0, 0.4)
	face.shadow_size = _px(12)
	face.shadow_offset = Vector2(0, _px(6))
	face.anti_aliasing = true
	add_theme_stylebox_override("panel", face)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	var band := PanelContainer.new()
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = UiTheme.GOLD
	band_style.corner_radius_top_left = _px(13)
	band_style.corner_radius_top_right = _px(13)
	band_style.border_color = UiTheme.OUTLINE
	band_style.border_width_bottom = _px(2)
	band_style.content_margin_top = _px(9)
	band_style.content_margin_bottom = _px(9)
	band_style.anti_aliasing = true
	band.add_theme_stylebox_override("panel", band_style)
	column.add_child(band)
	var title := UiTheme.outlined("Earnings report", _px(20))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(title)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", _px(12))
	body.add_theme_constant_override("margin_right", _px(12))
	body.add_theme_constant_override("margin_top", _px(12))
	body.add_theme_constant_override("margin_bottom", _px(13))
	column.add_child(body)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", _px(8))
	body.add_child(rows)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", _px(8))
	rows.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", _px(8))
	rows.add_child(buttons)
	_again = UiTheme.button("Play again", _px(15), _px(46), "primary")
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.pressed.connect(func() -> void: play_again.emit())
	buttons.add_child(_again)
	_leave = UiTheme.button("Leave", _px(15), _px(46), "ghost")
	_leave.custom_minimum_size.x = _px(92)
	_leave.pressed.connect(func() -> void: leave.emit())
	buttons.add_child(_leave)


## Draws the receipt `e` and, when `animate` is on, fills the level bar.
func show_report(e: Dictionary) -> void:
	_earnings = e
	if _tween != null:
		_tween.kill()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_content.add_child(_headline(e))
	_content.add_child(_lines_well(e))
	_content.add_child(_level_plate(e))
	if int(e.get("seasonPoints", 0)) > 0:
		_content.add_child(_season_row(int(e.get("seasonPoints", 0))))
	var unlocked: Array = e.get("unlocked", [])
	if not unlocked.is_empty():
		_content.add_child(_unlock_row(unlocked))
	# A long receipt keeps one "next quest" so the sheet still fits a phone.
	var open: Array = e.get("quests", [])
	var room := 1 if (not unlocked.is_empty() or _line_count(e) > 3) else 2
	for i in mini(room, open.size()):
		_content.add_child(_quest_row(open[i]))
	if bool(e.get("botsOnly", false)):
		var note := _text("Games against bots pay half.", 13, UiTheme.LILAC)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(note)
	visible = true
	_again.grab_focus.call_deferred()
	_play_fill()


## Jumps any running motion to its end state.
func finish_motion() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_show_final()


## 1250 as "1,250".
static func grouped(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## 1 as "1st", 2 as "2nd", 11 as "11th".
static func ordinal(n: int) -> String:
	var tail := "th"
	if (n % 100) < 11 or (n % 100) > 13:
		match n % 10:
			1:
				tail = "st"
			2:
				tail = "nd"
			3:
				tail = "rd"
	return "%d%s" % [n, tail]


## Total XP at which `level` starts (50 x (level - 1)^2, as on the server).
static func level_floor(level: int) -> int:
	return 50 * (level - 1) * (level - 1)


## How far `xp` is through `level`, 0 to 1.
static func level_fraction(xp: int, level: int) -> float:
	var from := level_floor(level)
	var to := level_floor(level + 1)
	return clampf(float(xp - from) / float(maxi(1, to - from)), 0.0, 1.0)


func _px(dp: float) -> int:
	return int(round(dp * s))


func _text(text: String, dp: float, color: Color, display := false) -> Label:
	var l := UiTheme.label(text, _px(dp), color, display)
	if not display:
		l.add_theme_font_override("font", UiTheme.body_font())
	return l


func _well(pad_x := 12.0, pad_y := 9.0, bg := WELL) -> PanelContainer:
	var p := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(_px(11))
	box.content_margin_left = _px(pad_x)
	box.content_margin_right = _px(pad_x)
	box.content_margin_top = _px(pad_y)
	box.content_margin_bottom = _px(pad_y)
	box.anti_aliasing = true
	p.add_theme_stylebox_override("panel", box)
	return p


func _row(sep := 10.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(sep))
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	return h


## `tile` sets the icon on a small glossy plate: the lobby's trophy and gift
## are drawn with ink outlines, which the dark well would swallow.
func _icon(kind: String, dp: float, tile := false) -> ReportIcon:
	var icon := ReportIcon.new()
	icon.kind = kind
	icon.tile = tile
	icon.custom_minimum_size = Vector2(_px(dp), _px(dp))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## The place medal and how the game went.
func _headline(e: Dictionary) -> Control:
	var rank := int(e.get("rank", 1))
	var seats := int(e.get("seats", 0))
	var capital := int(e.get("capital", 0))
	var h := _row(12)
	var medal := PlaceMedal.new()
	medal.rank = rank
	medal.font_px = _px(20)
	medal.custom_minimum_size = Vector2(_px(40), _px(40))
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(medal)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(1))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(_text("You won the game" if rank == 1 else "You finished %s" % ordinal(rank), 16, Color.WHITE, true))
	col.add_child(_text("%s of %d with %d capital" % [ordinal(rank), seats, capital], 13, UiTheme.LILAC))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", _px(4))
	pad.add_theme_constant_override("margin_right", _px(4))
	pad.add_child(h)
	return pad


## The XP lines as the server sent them, with more than MAX_QUEST_LINES
## finished quests folded into one.
func _lines(e: Dictionary) -> Array:
	var out: Array = []
	var quests: Array = []
	for line in e.get("lines", []):
		if String(line.get("kind", "")) == "quest":
			quests.append(line)
		else:
			out.append(line)
	if quests.size() <= MAX_QUEST_LINES:
		out.append_array(quests)
	else:
		var xp := 0
		for q in quests:
			xp += int(q.get("xp", 0))
		out.append({"kind": "quest", "xp": xp, "text": "", "count": quests.size()})
	return out


func _line_count(e: Dictionary) -> int:
	return _lines(e).size()


func _line_text(line: Dictionary, e: Dictionary) -> String:
	match String(line.get("kind", "")):
		"capital":
			var rate := float(e.get("rate", 0.0))
			var capital := int(e.get("capital", 0))
			# A whole rate reads as the sum it is; an odd one would not.
			if is_equal_approx(rate, roundf(rate)) and rate > 0.0:
				return "Capital %d × %d" % [capital, int(roundf(rate))]
			return "Capital %d" % capital
		"finish":
			return "Finished the game"
		"quest":
			if int(line.get("count", 1)) > 1:
				return "%d quests completed" % int(line.get("count", 1))
			return "Quest: %s" % String(line.get("text", ""))
	return ""


func _lines_well(e: Dictionary) -> Control:
	var well := _well(12, 3)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	well.add_child(col)
	var icons := {"capital": "coin", "finish": "check", "quest": "star"}
	for line in _lines(e):
		var h := _row(9)
		h.custom_minimum_size.y = _px(36)
		h.add_child(_icon(String(icons.get(String(line.get("kind", "")), "star")), 20))
		var what := _text(_line_text(line, e), 14, UiTheme.CREAM)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(what)
		var amount := _text("+%d" % int(line.get("xp", 0)), 15, Color.WHITE, true)
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(amount)
		col.add_child(h)
		var rule := ColorRect.new()
		rule.color = RULE
		rule.custom_minimum_size = Vector2(0, maxi(2, _px(1.2)))
		col.add_child(rule)
	var total := _row(9)
	total.custom_minimum_size.y = _px(44)
	var earned := _text("Earned", 16, Color.WHITE, true)
	earned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	earned.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total.add_child(earned)
	_total = UiTheme.outlined("", _px(20), UiTheme.GOLD)
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total.add_child(_total)
	col.add_child(total)
	return well


## The level and its bar; brighter, with a gold rim, when the game levelled you up.
func _level_plate(e: Dictionary) -> Control:
	var levelled := int(e.get("levelAfter", 1)) > int(e.get("levelBefore", 1))
	var plate := _well(12, 10, UiTheme.ROYAL_GLOW if levelled else WELL)
	if levelled:
		var box: StyleBoxFlat = plate.get_theme_stylebox("panel")
		box.border_color = UiTheme.GOLD
		box.set_border_width_all(_px(2))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(9))
	plate.add_child(col)
	var h := _row(12)
	col.add_child(h)
	_level_badge = LevelBadge.new()
	_level_badge.font_px = _px(15)
	_level_badge.custom_minimum_size = Vector2(_px(38), _px(38))
	_level_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_level_badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", _px(1))
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(names)
	_level_title = _text("", 16, Color.WHITE, true)
	names.add_child(_level_title)
	_level_sub = _text("", 13, SOFT_ON_GLOW if levelled else UiTheme.LILAC)
	names.add_child(_level_sub)
	if levelled:
		var chip := PanelContainer.new()
		var chip_box := StyleBoxFlat.new()
		chip_box.bg_color = UiTheme.GOLD_PALE
		chip_box.border_color = UiTheme.OUTLINE
		chip_box.set_border_width_all(_px(2))
		chip_box.set_corner_radius_all(_px(9))
		chip_box.content_margin_left = _px(7)
		chip_box.content_margin_right = _px(7)
		chip_box.content_margin_top = _px(1)
		chip_box.content_margin_bottom = _px(1)
		chip_box.anti_aliasing = true
		chip.add_theme_stylebox_override("panel", chip_box)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(UiTheme.label("LEVEL UP", _px(11), UiTheme.OUTLINE))
		h.add_child(chip)
	_bar = XpBar.new()
	_bar.font_px = _px(12)
	_bar.outline_px = _px(2)
	_bar.custom_minimum_size = Vector2(0, _px(16))
	col.add_child(_bar)
	return plate


func _season_row(points: int) -> Control:
	var well := _well()
	var h := _row(10)
	well.add_child(h)
	h.add_child(_icon("trophy", 30, true))
	var what := _text("Season points", 14, UiTheme.CREAM)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(what)
	h.add_child(_text("+%d" % points, 15, UiTheme.GOLD, true))
	return well


func _unlock_row(ids: Array) -> Control:
	var names := PackedStringArray()
	for id in ids:
		names.append(Cosmetics.name_of(String(id)))
	var well := _well()
	var h := _row(10)
	well.add_child(h)
	h.add_child(_icon("gift", 30, true))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(_text("New look: %s" % ", ".join(names), 14, UiTheme.CREAM))
	col.add_child(_text("Pick it in Quests, under Looks.", 13, UiTheme.LILAC))
	return well


## A quest still open, with how far it is.
func _quest_row(q: Dictionary) -> Control:
	var well := _well()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(6))
	well.add_child(col)
	var h := _row(10)
	col.add_child(h)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(names)
	var what := _text(String(q.get("text", "")), 14, UiTheme.CREAM)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(what)
	names.add_child(_text("%s quest, %d XP" % ["Weekly" if bool(q.get("weekly", false)) else "Daily", int(q.get("xp", 0))], 13, UiTheme.LILAC))
	var count := _text("%d / %d" % [int(q.get("progress", 0)), int(q.get("target", 1))], 14, Color.WHITE, true)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(count)
	var bar := XpBar.new()
	bar.fill = UiTheme.GOLD
	bar.fraction = clampf(float(q.get("progress", 0)) / maxf(1.0, float(q.get("target", 1))), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, _px(12))
	col.add_child(bar)
	return well


func _set_level(level: int, xp: int, fraction: float) -> void:
	_level_badge.level = level
	_level_badge.queue_redraw()
	_level_title.text = "Level %d" % level
	_bar.fraction = fraction
	_bar.text = "%s / %s" % [grouped(xp), grouped(level_floor(level + 1))]
	_bar.queue_redraw()


func _show_final() -> void:
	var e := _earnings
	var after := int(e.get("xpAfter", 0))
	var level := int(e.get("levelAfter", 1))
	_total.text = "+%s XP" % grouped(int(e.get("xp", 0)))
	_set_level(level, after, level_fraction(after, level))
	_level_sub.text = "%s XP to level %d" % [grouped(maxi(0, level_floor(level + 1) - after)), level + 1]


## The one authored moment: the XP counts up while the bar fills, and on a
## level-up the bar runs to the end, then starts again in the new level.
func _play_fill() -> void:
	var e := _earnings
	var before := int(e.get("xpBefore", 0))
	var after := int(e.get("xpAfter", 0))
	var level_from := int(e.get("levelBefore", 1))
	var level_to := int(e.get("levelAfter", 1))
	if not animate or not is_inside_tree() or after <= before:
		_show_final()
		return
	_show_final()
	_total.text = "+0 XP"
	_set_level(level_from, before, level_fraction(before, level_from))
	_tween = create_tween()
	_tween.tween_interval(0.2)
	var count := func(v: float) -> void: _total.text = "+%s XP" % grouped(int(roundf(v)))
	var fill := func(xp: float, level: int) -> void: _set_level(level, int(roundf(xp)), level_fraction(int(roundf(xp)), level))
	var gained := float(after - before)
	if level_to == level_from:
		_tween.tween_method(count, 0.0, gained, FILL_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_method(fill.bind(level_from), float(before), float(after), FILL_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		var edge := float(level_floor(level_from + 1))
		var start := float(level_floor(level_to))
		_tween.tween_method(count, 0.0, gained, FILL_SECONDS + SPILL_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_method(fill.bind(level_from), float(before), edge, FILL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(fill.bind(level_to), start, float(after), SPILL_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_show_final)


## A small GameIcons drawing, sized by its minimum size.
class ReportIcon extends Control:
	var kind := "star"
	var tile := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var half := minf(size.x, size.y) * 0.5
		if not tile:
			GameIcons.draw(self, kind, size / 2.0, half)
			return
		var plate := StyleBoxFlat.new()
		plate.bg_color = UiTheme.VIOLET
		plate.border_color = UiTheme.OUTLINE
		plate.set_border_width_all(maxi(2, int(half * 0.12)))
		plate.set_corner_radius_all(int(half * 0.5))
		plate.anti_aliasing = true
		draw_style_box(plate, Rect2(Vector2.ZERO, size))
		GameIcons.draw(self, kind, size / 2.0, half * 0.62)


## The finishing place on a glossy disc: gold for the winner, cream for the rest.
class PlaceMedal extends Control:
	var rank := 1
	var font_px := 36

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var o := maxf(2.0, r * 0.1)
		var face := UiTheme.GOLD if rank == 1 else UiTheme.CREAM
		var lip := UiTheme.GOLD_DEEP if rank == 1 else Color("#CFCBDA")
		draw_circle(c, r, UiTheme.OUTLINE, true, -1.0, true)
		draw_circle(c, r - o, lip, true, -1.0, true)
		draw_circle(c - Vector2(0, r * 0.12), r - o - r * 0.06, face, true, -1.0, true)
		var font := UiTheme.display_font()
		var text := str(rank)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		var baseline := c.y - r * 0.1 + (font.get_ascent(font_px) - font.get_descent(font_px)) / 2.0
		draw_string(font, Vector2(c.x - w / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, UiTheme.OUTLINE)


## The level number on the violet diamond the lobby HUD uses.
class LevelBadge extends Control:
	var level := 1
	var font_px := 28

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var o := maxf(2.0, r * 0.12)
		var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		var inner := PackedVector2Array([c + Vector2(0, -r + o * 1.4), c + Vector2(r - o * 1.4, 0), c + Vector2(0, r - o * 1.4), c + Vector2(-r + o * 1.4, 0)])
		draw_colored_polygon(outer, UiTheme.OUTLINE)
		draw_colored_polygon(inner, UiTheme.VIOLET)
		var font := UiTheme.display_font()
		var text := str(level)
		var px := font_px if text.length() < 3 else int(font_px * 0.78)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var baseline := c.y + (font.get_ascent(px) - font.get_descent(px)) / 2.0
		draw_string(font, Vector2(c.x - w / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)


## A night bar with an ink rim and a flat fill; optional centred text.
class XpBar extends Control:
	var fraction := 0.0
	var fill := UiTheme.MINT
	var text := ""
	var font_px := 22
	var outline_px := 4

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var radius := size.y / 2.0
		var rim := maxf(2.0, size.y * 0.14)
		var back := StyleBoxFlat.new()
		back.bg_color = Color("#0D0826")
		back.border_color = UiTheme.OUTLINE
		back.set_border_width_all(int(rim))
		back.set_corner_radius_all(int(radius))
		back.anti_aliasing = true
		draw_style_box(back, Rect2(Vector2.ZERO, size))
		var inner := Rect2(Vector2(rim, rim), size - Vector2(rim, rim) * 2.0)
		var w := inner.size.x * clampf(fraction, 0.0, 1.0)
		if w >= 1.0:
			var bar := StyleBoxFlat.new()
			bar.bg_color = fill
			bar.set_corner_radius_all(int(inner.size.y / 2.0))
			bar.anti_aliasing = true
			# A sliver still shows as a rounded pip, never a square corner.
			draw_style_box(bar, Rect2(inner.position, Vector2(maxf(w, minf(inner.size.y, inner.size.x)), inner.size.y)))
		if text.is_empty():
			return
		var font := UiTheme.ui_font()
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		var baseline := size.y / 2.0 + (font.get_ascent(font_px) - font.get_descent(font_px)) / 2.0
		var at := Vector2((size.x - tw) / 2.0, baseline)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, outline_px * 2, UiTheme.OUTLINE)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, Color.WHITE)
