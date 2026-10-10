class_name StartFan
extends Control
## The start screen's little table: an oval of felt with stacks of coins
## and the six companies' shares fanned above it, swaying and bobbing.
## Tap a share to flip it over. Laid out in design points (`s` px each)
## on a 390 dp wide stage, centred in whatever width it gets.

## Stage height in dp; the title card overlaps the felt's front edge.
const STAGE_H := 274.0
## Pivot of the fan, below the cards, in stage dp.
const FAN_PIVOT := Vector2(195, 250)
const SWAY_SECONDS := 7.0
const BOB_SECONDS := 3.2

var s := 1.85
## The felt follows the picked table skin.
var color := Companies.TABLE_BG:
	set(value):
		color = value
		queue_redraw()
var edge_color := Companies.TABLE_EDGE:
	set(value):
		edge_color = value
		queue_redraw()
## Shrink to the height the parent leaves (the lobby fits one screen);
## `s` then never grows past what it was set to.
var fit := false
var cards: Array[CardView] = []
var _max_s := 1.85
var _flipping := {}
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_max_s = s
	custom_minimum_size = Vector2(0, (STAGE_H * 0.45 if fit else STAGE_H) * s)
	if fit:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		resized.connect(_fit)
	for i in 6:
		var cv := CardView.new()
		cv.setup(-1, i)
		cv.selectable = true
		cv.focus_mode = Control.FOCUS_NONE
		cv.tooltip_text = "%s share. Tap to flip." % Companies.name_of(i)
		cv.pivot_offset = Vector2(CardView.W / 2.0, CardView.H * 1.5)
		cv.scale = Vector2.ONE * _card_scale()
		var index := i
		cv.card_pressed.connect(func(_id: int) -> void: flip(index))
		add_child(cv)
		cards.append(cv)
	_place(0.0)


func _fit() -> void:
	s = minf(_max_s, size.y / STAGE_H)
	for cv in cards:
		if not _flipping.has(cards.find(cv)):
			cv.scale = Vector2.ONE * _card_scale()
	queue_redraw()


func _card_scale() -> float:
	return s * 100.0 / CardView.W


## Turns share `i` over (face up <-> back) with a quick squash.
func flip(i: int) -> void:
	if _flipping.has(i):
		return
	_flipping[i] = true
	var cv := cards[i]
	var k := _card_scale()
	var tw := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cv, "scale:x", 0.0, 0.16)
	tw.tween_callback(func() -> void:
		cv.face_up = not cv.face_up
		cv.queue_redraw())
	tw.tween_property(cv, "scale:x", k, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _flipping.erase(i))


func _process(delta: float) -> void:
	_t += delta
	_place(_t)


## Fan the cards around the pivot, swaying the whole fan and bobbing each
## card on its own beat.
func _place(t: float) -> void:
	var sway := sin(t / SWAY_SECONDS * TAU)
	var origin := _stage_origin()
	for i in cards.size():
		var cv := cards[i]
		var off := i - 2.5
		var bob := -8.0 * (0.5 - 0.5 * cos((t - i * 0.35) / BOB_SECONDS * TAU))
		var pivot := origin + (FAN_PIVOT + Vector2(sway * 8.0, absf(off) * 4.0 + bob)) * s
		cv.position = pivot - cv.pivot_offset
		cv.rotation = deg_to_rad(off * 11.0 + sway * 3.0)


func _stage_origin() -> Vector2:
	# Bottom-aligned, so the title card always overlaps the felt's front edge.
	return Vector2((size.x - 390.0 * s) / 2.0, size.y - STAGE_H * s if fit else 0.0)


func _draw() -> void:
	var o := _stage_origin()
	var c := o + Vector2(195, 246) * s
	var rx := 160.0 * s
	var ry := 42.0 * s
	_ellipse(c + Vector2(0, 16 * s), rx, ry, Color(0, 0, 0, 0.35))
	_ellipse(c + Vector2(0, 7 * s), rx + 2, ry + 2, Companies.INK)
	_ellipse(c + Vector2(0, 5 * s), rx, ry, edge_color.darkened(0.3))
	_ellipse(c, rx + 2, ry + 2, Companies.INK)
	_ellipse(c, rx, ry, edge_color)
	_ellipse(c, rx - 10 * s, ry - 7 * s, color)
	_ellipse(c - Vector2(0, 4 * s), rx * 0.6, ry * 0.5, color.lightened(0.12))
	_coins(o + Vector2(67, 214) * s, 4, false)
	_coins(o + Vector2(103, 232) * s, 2, true)
	_coins(o + Vector2(315, 222) * s, 3, false)


func _ellipse(c: Vector2, rx: float, ry: float, fill: Color) -> void:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, fill)


## A short stack of coins standing on the felt (bottom disc at `base`).
func _coins(base: Vector2, n: int, gold: bool) -> void:
	var face := Companies.GOLD if gold else Companies.BRONZE
	for i in n:
		var c := base - Vector2(0, i * 6.0 * s)
		_ellipse(c + Vector2(0, 2.5 * s), 15 * s, 5 * s, Companies.INK)
		_ellipse(c + Vector2(0, 1.5 * s), 13.5 * s, 4 * s, face.darkened(0.25))
		_ellipse(c, 15 * s, 5 * s, Companies.INK)
		_ellipse(c, 13.5 * s, 3.8 * s, face.lightened(0.15))
