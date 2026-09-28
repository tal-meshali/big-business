class_name CardView
extends Button
## A share card. Draws its own face from company data so no art assets are
## needed for the spike. Portrait 5:7.

signal card_pressed(card_id: int)

const W := 120.0
const H := 168.0

var card_id: int = -1
var company: int = 0
var coins: int = 0
var face_up: bool = true
var selectable: bool = true:
	set(value):
		selectable = value
		disabled = not value
		modulate = Color(1, 1, 1, 1) if value else Color(0.75, 0.75, 0.75, 1)
var selected: bool = false:
	set(value):
		if selected == value:
			return
		selected = value
		var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(self, "position:y", _rest_y - (18.0 if value else 0.0), 0.18)
		queue_redraw()
var _rest_y: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(W, H)
	flat = true
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void: card_pressed.emit(card_id))


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
	var radius := 12
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(radius)
	if not face_up:
		style.bg_color = Color("#1E2A44")
		style.border_color = Color("#F2C14E")
		style.set_border_width_all(2)
		draw_style_box(style, rect)
		_draw_centered_text("BB", size / 2.0, 36, Color("#F2C14E"))
		return

	var color := Companies.color_of(company)
	style.bg_color = Companies.CARD_FACE
	style.border_color = Companies.GOLD if selected else color
	style.set_border_width_all(4 if selected else 3)
	if selected:
		style.shadow_color = Color(Companies.GOLD, 0.45)
		style.shadow_size = 10
	draw_style_box(style, rect)

	# Corner cluster: share count + icon.
	var comp := Companies.get_company(company)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(10, 30), str(comp["shares"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)
	_draw_icon(Vector2(size.x - 24, 22), 12.0, color)
	# Art window (the only area a custom design may replace).
	var art := Rect2(10, 42, size.x - 20, size.y - 84)
	draw_rect(art, color.lerp(Color.WHITE, 0.8), true)
	# Name band.
	var band := Rect2(0, size.y - 38, size.x, 38)
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = color
	band_style.corner_radius_bottom_left = radius
	band_style.corner_radius_bottom_right = radius
	draw_style_box(band_style, band)
	_draw_centered_text(Companies.short_name_of(company), Vector2(size.x / 2.0, size.y - 14), 16, Color.WHITE)

	if coins > 0:
		_draw_coin_badge(coins)


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
	var c := Vector2(size.x / 2.0, size.y / 2.0 - 8)
	draw_circle(c, 22, Color(0, 0, 0, 0.35))
	draw_circle(c, 18, Companies.BRONZE)
	_draw_centered_text(str(n), c + Vector2(0, 1), 18, Color.WHITE)


func _draw_centered_text(text: String, at: Vector2, px: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
	draw_string(font, at + Vector2(-w / 2.0, px / 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
