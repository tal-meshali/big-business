class_name SeatView
extends Control
## A player's plate, after the design canvas: white with an ink border and a
## hard shadow; avatar with initial, name (plus a "bot" badge), capital, and
## one colour pip per company held with an R bubble for a regulator token.
## The active seat's plate turns warm with a yellow ring and lifts. In
## `compact` mode (the local player's row inside the bottom bar) it draws a
## single borderless row instead. A timer arc runs around the active avatar.

signal seat_pressed(seat_index: int, at: Vector2)

const W := 218.0
const H := 118.0
const COMPACT_H := 52.0
## Avatar fills, one per seat position, in the design's pastels.
const AVATAR_FILLS := [Color("#FFD98A"), Color("#9ED9B5"), Color("#A9C5F5"), Color("#F5B8A0"), Color("#D9C5F5"), Color("#F5E1A0"), Color("#B5E0E8")]

var seat_index: int = -1
var data: Dictionary = {}
var is_active: bool = false
var is_me: bool = false
var compact: bool = false:
	set(value):
		compact = value
		queue_redraw()
var deadline_ms: float = 0.0
var step_ms: float = 0.0


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
	queue_redraw()


func _process(_delta: float) -> void:
	if is_active and deadline_ms > 0:
		queue_redraw()


func avatar_center() -> Vector2:
	if compact:
		return global_position + Vector2(UiTheme.px(13), size.y / 2.0)
	return global_position + Vector2(UiTheme.px(6 + 15), UiTheme.px(6 + 15) - _lift())


func _lift() -> float:
	return UiTheme.px(3) if (is_active and not compact) else 0.0


func _draw() -> void:
	var p := UiTheme.SCALE
	var connected: bool = data.get("connected", true) or data.get("isBot", false)
	var lift := _lift()
	var name_text := String(data.get("name", "?"))
	var fill: Color = AVATAR_FILLS[maxi(seat_index, 0) % AVATAR_FILLS.size()]
	if not connected:
		fill = fill.lerp(Color.GRAY, 0.6)

	if compact:
		_draw_row(Vector2(0, 0), size.x, 13 * p, name_text, fill, connected)
		return

	# Plate: ring first (active), then the hard-shadow box.
	var rect := Rect2(Vector2(0, -lift), size)
	if is_active:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Companies.PRIMARY
		ring.set_corner_radius_all(int(15 * p))
		ring.anti_aliasing = true
		draw_style_box(ring, rect.grow(4 * p))
	var box := HardBox.new(Companies.PLATE_ON if is_active else Companies.PANEL, 12 * p, 3 * p)
	box.border_width = 2 * p
	box.draw(get_canvas_item(), rect)

	var pad := 6 * p
	_draw_row(Vector2(pad, pad - lift), size.x - 2 * pad, 15 * p, name_text, fill, connected)
	_draw_pips(Vector2(pad, pad + 30 * p + 5 * p - lift), size.x - 2 * pad)


## Avatar, name with badges, coins. `r` is the avatar radius.
func _draw_row(at: Vector2, width: float, r: float, name_text: String, fill: Color, connected: bool) -> void:
	var p := UiTheme.SCALE
	var c := at + Vector2(r, r)
	draw_circle(c, r, Companies.INK)
	draw_circle(c, r - 2 * p, fill)
	var initial := name_text.substr(0, 1).to_upper()
	_centered(UiTheme.display_heavy(), initial, c, int(r * 0.95), Companies.INK)

	# Timer arc around the avatar while this seat is on the clock.
	if is_active and deadline_ms > 0 and step_ms > 0:
		var remaining := (deadline_ms - Time.get_unix_time_from_system() * 1000.0) / step_ms
		remaining = clampf(remaining, 0.0, 1.0)
		var arc_color := Companies.GOLD if remaining > 0.3 else Companies.ALERT
		draw_arc(c, r + 4 * p, -PI / 2, -PI / 2 + TAU * remaining, 40, arc_color, 3 * p, true)

	var x := at.x + 2 * r + 7 * p
	var name_font := UiTheme.bold()
	var name_px := int(12 * p)
	var label := "You" if is_me else name_text
	var name_w := name_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px).x
	var max_name: float = width - (x - at.x) - (0.0 if is_me else 8.0 * p)
	if compact:
		draw_string(name_font, Vector2(x, c.y + name_px * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, max_name, name_px, Companies.INK if connected else Companies.INK_SOFT)
		x += minf(name_w, max_name) + 8 * p
		_draw_coins(Vector2(x, c.y), true)
		var pip_w := _pips_width()
		_draw_pips(Vector2(at.x + width - pip_w, c.y - 9 * p), pip_w)
		return
	var name_y := at.y + 4 * p + name_px * 0.9
	draw_string(name_font, Vector2(x, name_y), label, HORIZONTAL_ALIGNMENT_LEFT, max_name, name_px, Companies.INK if connected else Companies.INK_SOFT)
	var badge := ""
	if data.get("isBot", false):
		badge = "bot"
	elif not connected:
		badge = "away"
	if badge != "":
		var bx := x + minf(name_w, max_name) + 4 * p
		var bpx := int(9 * p)
		var bw := name_font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bpx).x + 6 * p
		if bx + bw <= at.x + width:
			var brect := Rect2(bx, name_y - name_px * 0.85, bw, bpx + 4 * p)
			draw_rect(brect, Companies.INK, false, 1.0 * p)
			draw_string(name_font, Vector2(bx + 3 * p, brect.get_center().y + bpx * 0.36), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bpx, Companies.INK)
	_draw_coins(Vector2(x, at.y + 30 * p - 7 * p), width > 150 * p)


## Bronze count (and gold when any) after a small coin icon.
func _draw_coins(at: Vector2, with_word: bool) -> void:
	var p := UiTheme.SCALE
	var font := UiTheme.bold()
	var px := int(12 * p)
	var bronze := int(data.get("bronze", 0))
	var gold := int(data.get("gold", 0))
	var x := at.x
	Glyphs.coin(self, Vector2(x + 6 * p, at.y), 6 * p, false)
	x += 16 * p
	var text := str(bronze) + (" capital" if with_word and gold == 0 else "")
	draw_string(font, Vector2(x, at.y + px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.INK)
	if gold > 0:
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 6 * p
		Glyphs.coin(self, Vector2(x + 6 * p, at.y), 6 * p, true)
		draw_string(font, Vector2(x + 16 * p, at.y + px * 0.36), str(gold), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Companies.INK)


func _counts() -> Array:
	var counts := [0, 0, 0, 0, 0, 0]
	for card in data.get("portfolio", []):
		counts[int(card.get("company", 0))] += 1
	return counts


func _pips_width() -> float:
	var p := UiTheme.SCALE
	var n := 0
	var counts := _counts()
	var tokens: Array = data.get("tokens", [])
	for company in 6:
		if counts[company] > 0 or tokens.has(company):
			n += 1
	return maxf(0.0, n * 18 * p + maxi(n - 1, 0) * 5 * p)


## One deed-band pip per company held; an R bubble marks a regulator token.
func _draw_pips(at: Vector2, width: float) -> void:
	var p := UiTheme.SCALE
	var counts := _counts()
	var tokens: Array = data.get("tokens", [])
	var x := at.x
	var pip_w := 18 * p
	var font := UiTheme.display_heavy()
	for company in 6:
		var tok: bool = tokens.has(company)
		if counts[company] == 0 and not tok:
			continue
		if x + pip_w > at.x + width + 1:
			break
		var pip := Rect2(x, at.y, pip_w, 18 * p)
		var s := StyleBoxFlat.new()
		s.bg_color = Companies.color_of(company)
		s.border_color = Companies.INK
		s.set_border_width_all(int(1.5 * p))
		s.set_corner_radius_all(int(3 * p))
		s.anti_aliasing = true
		draw_style_box(s, pip)
		_centered(font, str(counts[company]), pip.get_center(), int(11 * p), Companies.band_text_color(company))
		if tok:
			var tc := Vector2(pip.end.x, pip.position.y)
			draw_circle(tc, 7 * p, Companies.INK)
			draw_circle(tc, 5.5 * p, Companies.CARD_FACE)
			_centered(font, "R", tc, int(8 * p), Companies.INK)
		x += pip_w + 5 * p


func _centered(font: Font, text: String, at: Vector2, px: int, color: Color) -> void:
	px = maxi(px, 3)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	draw_string(font, at + Vector2(-w / 2.0, px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
