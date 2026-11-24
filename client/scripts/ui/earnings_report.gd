class_name EarningsReport
extends MarginContainer
## The earnings report: what the game that just ended paid you. A night
## panel with a gold band (UiTheme.panel), shown after the Dividend day
## standings. It lists the XP line by line (capital first: XP follows the
## capital you ended with, decision D23), fills the level bar, and shows the
## season points, a look the game unlocked and the quest nearest to done.
##
## Fed by the server's receipt (OP_EARNINGS, EarningsMessage in
## server/src/match/protocol.ts). Every amount on it is the server's; the
## client only places the bar, with the level curve in Leveling.

signal play_again
signal leave

## A beat before the numbers move, so the eye is on them when they do.
const FILL_DELAY := 0.2
## The level bar: fill to the end of the old level, then into the new one.
const FILL_SECONDS := 0.55
const SPILL_SECONDS := 0.4
## The sheet's own entrance.
const ENTER_SECONDS := 0.2
## The level-up landing: the plate lights, the chip fades in, the badge pops.
const LIGHT_SECONDS := 0.15
const POP_SECONDS := 0.25
## The buttons take no press this long after the sheet appears. Play again
## sits where Continue was on the standings, and a double tap on Continue
## would otherwise start a new game before the report was seen.
const ARM_MS := 350
## At most this many quest lines; more finished quests fold into one line.
const MAX_QUEST_LINES := 2

## Set false to draw the final state at once (tests, screenshots).
var animate := true
var _content: VBoxContainer
var _again: Button
var _leave: Button
var _total: Label
var _level_title: Label
var _level_sub: Label
var _level_count: Label
var _level_badge: LevelBadge
var _level_box: StyleBoxFlat
var _level_chip: Control
var _bar: ProgressBar
## The bar's sequence, the total's count, the sheet's entrance and the
## level-up landing.
var _tween: Tween
var _count_tween: Tween
var _enter_tween: Tween
var _pop_tween: Tween
var _earnings: Dictionary = {}
## Time.get_ticks_msec() from which the buttons answer (ARM_MS).
var _armed_at := 0


## Builds the empty sheet. Call once, before the first show_report.
func setup() -> void:
	pivot_offset_ratio = Vector2(0.5, 0.5)
	var sheet := UiTheme.panel(UiTheme.GOLD, "Earnings report")
	var root: PanelContainer = sheet["panel"]
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root)
	var rows := VBoxContainer.new()
	# The actions stand a little further off than the groups do from each other.
	rows.add_theme_constant_override("separation", _px(16))
	sheet["body"].add_child(rows)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", _px(14))
	rows.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", _px(8))
	rows.add_child(buttons)
	_again = UiTheme.button("Play again", _px(15), _px(50), "primary")
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.pressed.connect(func() -> void:
		if _armed():
			play_again.emit())
	buttons.add_child(_again)
	_leave = UiTheme.button("Leave", _px(15), _px(50), "ghost")
	_leave.custom_minimum_size.x = _px(92)
	_leave.pressed.connect(func() -> void:
		if _armed():
			leave.emit())
	buttons.add_child(_leave)


## Draws the receipt `e` and, when `animate` is on, fills the level bar.
func show_report(e: Dictionary) -> void:
	_kill_tweens()
	_earnings = e
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	# What the game paid, then what it moved: two groups, a wider gap between.
	var paid := _group()
	paid.add_child(_headline(e))
	paid.add_child(_lines_well(e))
	if bool(e.get("botsOnly", false)):
		# On the wells' text edge, like every other line on the sheet.
		var note := MarginContainer.new()
		note.add_theme_constant_override("margin_left", _px(10))
		note.add_child(_text("Games with other people pay double.", UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT))
		paid.add_child(note)
	paid.add_child(_level_plate())
	var moved := _group()
	if int(e.get("seasonPoints", 0)) > 0:
		moved.add_child(_season_row(int(e.get("seasonPoints", 0))))
	var unlocked: Array = e.get("unlocked", [])
	if not unlocked.is_empty():
		moved.add_child(_unlock_row(unlocked))
	# One quest, the one the server lists first: the nearest thing to aim at.
	var open: Array = e.get("quests", [])
	if not open.is_empty():
		moved.add_child(_quest_row(open[0]))
	if moved.get_child_count() == 0:
		_content.remove_child(moved)
		moved.queue_free()
	visible = true
	_armed_at = Time.get_ticks_msec() + ARM_MS
	_again.grab_focus.call_deferred()
	_play_enter()
	_play_fill()


## Jumps any running motion to its end state. Safe before the first report.
func finish_motion() -> void:
	_kill_tweens()
	modulate.a = 1.0
	scale = Vector2.ONE
	if _earnings.is_empty():
		return
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


## A tap anywhere on the sheet skips the count-up. Not consumed, so a tap
## that lands on a button still presses it.
func _input(event: InputEvent) -> void:
	if _tween == null or not _tween.is_running() or not is_visible_in_tree():
		return
	var at := Vector2.INF
	if event is InputEventMouseButton and event.pressed:
		at = event.position
	elif event is InputEventScreenTouch and event.pressed:
		at = event.position
	if at != Vector2.INF and get_global_rect().has_point(at):
		finish_motion()


func _kill_tweens() -> void:
	for t in [_tween, _count_tween, _enter_tween, _pop_tween]:
		if t != null:
			t.kill()
	_tween = null
	_count_tween = null
	_enter_tween = null
	_pop_tween = null


## False for the first moments after the sheet appears (ARM_MS).
func _armed() -> bool:
	return Time.get_ticks_msec() >= _armed_at


## True when the report should move: off in tests, and where the device
## says it wants less motion.
func _moves() -> bool:
	# The call answers 1 for yes, 0 for no and -1 where the platform cannot
	# say. Not every platform can, which is why a tap also skips the motion.
	return animate and is_inside_tree() and DisplayServer.accessibility_should_reduce_animation() != 1


func _px(dp: float) -> int:
	return UiTheme.dp(dp)


## One line of text that keeps its width (UiTheme.body wraps, and a wrapping
## label in a row needs room handed to it).
func _text(text: String, dp: float, color: Color, display := false) -> Label:
	var l := UiTheme.label(text, _px(dp), color, display)
	if not display:
		l.add_theme_font_override("font", UiTheme.body_font())
	l.add_theme_constant_override("line_spacing", 0)
	return l


func _group() -> VBoxContainer:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", _px(8))
	_content.add_child(g)
	return g


func _row(sep := 10.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(sep))
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
	var h := _row(12)
	var medal := PlaceMedal.new()
	medal.rank = rank
	medal.custom_minimum_size = Vector2(_px(40), _px(40))
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(medal)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(1))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(col)
	col.add_child(_text("You won the game" if rank == 1 else "You finished %s" % ordinal(rank), UiTheme.TYPE_HEADING, Color.WHITE, true))
	col.add_child(_text("%d capital, %d players" % [int(e.get("capital", 0)), int(e.get("seats", 0))], UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT))
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


func _line_text(line: Dictionary, e: Dictionary) -> String:
	match String(line.get("kind", "")):
		"capital":
			var rate := float(e.get("rate", 0.0))
			var capital := int(e.get("capital", 0))
			# A whole rate reads as the sum it is; an odd one would not.
			if is_equal_approx(rate, roundf(rate)) and rate > 0.0:
				return "%d capital × %d XP" % [capital, int(roundf(rate))]
			return "%d capital" % capital
		"finish":
			return "Finished the game"
		"quest":
			if int(line.get("count", 1)) > 1:
				return "%d quests completed" % int(line.get("count", 1))
			return "Quest: %s" % String(line.get("text", ""))
	return ""


func _lines_well(e: Dictionary) -> Control:
	var well := UiTheme.well()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	well.add_child(col)
	var icons := {"capital": "coin", "finish": "check", "quest": "star"}
	for line in _lines(e):
		var h := _row(9)
		h.custom_minimum_size.y = _px(34)
		h.add_child(_icon(String(icons.get(String(line.get("kind", "")), "star")), 20))
		var what := _text(_line_text(line, e), UiTheme.TYPE_BODY, UiTheme.TEXT)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(what)
		h.add_child(_text("+%d" % int(line.get("xp", 0)), UiTheme.TYPE_BODY, Color.WHITE, true))
		col.add_child(h)
		var rule := ColorRect.new()
		rule.color = Color(UiTheme.LILAC, 0.16)
		rule.custom_minimum_size = Vector2(0, maxi(2, _px(1)))
		col.add_child(rule)
	var total := _row(9)
	total.custom_minimum_size.y = _px(42)
	var earned := _text("Earned", UiTheme.TYPE_HEADING, Color.WHITE, true)
	earned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(earned)
	# Gold, as the scores on the standings: this is the number to read.
	_total = UiTheme.title("", _px(UiTheme.TYPE_TITLE), UiTheme.GOLD)
	total.add_child(_total)
	col.add_child(total)
	return well


## The level and its bar. It starts as a plain well; _mark_level_up lights
## it, with a gold rim and a chip, at the moment the bar crosses over.
func _level_plate() -> Control:
	var plate := UiTheme.well()
	_level_box = plate.get_theme_stylebox("panel")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(8))
	plate.add_child(col)
	var h := _row(10)
	col.add_child(h)
	_level_badge = LevelBadge.new()
	_level_badge.font_px = _px(15)
	_level_badge.custom_minimum_size = Vector2(_px(38), _px(38))
	_level_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_level_badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", _px(1))
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(names)
	_level_title = _text("", UiTheme.TYPE_HEADING, Color.WHITE, true)
	names.add_child(_level_title)
	_level_sub = _text("", UiTheme.TYPE_BODY, UiTheme.TEXT)
	names.add_child(_level_sub)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", _px(3))
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(side)
	var chip := PanelContainer.new()
	var chip_box := UiTheme.ink_box(UiTheme.GOLD_PALE, _px(9), maxi(2, _px(1.2)))
	chip_box.content_margin_left = _px(7)
	chip_box.content_margin_right = _px(7)
	chip_box.content_margin_top = _px(1)
	chip_box.content_margin_bottom = _px(1)
	chip.add_theme_stylebox_override("panel", chip_box)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(UiTheme.caption("Level up", _px(UiTheme.TYPE_CAPTION), UiTheme.OUTLINE))
	# Hidden but keeping its place, so nothing jumps when it shows.
	chip.modulate.a = 0.0
	_level_chip = chip
	side.add_child(chip)
	_level_count = _text("", UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT)
	_level_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(_level_count)
	_bar = UiTheme.meter(UiTheme.MINT, _px(12))
	col.add_child(_bar)
	return plate


## The level-up look. With `pop` it lands: the plate lights and the chip
## fades in, the badge bounces and the phone buzzes once.
func _mark_level_up(pop: bool) -> void:
	var lit := Color(UiTheme.VIOLET, 0.55)
	# Lilac falls under 4.5:1 on the lit plate (UiTheme.standing_row).
	_level_count.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.85))
	if _pop_tween != null:
		_pop_tween.kill()
		_pop_tween = null
	if not pop:
		_level_box.bg_color = lit
		_level_box.border_color = UiTheme.GOLD
		_level_chip.modulate.a = 1.0
		_level_badge.pop = 1.0
		return
	Sfx.buzz(20)
	# WHY the badge's own `pop` and not its scale: the row is a container,
	# and a container puts a child's scale back to 1 every time it sorts,
	# which the changing numbers beside the badge make it do each frame.
	_level_badge.pop = 0.8
	_pop_tween = create_tween().set_parallel(true)
	_pop_tween.tween_property(_level_box, "bg_color", lit, LIGHT_SECONDS)
	_pop_tween.tween_property(_level_box, "border_color", UiTheme.GOLD, LIGHT_SECONDS)
	_pop_tween.tween_property(_level_chip, "modulate:a", 1.0, LIGHT_SECONDS)
	_pop_tween.tween_property(_level_badge, "pop", 1.0, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _season_row(points: int) -> Control:
	var well := UiTheme.well()
	var h := _row(10)
	well.add_child(h)
	h.add_child(_icon("trophy", 30, true))
	var what := _text("Season points", UiTheme.TYPE_BODY, UiTheme.TEXT)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(what)
	h.add_child(_text("+%d" % points, UiTheme.TYPE_HEADING, Color.WHITE, true))
	return well


func _unlock_row(ids: Array) -> Control:
	var names := PackedStringArray()
	for id in ids:
		names.append(Cosmetics.name_of(String(id)))
	var one := names.size() == 1
	var well := UiTheme.well()
	var h := _row(10)
	well.add_child(h)
	h.add_child(_icon("gift", 30, true))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	var what := _text("%s: %s" % ["New look" if one else "New looks", ", ".join(names)], UiTheme.TYPE_BODY, UiTheme.TEXT)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(what)
	col.add_child(_text("%s in Quests, on the Looks tab." % ("Choose it" if one else "Choose one"), UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT))
	return well


## A quest still open: its name, what it pays and how far it is.
func _quest_row(q: Dictionary) -> Control:
	var well := UiTheme.well()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _px(6))
	well.add_child(col)
	var h := _row(10)
	col.add_child(h)
	var what := _text(String(q.get("text", "")), UiTheme.TYPE_BODY, UiTheme.TEXT)
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(what)
	# The Quests screen's own wording, so the row is recognised there.
	var count := _text("%d of %d  ·  +%d XP" % [int(q.get("progress", 0)), int(q.get("target", 1)), int(q.get("xp", 0))], UiTheme.TYPE_LABEL, UiTheme.TEXT_SOFT)
	count.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(count)
	var bar := UiTheme.meter(UiTheme.MINT, _px(8))
	bar.max_value = maxf(1.0, float(q.get("target", 1)))
	bar.value = float(q.get("progress", 0))
	col.add_child(bar)
	return well


## The level plate at `xp` inside `level`: title, the count, the bar.
func _set_level(level: int, xp: int) -> void:
	var span := Leveling.span(level)
	_level_badge.level = level
	_level_badge.queue_redraw()
	_level_title.text = "Level %d" % level
	_level_count.text = "%s / %s" % [grouped(xp), grouped(span.y)]
	_bar.min_value = span.x
	_bar.max_value = span.y
	_bar.value = clampi(xp, span.x, span.y)


## What is left to the next level. Set at rest only (start, crossover,
## end): a sentence whose number ticked every frame would shiver.
func _set_left(level: int, xp: int) -> void:
	_level_sub.text = "%s XP to level %d" % [grouped(maxi(0, Leveling.span(level).y - xp)), level + 1]


func _show_final() -> void:
	var e := _earnings
	_total.text = "+%s XP" % grouped(int(e.get("xp", 0)))
	_set_level(int(e.get("levelAfter", 1)), int(e.get("xpAfter", 0)))
	_set_left(int(e.get("levelAfter", 1)), int(e.get("xpAfter", 0)))
	if int(e.get("levelAfter", 1)) > int(e.get("levelBefore", 1)):
		_mark_level_up(false)


## The sheet arrives: a short fade and a small settle, nothing more.
func _play_enter() -> void:
	modulate.a = 1.0
	scale = Vector2.ONE
	if not _moves():
		return
	modulate.a = 0.0
	_enter_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(self, "modulate:a", 1.0, ENTER_SECONDS)
	# WHY from(): the parent container sorts once as the sheet appears and
	# puts the scale back to 1, so a start value set by hand would be lost.
	_enter_tween.tween_property(self, "scale", Vector2.ONE, ENTER_SECONDS).from(Vector2(0.96, 0.96))


## The one authored moment: the XP counts up while the bar fills, and on a
## level-up the bar runs to the end, the plate lights up, and the bar starts
## again in the new level. The count and the bar run side by side on their
## own tweens, so the count lands with the bar whatever the bar has to do.
func _play_fill() -> void:
	var e := _earnings
	var before := int(e.get("xpBefore", 0))
	var after := int(e.get("xpAfter", 0))
	var level_from := int(e.get("levelBefore", 1))
	var level_to := int(e.get("levelAfter", 1))
	if not _moves() or after <= before:
		_show_final()
		return
	_total.text = "+0 XP"
	_set_level(level_from, before)
	var levelled := level_to > level_from
	# Without a level-up the line already says where this game leaves you.
	_set_left(level_from, before if levelled else after)
	var fill := func(xp: float, level: int) -> void: _set_level(level, int(roundf(xp)))
	_count_tween = create_tween()
	_count_tween.tween_interval(FILL_DELAY)
	_count_tween.tween_method(func(v: float) -> void: _total.text = "+%s XP" % grouped(int(roundf(v))), 0.0, float(after - before),
		FILL_SECONDS + (SPILL_SECONDS if levelled else 0.0)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween = create_tween()
	_tween.tween_interval(FILL_DELAY)
	if levelled:
		_tween.tween_method(fill.bind(level_from), float(before), float(Leveling.xp_for_level(level_from + 1)), FILL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_callback(func() -> void:
			_set_left(level_to, after)
			_mark_level_up(true))
		_tween.tween_method(fill.bind(level_to), float(Leveling.xp_for_level(level_to)), float(after), SPILL_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_method(fill.bind(level_from), float(before), float(after), FILL_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
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
		draw_style_box(UiTheme.ink_box(UiTheme.VIOLET, half * 0.5, maxf(2.0, half * 0.12)), Rect2(Vector2.ZERO, size))
		GameIcons.draw(self, kind, size / 2.0, half * 0.62)


## The finishing place on the standings' medal: gold, silver, bronze, then
## the sheet's own royal.
class PlaceMedal extends Control:
	var rank := 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var podium := rank >= 1 and rank <= 3
		var metal: Color = [UiTheme.GOLD, Color("#D5DBEA"), Color("#E0965A")][rank - 1] if podium else UiTheme.ROYAL_GLOW
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c + Vector2(0, r * 0.14), r, UiTheme.OUTLINE, true, -1.0, true)
		draw_circle(c, r, UiTheme.OUTLINE, true, -1.0, true)
		draw_circle(c, r - maxf(2.0, r * 0.16), metal, true, -1.0, true)
		var font := UiTheme.display_font()
		var text := str(rank)
		var px := int(r * (1.05 if rank < 10 else 0.8))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, c + Vector2(-w / 2.0, px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.OUTLINE if podium else UiTheme.TEXT)


## The level number on the violet diamond the lobby HUD uses.
class LevelBadge extends Control:
	var level := 1
	var font_px := 28
	## The drawing's scale about its centre, for the level-up bounce.
	var pop := 1.0:
		set(value):
			pop = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_set_transform(size / 2.0 * (1.0 - pop), 0.0, Vector2(pop, pop))
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var o := maxf(2.0, r * 0.12)
		var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		var inner := PackedVector2Array([c + Vector2(0, -r + o * 1.4), c + Vector2(r - o * 1.4, 0), c + Vector2(0, r - o * 1.4), c + Vector2(-r + o * 1.4, 0)])
		draw_colored_polygon(outer, UiTheme.OUTLINE)
		draw_colored_polygon(inner, UiTheme.VIOLET)
		# The lobby badge's two tones: the upper facet catches the light.
		draw_colored_polygon(PackedVector2Array([inner[3], inner[0], inner[1]]), UiTheme.VIOLET.lightened(0.14))
		var font := UiTheme.display_font()
		var text := str(level)
		var px := font_px if text.length() < 3 else int(font_px * 0.78)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var baseline := c.y + (font.get_ascent(px) - font.get_descent(px)) / 2.0
		draw_string(font, Vector2(c.x - w / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color.WHITE)
