class_name SeatView
extends Control
## One player at the table. Opponents get a white plate (avatar, name and
## bot tag, capital, then one coloured pip per company held, with a gold
## regulator seal); the local player gets a flat strip in the bottom bar.
## The seat whose turn it is lifts and glows yellow, with a timer arc
## around the avatar.

signal seat_pressed(seat_index: int, at: Vector2)

## Fallback size in px, before the table sizes the seat.
const W := 220.0
const H := 104.0
## Design points between the capital and gold pills.
const PILL_GAP := 6.0
## Avatar fills, by seat order from the local player.
const AVATARS := [Color("#FFD98A"), Color("#9ED9B5"), Color("#A9C5F5"), Color("#F5B8A0"), Color("#D9C2F0"), Color("#F7C6D9"), Color("#BFE3F0")]

var seat_index: int = -1
var data: Dictionary = {}
var is_active: bool = false
var is_me: bool = false
var deadline_ms: float = 0.0
var step_ms: float = 0.0
## Design points to px.
var s: float = 1.85
## True for the local player's strip in the bottom bar.
var strip := false
## Wide plates (one or two opponents) spell out "capital".
var wide := false
var avatar_color := AVATARS[1]
## Capital pop: 0 to 1 per coin kind while a count that just changed
## ticks (swells and flashes gold). One "+3"/"-2" per kind shows right
## after its pill where there is room, holds, then fades.
var _pop := {"bronze": 0.0, "gold": 0.0}
var _pop_tweens := {}
## kind -> {"delta": int, "t": 0 to 1 (linear), "tween": Tween}
var _deltas := {}
## Counts last seen, and for which seat.
var _shown := {}
var _shown_seat := -1
## Where each pill was drawn last, for flying coins and the deltas.
var _pill_rects := {}

## The tick, within the 0.06 to 0.3 s budget each way (docs/design/theme.md).
const POP_UP := 0.08
const POP_DOWN := 0.22
## WHY longer than UI motion: the delta is information to read, not a
## transition; it holds for about half of this, then fades.
const DELTA_TIME := 0.9
## Part of DELTA_TIME the delta holds before it fades.
const DELTA_HOLD := 0.55


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		seat_pressed.emit(seat_index, get_global_mouse_position())


func update(p_index: int, p_data: Dictionary, p_active: bool, p_me: bool, p_deadline: float, p_step_seconds: float) -> void:
	seat_index = p_index
	data = p_data
	is_active = p_active
	is_me = p_me
	deadline_ms = p_deadline
	step_ms = p_step_seconds * 1000.0
	_watch_capital()
	queue_redraw()


## Pops a count that changed since the last update of the same seat.
func _watch_capital() -> void:
	if _shown_seat != seat_index:
		reset_capital()
	for kind in ["bronze", "gold"]:
		var now := int(data.get(kind, 0))
		if _shown.has(kind) and int(_shown[kind]) != now:
			_start_pop(kind, now - int(_shown[kind]))
		_shown[kind] = now
	_shown_seat = seat_index


## Forgets the counts seen so far and stops any pop: the next update is a
## fresh start (a new game, or this plate now shows another seat).
func reset_capital() -> void:
	for tw in _pop_tweens.values():
		if tw.is_valid():
			tw.kill()
	for d in _deltas.values():
		if d["tween"].is_valid():
			d["tween"].kill()
	_pop_tweens.clear()
	_deltas.clear()
	_pop = {"bronze": 0.0, "gold": 0.0}
	_shown.clear()
	_shown_seat = -1
	queue_redraw()


func _start_pop(kind: String, delta: int) -> void:
	if _pop_tweens.has(kind) and _pop_tweens[kind].is_valid():
		_pop_tweens[kind].kill()
	var setter := func(v: float) -> void:
		_pop[kind] = v
		queue_redraw()
	# WHY from the current value: a second change mid-tick swells again
	# from where it is instead of snapping back to rest.
	var tw := create_tween()
	tw.tween_method(setter, float(_pop[kind]), 1.0, POP_UP).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(setter, 1.0, 0.0, POP_DOWN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pop_tweens[kind] = tw
	# A second change while a delta still holds folds into it; one already
	# fading is replaced.
	if _deltas.has(kind):
		if float(_deltas[kind]["t"]) < DELTA_HOLD:
			delta += int(_deltas[kind]["delta"])
		if _deltas[kind]["tween"].is_valid():
			_deltas[kind]["tween"].kill()
		_deltas.erase(kind)
	if delta == 0:
		return
	var d := {"delta": delta, "t": 0.0}
	var dt := create_tween()
	dt.tween_method(func(v: float) -> void:
		d["t"] = v
		queue_redraw(), 0.0, 1.0, DELTA_TIME)
	dt.tween_callback(func() -> void:
		if is_same(_deltas.get(kind), d):
			_deltas.erase(kind)
		queue_redraw())
	d["tween"] = dt
	_deltas[kind] = d


func _process(_delta: float) -> void:
	if is_active and deadline_ms > 0:
		queue_redraw()


func avatar_center() -> Vector2:
	return get_global_transform() * _avatar_local()


## Where coins leave from and land: the coin on the capital pill (or, for
## gold before there is any, where its pill will appear).
func capital_center(kind := "bronze") -> Vector2:
	if not _pill_rects.has("bronze"):
		return avatar_center()
	var rect: Rect2 = _pill_rects.get(kind, _pill_rects["bronze"])
	var r := rect.size.y * CapitalChip.COIN_R
	var local := Vector2(rect.position.x + r, rect.get_center().y)
	if not _pill_rects.has(kind):
		local = Vector2(rect.end.x + PILL_GAP * s + r, rect.get_center().y)
	return get_global_transform() * local


func _avatar_local() -> Vector2:
	if strip:
		return Vector2(13 * s, size.y / 2.0)
	return Vector2((8 + 15) * s, (6 + 15) * s + _lift())


func _lift() -> float:
	return -3.0 * s if is_active and not strip else 0.0


func _draw() -> void:
	var connected: bool = data.get("connected", true) or data.get("isBot", false)
	if not strip:
		var box := Rect2(Vector2(0, _lift()), size)
		if is_active:
			var ring := StyleBoxFlat.new()
			ring.bg_color = UiTheme.PRIMARY
			ring.set_corner_radius_all(int(16 * s))
			draw_style_box(ring, box.grow(4 * s))
		var plate := UiTheme.card_box(UiTheme.PLATE_ON if is_active else Companies.PANEL, 12 * s, 3 * s, 2)
		draw_style_box(plate, box)

	var text := UiTheme.ui_font()
	var display := UiTheme.display_font()
	var c := _avatar_local()
	var r := (13.0 if strip else 15.0) * s
	var fill: Color = avatar_color if connected else avatar_color.lerp(Color.GRAY, 0.6)
	draw_circle(c, r, Companies.INK)
	draw_circle(c, r - 2, fill)
	var name_text := "You" if is_me else String(data.get("name", "?"))
	var initial := name_text.substr(0, 1).to_upper()
	var ipx := int((12.0 if strip else 14.0) * s)
	var iw := display.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, ipx).x
	draw_string(display, c + Vector2(-iw / 2.0, ipx * 0.36), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, ipx, Companies.INK)

	# Timer arc around the avatar.
	if is_active and deadline_ms > 0 and step_ms > 0:
		var remaining := (deadline_ms - Time.get_unix_time_from_system() * 1000.0) / step_ms
		remaining = clampf(remaining, 0.0, 1.0)
		var arc_color := Companies.GOLD if remaining > 0.3 else Companies.ALERT
		draw_arc(c, r + 3.5 * s, -PI / 2, -PI / 2 + TAU * remaining, 40, Companies.INK, 3.5 * s, true)
		draw_arc(c, r + 3.5 * s, -PI / 2, -PI / 2 + TAU * remaining, 40, arc_color, 2.2 * s, true)
	elif is_active:
		draw_arc(c, r + 3.5 * s, 0, TAU, 40, Companies.GOLD, 2.2 * s, true)

	var bronze := int(data.get("bronze", 0))
	var gold := int(data.get("gold", 0))
	if strip:
		_draw_strip(text, c, r, name_text, bronze, gold)
		return

	# Name, then a tag: bot, or away while disconnected.
	var nx := c.x + r + 7 * s
	var top := 6 * s + _lift()
	var npx := int(12 * s)
	var max_w := size.x - nx - 6 * s
	var tag := "bot" if data.get("isBot", false) else ("away" if not connected else "")
	var tag_w := 0.0
	if tag != "":
		tag_w = text.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * s)).x + 8 * s
	# A long name gives way to its short form ("Analyst Avi" -> "Avi").
	var words := name_text.split(" ", false)
	var short_name: String = words[words.size() - 1] if data.get("isBot", false) and words.size() > 1 else (words[0] if words.size() > 0 else name_text)
	var shown := name_text
	if text.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, npx).x > max_w - tag_w:
		shown = _fit(text, short_name, npx, max_w - tag_w)
	draw_string(text, Vector2(nx, top + 13 * s), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, npx, Companies.INK if connected else Companies.INK_SOFT)
	if tag != "":
		var tx := nx + text.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, npx).x + 4 * s
		var tag_box := Rect2(tx, top + 3 * s, tag_w - 4 * s, 13 * s)
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color(0, 0, 0, 0)
		tb.border_color = Companies.INK
		tb.set_border_width_all(1)
		tb.set_corner_radius_all(int(4 * s))
		draw_style_box(tb, tag_box)
		draw_string(text, Vector2(tx + 2 * s, top + 13 * s), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * s), Companies.INK)
	# WHY 38 and pips first: a regulator seal sticks up from its pip; it
	# goes under the coin's lip with its "R" clear, and the pips keep off
	# the plate's bottom edge.
	_draw_pips(text, Vector2(8 * s, top + 38 * s), size.x - 12 * s)
	_draw_coins(Vector2(nx, top + 24 * s), bronze, gold, wide, size.x - 6 * s)


func _draw_strip(text: Font, c: Vector2, r: float, name_text: String, bronze: int, gold: int) -> void:
	var px := int(13 * s)
	var x := c.x + r + 8 * s
	var base := size.y / 2.0 + px * 0.36
	draw_string(text, Vector2(x, base), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.INK)
	x += text.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 10 * s
	# Pips flush right; capital gets what is left.
	var pw := 0.0
	for p in _pip_list():
		pw += (28.0 if p[2] else 23.0) * s
	var pips_x := size.x - pw - 4 * s
	x = _draw_coins(Vector2(x, size.y / 2.0), bronze, gold, true, pips_x - 8 * s, pips_x - 2 * s)
	_draw_pips(text, Vector2(maxf(x, pips_x), size.y / 2.0 - 9 * s), size.x)


## Capital pills (bronze, then gold once there is any); returns the x
## after them. To fit `right` it drops the words, then shrinks. Deltas
## may use the room up to `delta_right` (default: `right`).
func _draw_coins(at: Vector2, bronze: int, gold: int, spell: bool, right: float = INF, delta_right: float = NAN) -> float:
	var h := (15.0 if strip else 14.0) * s
	var pills := [["bronze", bronze, "capital" if spell else ""]]
	if gold > 0:
		pills.append(["gold", gold, "gold" if spell else ""])
	var gap := PILL_GAP * s
	var total := _pills_width(pills, h, gap)
	if at.x + total > right and spell:
		for p in pills:
			p[2] = ""
		total = _pills_width(pills, h, gap)
	if at.x + total > right:
		# WHY a 0.6 floor: smaller counts stop being readable on a phone.
		var k := maxf(0.6, (right - at.x) / total)
		h *= k
		gap *= k
	var x := at.x
	_pill_rects.clear()
	for p in pills:
		var kind: String = p[0]
		var rect := CapitalChip.pill(self, Vector2(x, at.y), int(p[1]), p[2], h, kind == "gold", float(_pop[kind]))
		_pill_rects[kind] = rect
		x = rect.end.x + gap
	_draw_deltas(h, delta_right if not is_nan(delta_right) else right)
	return x - gap + 8.0 * s


func _pills_width(pills: Array, h: float, gap: float) -> float:
	var total := -gap
	for p in pills:
		total += CapitalChip.pill_width(int(p[1]), p[2], h) + gap
	return total


## "+3" or "-2" right after the pill whose count just changed, drifting up
## a little. Where there is no room before the next pill or the edge, it is
## left out: the gold flash and the flying coins already say it.
## WHY not above the pill: that is the name row.
func _draw_deltas(h: float, right: float) -> void:
	var font := UiTheme.display_font()
	var px := int(h * 0.9)
	var limit := minf(right, size.x - 4.0 * s)
	var reduce := UiTheme.reduce_motion()
	for kind in ["bronze", "gold"]:
		if not _deltas.has(kind) or not _pill_rects.has(kind):
			continue
		var d: Dictionary = _deltas[kind]
		var t: float = d["t"]
		var delta: int = d["delta"]
		var txt := ("+%d" if delta > 0 else "%d") % delta
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var rect: Rect2 = _pill_rects[kind]
		var x := rect.end.x + 3.0 * s
		var stop := limit
		if kind == "bronze" and _pill_rects.has("gold"):
			stop = minf(stop, _pill_rects["gold"].position.x - 2.0 * s)
		if x + w > stop:
			continue
		var rise := 0.0 if reduce else ease(t, 0.3) * 3.0 * s
		var at := Vector2(x, rect.get_center().y + px * 0.36 - rise)
		var a := clampf((1.0 - t) / (1.0 - DELTA_HOLD), 0.0, 1.0)
		var fill := UiTheme.MINT if delta > 0 else UiTheme.BADGE
		draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(4, int(px * 0.3)), Color(UiTheme.OUTLINE, a))
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(fill, a))


func _pip_list() -> Array:
	var counts := [0, 0, 0, 0, 0, 0]
	for card in data.get("portfolio", []):
		counts[int(card.get("company", 0))] += 1
	var tokens := Companies.tokens_of(data)
	var out := []
	for company in 6:
		if counts[company] > 0 or tokens.has(company):
			out.append([company, counts[company], tokens.has(company)])
	return out


## One block per company held, with the count; a gold seal on the corner
## of each company whose regulator token this seat holds.
func _draw_pips(text: Font, at: Vector2, right: float) -> void:
	var display := UiTheme.display_font()
	var x := at.x
	var pip := 18.0 * s
	var seals: Array[Vector2] = []
	for p in _pip_list():
		if x + pip > right:
			break
		var company: int = p[0]
		var box := Rect2(x, at.y, pip, pip)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Companies.color_of(company)
		sb.border_color = Companies.INK
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(3 * s))
		draw_style_box(sb, box)
		var txt := str(p[1])
		var px := int(11 * s)
		var tw := display.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(display, Vector2(x + pip / 2.0 - tw / 2.0, at.y + pip / 2.0 + px * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.band_text_color(company))
		if p[2]:
			seals.append(Vector2(box.end.x - 1 * s, box.position.y + 1 * s))
		x += pip + (10.0 if p[2] else 5.0) * s
	# WHY: seals are drawn after every pip so the next pip cannot cover one;
	# a small "R" ring was too easy to miss on a phone.
	for at_seal in seals:
		var rr := 8.5 * s
		draw_circle(at_seal, rr, Companies.INK)
		draw_circle(at_seal, rr - 1.5 * s, Companies.GOLD)
		var px := int(10 * s)
		var rw := display.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(display, at_seal + Vector2(-rw / 2.0, px * 0.36), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.INK)


## `text` cut with an ellipsis to fit `width` px.
static func _fit(font: Font, text: String, px: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		t = t.substr(0, t.length() - 1)
	return t + "…"
