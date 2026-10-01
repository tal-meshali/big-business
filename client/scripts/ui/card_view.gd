class_name CardView
extends Button
## A share card drawn like a title deed: off-white face, black border, a
## solid colour band with the company name, and black text on the body.
## Drawn in code so no art assets are needed yet. Portrait 5:7. The back
## follows the card back selected in Cosmetics.
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
const RADIUS := 8
const INSET := 6.0
const BAND_H := 50.0

var card_id: int = -1
var company: int = 0
var coins: int = 0
var face_up: bool = true
var selectable: bool = true:
	set(value):
		selectable = value
		disabled = not value
		modulate = Color(1, 1, 1, 1) if value else Color(0.82, 0.82, 0.82, 1)
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


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	flat = true
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_on_pressed)


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
	var outer := StyleBoxFlat.new()
	outer.set_corner_radius_all(RADIUS)
	outer.bg_color = Companies.CARD_FACE
	outer.border_color = Companies.INK
	outer.set_border_width_all(2)
	if selected:
		outer.border_color = Companies.GOLD
		outer.set_border_width_all(4)
		outer.shadow_color = Color(Companies.GOLD, 0.5)
		outer.shadow_size = 10
	draw_style_box(outer, rect)

	if not face_up:
		_draw_back()
		return

	var color := Companies.color_of(company)
	var text_on_band := Companies.band_text_color(company)
	var comp := Companies.get_company(company)
	var font := ThemeDB.fallback_font

	# Colour band with a thin ink border, like a deed's title bar.
	var band := Rect2(INSET, INSET, size.x - INSET * 2, BAND_H)
	draw_rect(band, color, true)
	draw_rect(band, Companies.INK, false, 1.5)
	# Share count top-left inside the band: the part of the card that stays
	# visible in a fanned hand.
	draw_string(font, Vector2(INSET + 6, INSET + 22), str(comp["shares"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, text_on_band)
	_draw_icon(Vector2(size.x - INSET - 14, INSET + 14), 8.0, text_on_band)
	_draw_centered_text("SHARE OF", Vector2(size.x / 2.0, INSET + 14), 8, Color(text_on_band, 0.85))
	_draw_centered_text(Companies.short_name_of(company).to_upper(), Vector2(size.x / 2.0, INSET + 38), 15, text_on_band)

	# Body: full name, a deed-style rule, and the share count in words.
	var body_top := INSET + BAND_H + 6
	_draw_centered_text(String(comp["name"]), Vector2(size.x / 2.0, body_top + 10), 9, Companies.INK)
	draw_line(Vector2(INSET + 8, body_top + 20), Vector2(size.x - INSET - 8, body_top + 20), Companies.INK_SOFT, 1.0)
	# Art window: the only area a custom design may replace.
	var art := Rect2(INSET + 10, body_top + 26, size.x - INSET * 2 - 20, 46)
	draw_rect(art, color.lerp(Color.WHITE, 0.82), true)
	draw_rect(art, Companies.INK_SOFT, false, 1.0)
	_draw_icon(art.get_center(), 14.0, color)
	draw_line(Vector2(INSET + 8, size.y - 30), Vector2(size.x - INSET - 8, size.y - 30), Companies.INK_SOFT, 1.0)
	_draw_centered_text("%d shares issued" % int(comp["shares"]), Vector2(size.x / 2.0, size.y - 17), 9, Companies.INK)

	if coins > 0:
		_draw_coin_badge(coins)


func _draw_back() -> void:
	var inner := Rect2(INSET, INSET, size.x - INSET * 2, size.y - INSET * 2)
	match Cosmetics.card_back:
		"back_midnight":
			_draw_back_midnight(inner)
		"back_sunrise":
			_draw_back_sunrise(inner)
		"back_pinstripe":
			_draw_back_pinstripe(inner)
		_:
			_draw_back_classic(inner)


## Six colour stripes, one per company, then the monogram.
func _draw_back_classic(inner: Rect2) -> void:
	draw_rect(inner, Companies.INK, false, 1.5)
	var stripe_w := (inner.size.x - 12) / 6.0
	for i in 6:
		draw_rect(Rect2(inner.position.x + 6 + i * stripe_w, inner.position.y + 8, stripe_w - 2, 10), Companies.color_of(i), true)
		draw_rect(Rect2(inner.position.x + 6 + i * stripe_w, inner.end.y - 18, stripe_w - 2, 10), Companies.color_of(i), true)
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


func _draw_monogram(color: Color) -> void:
	_draw_centered_text("BIG", Vector2(size.x / 2.0, size.y / 2.0 - 14), 22, color)
	_draw_centered_text("BUSINESS", Vector2(size.x / 2.0, size.y / 2.0 + 12), 16, color)


func _draw_icon(center: Vector2, r: float, color: Color) -> void:
	# sun = circle, then triangle, square, hexagon, octagon, pentagon
	var sides: int = [0, 3, 4, 6, 8, 5][company]
	if sides == 0:
		draw_circle(center, r, color)
		return
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides - PI / 2
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)


func _draw_coin_badge(n: int) -> void:
	var c := Vector2(size.x / 2.0, size.y / 2.0 + 16)
	draw_circle(c, 21, Companies.INK)
	draw_circle(c, 18, Companies.BRONZE)
	_draw_centered_text(str(n), c + Vector2(0, 1), 18, Color.WHITE)


func _draw_centered_text(text: String, at: Vector2, px: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	draw_string(font, at + Vector2(-w / 2.0, px / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
