class_name StartStage
extends Control
## The start page's hero, after the design canvas: a small tilted felt with
## a few coin stacks, and a fan of the six company shares floating above it.
## The cards bob gently and flip over when tapped. Drawn in code; sized by
## its width (design 390 px wide, STAGE_H tall).

const STAGE_H := 250.0
const CARD_W := 84.0

## Felt and rim colours (the lobby's Cosmetics felt), kept as properties so
## the lobby can recolour the stage when a felt is picked.
var color: Color = Companies.TABLE_BG
var edge_color: Color = Companies.TABLE_EDGE
var _cards: Array[CardView] = []
var _base: Array[Vector2] = []
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	for i in 6:
		var cv := CardView.new()
		cv.setup(-1, i, 0, true)
		cv.show_ring = false
		cv.selectable = true
		cv.card_pressed.connect(func(_id: int) -> void: cv.flip_to(not cv.face_up))
		add_child(cv)
		_cards.append(cv)
		_base.append(Vector2.ZERO)
	resized.connect(_layout)


func set_colors(felt: Color, rim: Color) -> void:
	color = felt
	edge_color = rim
	queue_redraw()


func _k() -> float:
	return (size.x if size.x > 0 else 720.0) / 390.0


func _layout() -> void:
	var k := _k()
	var w := CARD_W * k
	var h := w * 1.4
	var cx := size.x / 2.0
	for i in _cards.size():
		var cv := _cards[i]
		var off := i - 2.5
		cv.set_card_size(w, h)
		cv.pivot_offset = Vector2(w / 2.0, h * 1.5)
		cv.rotation = deg_to_rad(off * 11.0)
		var top := 16.0 * k + absf(off) * 4.0 * k
		_base[i] = Vector2(cx - w / 2.0, top)
		cv.position = _base[i]
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var k := _k()
	for i in _cards.size():
		var bob := sin((_time - i * 0.35) * TAU / 3.2) * 4.0 * k
		_cards[i].position = _base[i] + Vector2(0, bob - 4.0 * k)


func _draw() -> void:
	var k := _k()
	var c := Vector2(size.x / 2.0, 200.0 * k)
	var rx := 160.0 * k
	var ry := 36.0 * k
	# Shadow, rim, felt, ink outline.
	draw_colored_polygon(_ellipse(c + Vector2(0, 14 * k), rx * 1.02, ry * 1.1), Color(0, 0, 0, 0.35))
	draw_colored_polygon(_ellipse(c, rx, ry), edge_color)
	draw_colored_polygon(_ellipse(c, rx - 10 * k, ry - 8 * k), color)
	draw_colored_polygon(_ellipse(c - Vector2(0, 4 * k), rx * 0.6, ry * 0.5), Color(color.lightened(0.15), 0.6))
	var outline := _ellipse(c, rx, ry)
	outline.append(outline[0])
	draw_polyline(outline, Companies.INK, 2.0 * k, true)
	# Coin stacks.
	_stack(Vector2(c.x - 128 * k, c.y + 4 * k), 4, false, k)
	_stack(Vector2(c.x - 92 * k, c.y + 16 * k), 2, true, k)
	_stack(Vector2(c.x + 120 * k, c.y + 10 * k), 3, false, k)
	Glyphs.coin_disc(self, Vector2(c.x + 120 * k, c.y + 10 * k - 3 * 4 * k), 15 * k, 5 * k, true)


func _stack(base: Vector2, n: int, gold: bool, k: float) -> void:
	for i in n:
		Glyphs.coin_disc(self, base - Vector2(0, i * 4 * k), 15 * k, 5 * k, gold)


func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
