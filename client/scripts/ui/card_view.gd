class_name CardView
extends Button
## A share card drawn like a title deed: off-white face, black border, a
## solid colour band with the share count and company, the company's art
## in a tinted window, and the share count in words at the foot.
## Drawn in code so no art assets are needed yet. Portrait 5:7. The back
## follows the card back selected in Cosmetics. In a private room with a
## custom deck (CardArt), its pictures fill the art window and the back.
## Press and hold for HOLD_SECONDS to look at a card closely: that emits
## card_held (and card_released on letting go) instead of card_pressed.

signal card_pressed(card_id: int)
signal card_held(card: CardView)
signal card_released(card: CardView)

const W := 120.0
const H := 168.0
## Press-and-hold time before a card counts as held rather than tapped.
const HOLD_SECONDS := 0.35
## Finger travel (card px) that turns a hold into a scroll or drag.
const HOLD_SLOP := 14.0
## How far a selected card rises out of the hand.
const LIFT := 18.0
const RADIUS := 11
const INSET := 6.0
const BAND_H := 42.0
const FOOT_H := 14.0

var card_id: int = -1
var company: int = 0
var coins: int = 0
var face_up: bool = true
var selectable: bool = true:
	set(value):
		selectable = value
		disabled = not value
		queue_redraw()
## Draws the orange "tap me" ring (the table sets it on cards you may use).
var highlight: bool = false:
	set(value):
		highlight = value
		queue_redraw()
## Hatched: a Market share your own regulator token keeps you from taking.
var blocked: bool = false:
	set(value):
		blocked = value
		queue_redraw()
var selected: bool = false:
	set(value):
		if selected == value:
			return
		selected = value
		# WHY: a new lift must replace one still running; two tweens on
		# position:y finish in either order and can strand the card.
		if _lift_tween != null:
			_lift_tween.kill()
		_lift_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_lift_tween.tween_property(self, "position:y", _rest_y - (LIFT if value else 0.0), 0.18)
		# Drawn above its neighbours in the fan while selected.
		z_index = 1 if value else 0
		queue_redraw()
## True from the moment a press becomes a hold until it is let go.
var held: bool = false
var _rest_y: float = 0.0
var _lift_tween: Tween
var _press_down: bool = false
var _press_pos := Vector2.ZERO
## Bumped on every press and release so a stale hold timer does nothing.
var _press_serial: int = 0
var _swallow_press: bool = false
## Designer preview: pictures shown instead of the room's (null: use the room's).
var preview_back: Texture2D
var preview_art: Texture2D


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	flat = true
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)


func _ready() -> void:
	# WHY by path: tests compile CardView before autoloads exist.
	var net := get_node_or_null("/root/Net")
	if net != null:
		net.custom_deck_changed.connect(queue_redraw)


func _on_pressed() -> void:
	if _swallow_press:
		_swallow_press = false
		return
	card_pressed.emit(card_id)


## Tells a tap from a press-and-hold. Runs for disabled cards too, so any
## card on the table can be looked at, not only the ones you may play.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_press_serial += 1
		if event.pressed:
			_press_down = true
			_press_pos = event.position
			_swallow_press = false
			var serial := _press_serial
			get_tree().create_timer(HOLD_SECONDS).timeout.connect(func() -> void:
				if serial == _press_serial and _press_down:
					_begin_hold())
		else:
			_press_down = false
			if held:
				held = false
				card_released.emit(self)
	elif event is InputEventMouseMotion and _press_down and not held:
		if event.position.distance_to(_press_pos) > HOLD_SLOP:
			_press_serial += 1


func _begin_hold() -> void:
	held = true
	# The release that ends a hold must not also select or take the card.
	_swallow_press = true
	card_held.emit(self)


func setup(p_card_id: int, p_company: int, p_coins: int = 0, p_face_up: bool = true) -> void:
	card_id = p_card_id
	company = p_company
	coins = p_coins
	face_up = p_face_up
	queue_redraw()


## Remember the resting y so the selection lift can return to it.
func set_rest_position(pos: Vector2) -> void:
	position = pos
	_rest_y = pos.y


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if highlight or selected:
		# Orange ring outside the card: you can tap this one now.
		var ring := StyleBoxFlat.new()
		ring.set_corner_radius_all(RADIUS + 5)
		ring.bg_color = UiTheme.RING
		var grow := 7.0 if selected else 5.5
		draw_style_box(ring, rect.grow(grow))
	var outer := StyleBoxFlat.new()
	outer.set_corner_radius_all(RADIUS)
	outer.bg_color = Companies.CARD_FACE
	outer.border_color = Companies.INK
	outer.set_border_width_all(2)
	outer.anti_aliasing = true
	if not highlight and not selected:
		outer.shadow_color = Color(0.06, 0.16, 0.09, 0.28)
		outer.shadow_size = 6
		outer.shadow_offset = Vector2(0, 5)
	draw_style_box(outer, rect)

	if not face_up:
		_draw_back()
		return

	var color := Companies.color_of(company)
	var text_on_band := Companies.band_text_color(company)
	var comp := Companies.get_company(company)
	var display := UiTheme.display_font()
	var text := UiTheme.ui_font()

	# Colour band: share count on the left (the part still visible in a
	# fanned hand), then "SHARE OF" over the short name.
	var band := Rect2(INSET, INSET, size.x - INSET * 2, BAND_H)
	var band_box := StyleBoxFlat.new()
	band_box.bg_color = color
	band_box.border_color = Companies.INK
	band_box.set_border_width_all(2)
	band_box.set_corner_radius_all(5)
	draw_style_box(band_box, band)
	var count := str(comp["shares"])
	draw_string(display, Vector2(INSET + 6, INSET + BAND_H / 2.0 + 9), count, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, text_on_band)
	var count_w := display.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
	var mid := (INSET + 6 + count_w + size.x - INSET) / 2.0
	_draw_centered_text("SHARE OF", Vector2(mid, INSET + 13), 8, text_on_band, text)
	var short := Companies.short_name_of(company).to_upper()
	# The short name shrinks to fit beside a two-digit count.
	var room := size.x - INSET - 4 - (INSET + 6 + count_w + 4)
	var short_px := 15
	while short_px > 9 and display.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, short_px).x > room:
		short_px -= 1
	_draw_centered_text(short, Vector2(mid, INSET + 30), short_px, text_on_band, display)

	# Full name over a rule, the art window, and the share count in words.
	var name_y := INSET + BAND_H + 4
	_draw_centered_text(String(comp["name"]), Vector2(size.x / 2.0, name_y + 7), 11, Companies.INK, text)
	draw_line(Vector2(INSET, name_y + 16), Vector2(size.x - INSET, name_y + 16), Companies.INK, 1.2)
	# Art window: the only area a custom design may replace.
	var art := Rect2(INSET, name_y + 20, size.x - INSET * 2, size.y - name_y - 20 - FOOT_H - INSET)
	var art_box := StyleBoxFlat.new()
	art_box.bg_color = color.lerp(Color.WHITE, 0.78)
	art_box.border_color = Companies.INK
	art_box.set_border_width_all(1)
	art_box.set_corner_radius_all(4)
	draw_style_box(art_box, art)
	var custom := preview_art if preview_art != null else CardArt.company_texture(company)
	if custom != null:
		draw_texture_rect(custom, art.grow(-1), false)
		draw_rect(art, Companies.INK, false, 1.0)
	elif coins == 0:
		_draw_icon(art.get_center(), minf(art.size.x, art.size.y) * 0.8, color)
	var foot_y := size.y - INSET - FOOT_H
	draw_line(Vector2(INSET, foot_y + 3), Vector2(size.x - INSET, foot_y + 3), Companies.INK, 1.2)
	_draw_centered_text("%d shares issued" % int(comp["shares"]), Vector2(size.x / 2.0, foot_y + 12), 10, Companies.INK, text)

	if coins > 0:
		if custom == null:
			_draw_icon(art.get_center() - Vector2(0, art.size.y * 0.12), minf(art.size.x, art.size.y) * 0.55, color)
		_draw_coin_badge(coins, art.get_center() + Vector2(0, art.size.y * 0.16))
	if blocked:
		_draw_blocked_stripes(rect)


func _draw_back() -> void:
	var inner := Rect2(INSET, INSET, size.x - INSET * 2, size.y - INSET * 2)
	var custom := preview_back if preview_back != null else CardArt.back_texture()
	if custom != null:
		draw_texture_rect(custom, inner, false)
		draw_rect(inner, Companies.INK, false, 1.5)
		return
	match Cosmetics.shown_card_back():
		"back_midnight":
			_draw_back_midnight(inner)
		"back_sunrise":
			_draw_back_sunrise(inner)
		"back_pinstripe":
			_draw_back_pinstripe(inner)
		"back_gilded":
			_draw_back_gilded(inner)
		"back_blueprint":
			_draw_back_blueprint(inner)
		"back_ticker":
			_draw_back_ticker(inner)
		_:
			_draw_back_classic(inner)


## Six colour stripes, one per company, ink rules, then the monogram.
func _draw_back_classic(inner: Rect2) -> void:
	var gap := 3.0
	var cell := (inner.size.x - gap * 5) / 6.0
	for row_y in [inner.position.y + 2, inner.end.y - 14]:
		for i in 6:
			var r := Rect2(inner.position.x + i * (cell + gap), row_y, cell, 12)
			draw_rect(r, Companies.color_of(i), true)
			draw_rect(r, Companies.INK, false, 1.2)
	draw_line(Vector2(inner.position.x + 12, inner.position.y + 26), Vector2(inner.end.x - 12, inner.position.y + 26), Companies.INK, 2.4)
	draw_line(Vector2(inner.position.x + 12, inner.end.y - 26), Vector2(inner.end.x - 12, inner.end.y - 26), Companies.INK, 2.4)
	_draw_monogram(Companies.INK)


## Dark ink face with a light monogram and a thin double border.
func _draw_back_midnight(inner: Rect2) -> void:
	var entry := Cosmetics.card_back_entry("back_midnight")
	var face: Color = entry["accent"]
	var light: Color = entry["ink"]
	draw_rect(inner, face, true)
	draw_rect(inner, light, false, 1.5)
	draw_rect(inner.grow(-5), Color(light, 0.5), false, 1.0)
	# Four small stars in the corners.
	for corner in [inner.position + Vector2(12, 12), Vector2(inner.end.x - 12, inner.position.y + 12), Vector2(inner.position.x + 12, inner.end.y - 12), inner.end - Vector2(12, 12)]:
		draw_circle(corner, 2.0, light)
	_draw_monogram(light)


## Warm horizontal bands from yellow through orange to red, monogram in ink.
func _draw_back_sunrise(inner: Rect2) -> void:
	var bands := 7
	var band_h := inner.size.y / bands
	var top := Cosmetics.card_back_entry("back_sunrise")["accent"] as Color
	var bottom := Companies.color_of(5)
	for i in bands:
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(inner.position.x, inner.position.y + i * band_h, inner.size.x, band_h + 0.5), top.lerp(bottom, t), true)
	draw_rect(inner, Companies.INK, false, 1.5)
	# A paler plate so the monogram stays readable on the orange middle.
	var plate := Rect2(inner.position.x + 14, size.y / 2.0 - 30, inner.size.x - 28, 60)
	draw_rect(plate, Color(Companies.CARD_FACE, 0.85), true)
	draw_rect(plate, Companies.INK, false, 1.0)
	_draw_monogram(Companies.INK)


## Thin vertical lines in the company blue, monogram on a white plate.
func _draw_back_pinstripe(inner: Rect2) -> void:
	var stripe := Cosmetics.card_back_entry("back_pinstripe")["accent"] as Color
	var x := inner.position.x + 4.0
	while x < inner.end.x - 2.0:
		draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), stripe, 1.0)
		x += 6.0
	draw_rect(inner, Companies.INK, false, 1.5)
	var plate := Rect2(inner.position.x + 14, size.y / 2.0 - 30, inner.size.x - 28, 60)
	draw_rect(plate, Companies.CARD_FACE, true)
	draw_rect(plate, Companies.INK, false, 1.0)
	_draw_monogram(Companies.INK)


## Shop skin: deep green face, gold double frame and gold monogram.
## Placeholder drawing until the commissioned art (TODO-local F).
func _draw_back_gilded(inner: Rect2) -> void:
	var entry := Cosmetics.card_back_entry("back_gilded")
	var gold: Color = entry["ink"]
	draw_rect(inner, entry["accent"], true)
	draw_rect(inner, gold, false, 2.5)
	draw_rect(inner.grow(-6), gold, false, 1.0)
	for corner in [inner.position + Vector2(10, 10), Vector2(inner.end.x - 10, inner.position.y + 10), Vector2(inner.position.x + 10, inner.end.y - 10), inner.end - Vector2(10, 10)]:
		draw_colored_polygon(PackedVector2Array([corner + Vector2(0, -4), corner + Vector2(4, 0), corner + Vector2(0, 4), corner + Vector2(-4, 0)]), gold)
	_draw_monogram(gold)


## Shop skin: drafting-blue face with a light grid, like a company's floor plan.
func _draw_back_blueprint(inner: Rect2) -> void:
	var entry := Cosmetics.card_back_entry("back_blueprint")
	var line: Color = entry["ink"]
	draw_rect(inner, entry["accent"], true)
	var x := inner.position.x + 8.0
	while x < inner.end.x - 2.0:
		draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), Color(line, 0.25), 1.0)
		x += 10.0
	var y := inner.position.y + 8.0
	while y < inner.end.y - 2.0:
		draw_line(Vector2(inner.position.x + 2, y), Vector2(inner.end.x - 2, y), Color(line, 0.25), 1.0)
		y += 10.0
	draw_rect(inner, line, false, 1.5)
	_draw_monogram(line)


## Plus skin: a dark trading screen with a rising green price line.
## Placeholder drawing until the commissioned art (TODO-local F).
func _draw_back_ticker(inner: Rect2) -> void:
	var entry := Cosmetics.card_back_entry("back_ticker")
	var green: Color = entry["ink"]
	draw_rect(inner, entry["accent"], true)
	var pts := PackedVector2Array()
	var steps := 9
	for i in steps + 1:
		var t := float(i) / steps
		var wobble := 10.0 * sin(i * 2.1)
		pts.append(Vector2(inner.position.x + 6 + t * (inner.size.x - 12), inner.end.y - 24 - t * (inner.size.y * 0.45) + wobble))
	draw_polyline(pts, Color(green, 0.55), 2.0, true)
	draw_rect(inner, green, false, 1.5)
	_draw_monogram(green)


func _draw_monogram(color: Color) -> void:
	var display := UiTheme.display_font()
	_draw_centered_text("BIG", Vector2(size.x / 2.0, size.y / 2.0 - 11), 21, color, display)
	_draw_centered_text("BUSINESS", Vector2(size.x / 2.0, size.y / 2.0 + 12), 19, color, display)


## The company's art in a 24-unit box centred on `center`, `box` px wide:
## sun, pine, anchor, gear, cloud, bolt. Ink outlines, company fill.
## WHY: each company also differs in silhouette, for colourblind players.
func _draw_icon(center: Vector2, box: float, color: Color) -> void:
	var k := box / 24.0
	var at := func(x: float, y: float) -> Vector2: return center + (Vector2(x, y) - Vector2(12, 12)) * k
	var w := maxf(1.0, 1.6 * k)
	match company:
		0:
			for ray in [[12, 2, 12, 5], [12, 19, 12, 22], [2, 12, 5, 12], [19, 12, 22, 12], [4.9, 4.9, 7, 7], [17, 17, 19.1, 19.1], [4.9, 19.1, 7, 17], [17, 7, 19.1, 4.9]]:
				draw_line(at.call(ray[0], ray[1]), at.call(ray[2], ray[3]), Companies.INK, w, true)
			draw_circle(at.call(12, 12), 4.5 * k, color)
			draw_arc(at.call(12, 12), 4.5 * k, 0, TAU, 32, Companies.INK, w, true)
		1:
			_ink_polygon([at.call(12, 2), at.call(19, 21), at.call(5, 21)], color, w)
			for seg in [[8.6, 12, 15.4, 12], [7, 16.5, 17, 16.5], [12, 7, 12, 21]]:
				draw_line(at.call(seg[0], seg[1]), at.call(seg[2], seg[3]), Companies.INK, w, true)
		2:
			draw_circle(at.call(12, 5), 2.3 * k, color)
			draw_arc(at.call(12, 5), 2.3 * k, 0, TAU, 24, Companies.INK, w * 1.1, true)
			draw_line(at.call(12, 7.3), at.call(12, 21), Companies.INK, w * 1.1, true)
			draw_line(at.call(8, 10.5), at.call(16, 10.5), Companies.INK, w * 1.1, true)
			draw_arc(at.call(12, 13.5), 7.5 * k, 0, PI, 24, Companies.INK, w * 1.1, true)
		3:
			var gear := [[10.4, 2], [13.6, 2], [14.2, 4.6], [16.2, 5.4], [18.5, 4], [20.7, 6.2], [19.3, 8.5], [20.1, 10.5], [22.7, 11.1], [22.7, 14.3], [20.1, 14.9], [19.3, 16.9], [20.7, 19.2], [18.5, 21.4], [16.2, 20], [14.2, 20.8], [13.6, 23.4], [10.4, 23.4], [9.8, 20.8], [7.8, 20], [5.5, 21.4], [3.3, 19.2], [4.7, 16.9], [3.9, 14.9], [2, 13.6], [2, 10.4], [4.6, 9.8], [5.4, 7.8], [4, 5.5], [6.2, 3.3], [8.5, 4.7], [10.5, 3.9]]
			var pts: Array = []
			for p in gear:
				pts.append(at.call(p[0], p[1] - 0.7))
			_ink_polygon(pts, color, w)
			draw_circle(at.call(12, 12), 3.4 * k, Companies.CARD_FACE)
			draw_arc(at.call(12, 12), 3.4 * k, 0, TAU, 24, Companies.INK, w, true)
		4:
			# Cloud: ink blobs first, then the same blobs in colour, smaller.
			var blobs := [[7.4, 14.2, 4.8], [12.2, 10.6, 5.6], [17.2, 14.6, 4.4]]
			for b in blobs:
				draw_circle(at.call(b[0], b[1]), b[2] * k + w, Companies.INK)
			draw_rect(Rect2(at.call(7.4, 14.2) - Vector2(0, w), (Vector2(17.2, 19) - Vector2(7.4, 14.2)) * k + Vector2(0, 2 * w)), Companies.INK)
			for b in blobs:
				draw_circle(at.call(b[0], b[1]), b[2] * k, color)
			draw_rect(Rect2(at.call(7.4, 14.2), (Vector2(17.2, 19) - Vector2(7.4, 14.2)) * k), color)
		5:
			draw_circle(at.call(12, 12), 9.5 * k, color)
			draw_arc(at.call(12, 12), 9.5 * k, 0, TAU, 40, Companies.INK, w, true)
			draw_circle(at.call(12, 12), 6.2 * k, Companies.CARD_FACE)
			draw_arc(at.call(12, 12), 6.2 * k, 0, TAU, 32, Companies.INK, w, true)
			var bolt := [[13.2, 7.2], [9.4, 12.6], [12.5, 12.6], [11.4, 16.8], [15.2, 11.3], [12.1, 11.3]]
			var bpts := PackedVector2Array()
			for p in bolt:
				bpts.append(at.call(p[0], p[1]))
			draw_colored_polygon(bpts, Companies.INK)


func _ink_polygon(points: Array, fill: Color, width: float) -> void:
	var pts := PackedVector2Array(points)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, Companies.INK, width, true)


func _draw_coin_badge(n: int, c: Vector2) -> void:
	draw_circle(c + Vector2(0, 3), 22, Companies.INK)
	draw_circle(c, 22, Companies.INK)
	draw_circle(c, 19.5, Companies.BRONZE)
	draw_circle(c - Vector2(5, 6), 7, Color(1, 1, 1, 0.18))
	_draw_centered_text(str(n), c + Vector2(0, 1), 22, Companies.CARD_FACE, UiTheme.display_font())


## A share you may not take (you hold its regulator token): diagonal hatching.
func _draw_blocked_stripes(rect: Rect2) -> void:
	var inner := rect.grow(-3)
	var x := inner.position.x - inner.size.y
	while x < inner.end.x:
		var a := Vector2(x, inner.end.y)
		var b := Vector2(x + inner.size.y, inner.position.y)
		var seg = Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]))
		for part in seg:
			draw_polyline(part, Color(Companies.INK, 0.28), 5.0)
		x += 16.0


func _draw_centered_text(text: String, at: Vector2, px: int, color: Color, font: Font = null) -> void:
	if font == null:
		font = UiTheme.ui_font()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	draw_string(font, at + Vector2(-w / 2.0, px / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
