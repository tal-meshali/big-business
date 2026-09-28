class_name CardView
extends Button
## A share card drawn like a title deed, after the design canvas: cream face,
## ink border, a colour band with the share count and company name, the full
## name on a rule, an art window in the company tint with the company's
## silhouette, and a deed-style footer. Everything is drawn relative to
## `size`, so the same card renders crisp at any size (hand, Market,
## Portfolio stack) without scaling text. Portrait 5:7; the design card is
## 100x140. The back follows the card back selected in Cosmetics.

signal card_pressed(card_id: int)

## Default size (project px): a design card at the lobby scale.
const W := 120.0
const H := 168.0

var card_id: int = -1
var company: int = 0
var coins: int = 0
var face_up: bool = true
## Draw the orange action ring around a selectable card (off for decor).
var show_ring: bool = true
## Tappable right now: the card gets the orange action ring.
var selectable: bool = true:
	set(value):
		selectable = value
		disabled = not value
		queue_redraw()
## Off limits for me (a Market share of a company whose token I hold):
## diagonal stripes over the face.
var locked: bool = false:
	set(value):
		locked = value
		queue_redraw()
var selected: bool = false:
	set(value):
		if selected == value:
			return
		selected = value
		var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(self, "position:y", _rest_y - (size.y * 0.13 if value else 0.0), 0.18)
		queue_redraw()
var _rest_y: float = 0.0
var _pulse_tween: Tween
var _flip_tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(func() -> void: card_pressed.emit(card_id))
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	pivot_offset = size / 2.0


func setup(p_card_id: int, p_company: int, p_coins: int = 0, p_face_up: bool = true) -> void:
	card_id = p_card_id
	company = p_company
	coins = p_coins
	face_up = p_face_up
	queue_redraw()


## Set the card's rendered size (project px); keeps the 5:7 ratio when only
## a width is given.
func set_card_size(width: float, height: float = -1.0) -> void:
	var h := height if height > 0 else width * 1.4
	custom_minimum_size = Vector2(width, h)
	size = Vector2(width, h)
	queue_redraw()


## Pulse a warm glow until the card is freed: the tutorial's "tap here".
## WHY: a looping modulate tween rather than a state flag, so the effect
## needs no per-frame code and dies with the card on the next render.
func pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "modulate", Color(1.25, 1.15, 0.75, 1), 0.45)
	_pulse_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.45)


## Turn the card over with a flip about its vertical axis.
func flip_to(up: bool) -> void:
	if face_up == up:
		return
	if _flip_tween != null:
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "scale:x", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(func() -> void:
		face_up = up
		queue_redraw())
	_flip_tween.tween_property(self, "scale:x", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Remember the resting y so the selection lift can return to it.
func set_rest_position(pos: Vector2) -> void:
	position = pos
	_rest_y = pos.y


func _draw() -> void:
	# Design px -> this card's px, per axis (flat cards are foreshortened).
	var ux := size.x / 100.0
	var uy := size.y / 140.0
	var u := minf(ux, uy)
	var rect := Rect2(Vector2.ZERO, size)
	var ink := Companies.INK

	# Action ring (orange) outside the border for tappable and selected cards.
	if (selectable and show_ring) or selected:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Companies.CHANCE
		ring.set_corner_radius_all(int(12 * u))
		ring.anti_aliasing = true
		var grow := (5.0 if selected else 4.0) * u
		draw_style_box(ring, rect.grow(grow))

	var outer := StyleBoxFlat.new()
	outer.set_corner_radius_all(int(9 * u))
	outer.bg_color = Companies.CARD_FACE
	outer.border_color = ink
	outer.set_border_width_all(int(maxf(1.0, 2 * u)))
	outer.anti_aliasing = true
	draw_style_box(outer, rect)

	if not face_up:
		_draw_back(u)
		return

	var color := Companies.color_of(company)
	var text_on_band := Companies.band_text_color(company)
	var comp := Companies.get_company(company)
	var pad := 5.0
	var gap := 3.0
	var x0 := (2 + pad) * ux
	var inner_w := size.x - 2 * x0
	var y := (2 + pad) * uy

	# Colour band: count on the left, "SHARE OF" over the short name centred.
	var band_h := 34.0 * uy
	var band := Rect2(x0, y, inner_w, band_h)
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = color
	band_style.border_color = ink
	band_style.set_border_width_all(int(maxf(1.0, 1.5 * u)))
	band_style.set_corner_radius_all(int(4 * u))
	band_style.anti_aliasing = true
	draw_style_box(band_style, band)
	var cnt_font := UiTheme.display_heavy()
	var cnt_px := int(20 * u)
	draw_string(cnt_font, Vector2(x0 + 5 * ux, band.get_center().y + cnt_px * 0.36), str(comp["shares"]), HORIZONTAL_ALIGNMENT_LEFT, -1, cnt_px, text_on_band)
	var cnt_w := cnt_font.get_string_size(str(comp["shares"]), HORIZONTAL_ALIGNMENT_LEFT, -1, cnt_px).x
	var mid_x := x0 + 5 * ux + cnt_w + (inner_w - 10 * ux - cnt_w) / 2.0
	_centered(UiTheme.bold(), "SHARE OF", Vector2(mid_x, band.position.y + 10.5 * uy), int(maxf(4.0, 6 * u)), Color(text_on_band, 0.9))
	_centered(cnt_font, Companies.short_name_of(company).to_upper(), Vector2(mid_x, band.position.y + 23.5 * uy), int(11.5 * u), text_on_band)
	y += band_h + gap * uy

	# Full name on a rule.
	var name_h := 14.0 * uy
	_centered(UiTheme.bold(), String(comp["name"]), Vector2(size.x / 2.0, y + 6.5 * uy), int(8 * u), ink)
	draw_line(Vector2(x0, y + name_h), Vector2(x0 + inner_w, y + name_h), ink, maxf(1.0, 1 * u))
	y += name_h + gap * uy

	# Footer with a rule above it.
	var foot_h := 12.5 * uy
	var foot_top := size.y - (2 + pad) * uy - foot_h
	draw_line(Vector2(x0, foot_top), Vector2(x0 + inner_w, foot_top), ink, maxf(1.0, 1 * u))
	_centered(UiTheme.body(), "%d shares issued" % int(comp["shares"]), Vector2(size.x / 2.0, foot_top + 8.5 * uy), int(7.5 * u), ink)

	# Art window: the only area a custom design may replace.
	var art := Rect2(x0, y, inner_w, foot_top - gap * uy - y)
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = Companies.tint_of(company)
	art_style.border_color = ink
	art_style.set_border_width_all(int(maxf(1.0, 1 * u)))
	art_style.set_corner_radius_all(int(3 * u))
	art_style.anti_aliasing = true
	draw_style_box(art_style, art)
	Glyphs.company_icon(self, art.get_center(), minf(art.size.x, art.size.y) * 0.34, company, color, ink)

	if locked:
		_draw_stripes(rect.grow(-2 * u), Color(ink, 0.28), 6 * u, 14 * u)
	if coins > 0:
		_draw_coin_badge(art, u)


## Diagonal hatching clipped to `r`, for Market shares I may not take.
func _draw_stripes(r: Rect2, color: Color, width: float, period: float) -> void:
	var o := -r.size.y
	while o < r.size.x:
		var a := Vector2(r.position.x + o, r.end.y)
		var b := Vector2(r.position.x + o + r.size.y, r.position.y)
		# Clip the segment to the rect horizontally (it already spans it vertically).
		if a.x < r.position.x:
			var t := (r.position.x - a.x) / (b.x - a.x)
			a = a.lerp(b, t)
		if b.x > r.end.x:
			var t2 := (r.end.x - a.x) / (b.x - a.x)
			b = a.lerp(b, t2)
		if b.x > a.x:
			draw_line(a, b, color, width)
		o += period


func _draw_coin_badge(art: Rect2, u: float) -> void:
	var c := Vector2(art.position.x + art.size.x / 2.0, art.position.y + art.size.y * 0.6)
	var r := 25.0 * u
	draw_circle(c + Vector2(0, 3 * u), r, Companies.INK)
	Glyphs.coin(self, c, r, false)
	_centered(UiTheme.display_heavy(), str(coins), c + Vector2(0, 1 * u), int(25 * u), Companies.CARD_FACE)


func _draw_back(u: float) -> void:
	var inner := Rect2(Vector2(7, 8) * u, size - Vector2(14, 16) * u)
	match Cosmetics.card_back:
		"back_midnight":
			_draw_back_midnight(inner, u)
		"back_sunrise":
			_draw_back_sunrise(inner, u)
		"back_pinstripe":
			_draw_back_pinstripe(inner, u)
		_:
			_draw_back_classic(inner, u)


## Six colour stripes top and bottom, two rules, the monogram.
func _draw_back_classic(inner: Rect2, u: float) -> void:
	_draw_stripe_row(inner.position.y, inner, u)
	_draw_stripe_row(inner.end.y - 10 * u, inner, u)
	draw_rect(Rect2(inner.position.x + 10 * u, inner.position.y + 22 * u, inner.size.x - 20 * u, 2 * u), Companies.INK, true)
	draw_rect(Rect2(inner.position.x + 10 * u, inner.end.y - 24 * u, inner.size.x - 20 * u, 2 * u), Companies.INK, true)
	_draw_monogram(Companies.INK, u)


func _draw_stripe_row(y: float, inner: Rect2, u: float) -> void:
	var gap := 3.0 * u
	var w := (inner.size.x - gap * 5) / 6.0
	for i in 6:
		var r := Rect2(inner.position.x + i * (w + gap), y, w, 10 * u)
		var s := StyleBoxFlat.new()
		s.bg_color = Companies.color_of(i)
		s.border_color = Companies.INK
		s.set_border_width_all(int(maxf(1.0, u)))
		s.set_corner_radius_all(int(2 * u))
		draw_style_box(s, r)


## Dark ink face with a light monogram and a thin double border.
func _draw_back_midnight(inner: Rect2, u: float) -> void:
	var entry := Cosmetics.card_back_entry("back_midnight")
	var face: Color = entry["accent"]
	var light: Color = entry["ink"]
	draw_rect(inner, face, true)
	draw_rect(inner, light, false, 1.5 * u)
	draw_rect(inner.grow(-5 * u), Color(light, 0.5), false, 1.0 * u)
	for corner in [inner.position + Vector2(12, 12) * u, Vector2(inner.end.x - 12 * u, inner.position.y + 12 * u), Vector2(inner.position.x + 12 * u, inner.end.y - 12 * u), inner.end - Vector2(12, 12) * u]:
		draw_circle(corner, 2.0 * u, light)
	_draw_monogram(light, u)


## Warm horizontal bands from yellow through orange to red, monogram in ink.
func _draw_back_sunrise(inner: Rect2, u: float) -> void:
	var bands := 7
	var band_h := inner.size.y / bands
	var top := Cosmetics.card_back_entry("back_sunrise")["accent"] as Color
	var bottom := Companies.color_of(5)
	for i in bands:
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(inner.position.x, inner.position.y + i * band_h, inner.size.x, band_h + 0.5), top.lerp(bottom, t), true)
	draw_rect(inner, Companies.INK, false, 1.5 * u)
	var plate := Rect2(inner.position.x + 14 * u, size.y / 2.0 - 26 * u, inner.size.x - 28 * u, 52 * u)
	draw_rect(plate, Color(Companies.CARD_FACE, 0.85), true)
	draw_rect(plate, Companies.INK, false, 1.0 * u)
	_draw_monogram(Companies.INK, u)


## Thin vertical lines in the company blue, monogram on a cream plate.
func _draw_back_pinstripe(inner: Rect2, u: float) -> void:
	var stripe := Cosmetics.card_back_entry("back_pinstripe")["accent"] as Color
	var x := inner.position.x + 4.0 * u
	while x < inner.end.x - 2.0 * u:
		draw_line(Vector2(x, inner.position.y + 2 * u), Vector2(x, inner.end.y - 2 * u), stripe, 1.0 * u)
		x += 6.0 * u
	draw_rect(inner, Companies.INK, false, 1.5 * u)
	var plate := Rect2(inner.position.x + 14 * u, size.y / 2.0 - 26 * u, inner.size.x - 28 * u, 52 * u)
	draw_rect(plate, Companies.CARD_FACE, true)
	draw_rect(plate, Companies.INK, false, 1.0 * u)
	_draw_monogram(Companies.INK, u)


func _draw_monogram(color: Color, u: float) -> void:
	var f := UiTheme.display_heavy()
	_centered(f, "BIG", Vector2(size.x / 2.0, size.y / 2.0 - 9 * u), int(17 * u), color)
	_centered(f, "BUSINESS", Vector2(size.x / 2.0, size.y / 2.0 + 9 * u), int(17 * u), color)


func _centered(font: Font, text: String, at: Vector2, px: int, color: Color) -> void:
	px = maxi(px, 3)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	draw_string(font, at + Vector2(-w / 2.0, px * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
