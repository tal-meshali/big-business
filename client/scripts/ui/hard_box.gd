class_name HardBox
extends StyleBox
## A deed-style box: rounded face with an ink border and a hard offset shadow
## (the design's `box-shadow: 0 3px 0 ink`), drawn as two flat boxes. `lift`
## moves the face down and shortens the shadow for the pressed state.

var bg: Color = Color.WHITE
var border: Color = Color("#1C1C1C")
var border_width: float = 2.0
var radius: float = 10.0
var shadow: float = 3.0
var lift: float = 0.0

var _face := StyleBoxFlat.new()
var _drop := StyleBoxFlat.new()


func _init(p_bg: Color = Color.WHITE, p_radius: float = 10.0, p_shadow: float = 3.0, p_border_width: float = 2.0, p_lift: float = 0.0) -> void:
	bg = p_bg
	radius = p_radius
	shadow = p_shadow
	border_width = p_border_width
	lift = p_lift
	set_content_margin_all(12)


func _sync() -> void:
	_face.bg_color = bg
	_face.border_color = border
	_face.set_border_width_all(int(border_width))
	_face.set_corner_radius_all(int(radius))
	_face.anti_aliasing = true
	_drop.bg_color = border
	_drop.set_corner_radius_all(int(radius))
	_drop.anti_aliasing = true


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	_sync()
	var face_rect := Rect2(rect.position + Vector2(0, lift), rect.size)
	var drop := shadow - lift
	if drop > 0.0:
		_drop.draw(to_canvas_item, Rect2(rect.position + Vector2(0, shadow), rect.size))
	_face.draw(to_canvas_item, face_rect)


func _get_draw_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position, rect.size + Vector2(0, maxf(shadow, lift)))
