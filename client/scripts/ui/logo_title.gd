class_name LogoTitle
extends Control
## The game's wordmark, drawn like a mobile game logo: "BIG" over
## "BUSINESS" in Archivo Black with a toon-shaded gold face (pale top,
## gold middle, deep gold bottom), a thick ink outline and a brown
## extrusion, tilted a few degrees. A glint sweeps across it now and then.
## WHY clipped child layers: Godot draws text in one colour, and a child
## with clip_contents is the cheap way to colour a band of the glyphs.

const TILT_DEG := -3.0
const GLINT_EVERY := 4.0
const GLINT_SECONDS := 0.9

var px := 64.0
## The words, one per line, and each line's size relative to `px`.
var lines: Array = ["BIG", "BUSINESS"]
var sizes: Array = [0.7, 1.0]
## Degrees. WHY: containers reset a child's rotation, so put the logo in a
## plain Control when it sits in one.
var tilt := TILT_DEG
var _t := 0.0
var _font: Font
## Per line: [gold band, pale band, glint] clipped layers.
var _layers: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = UiTheme.display_font()
	custom_minimum_size = Vector2(_width(), _height())
	rotation = deg_to_rad(tilt)
	for i in lines.size():
		var row: Array[Control] = []
		for c in [UiTheme.GOLD, UiTheme.GOLD_PALE, Color(1, 1, 1, 0.9)]:
			var layer := Control.new()
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.clip_contents = true
			var line := i
			var color: Color = c
			layer.draw.connect(func() -> void: _draw_line(layer, line, color))
			add_child(layer)
			row.append(layer)
		_layers.append(row)
	resized.connect(_layout)
	_layout()


func _width() -> float:
	var w := 0.0
	for i in lines.size():
		w = maxf(w, _font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, int(px * sizes[i])).x)
	return w + px * 0.4


func _height() -> float:
	var h := 0.0
	for i in lines.size():
		h += _font.get_ascent(int(px * sizes[i])) + px * 0.06
	return h + px * 0.16


func _line_rect(i: int) -> Rect2:
	var y := px * 0.02
	for k in i:
		y += _font.get_ascent(int(px * sizes[k])) + px * 0.06
	var sz := int(px * sizes[i])
	var w := _font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	return Rect2((size.x - w) / 2.0, y, w, _font.get_ascent(sz))


func _layout() -> void:
	pivot_offset = size / 2.0
	for i in _layers.size():
		var r := _line_rect(i)
		var pad := px * 0.2
		var gold: Control = _layers[i][0]
		gold.position = Vector2(r.position.x - pad, r.position.y - pad)
		gold.size = Vector2(r.size.x + pad * 2.0, pad + r.size.y * 0.74)
		var pale: Control = _layers[i][1]
		pale.position = gold.position
		pale.size = Vector2(gold.size.x, pad + r.size.y * 0.4)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var phase := fposmod(_t, GLINT_EVERY)
	for i in _layers.size():
		var glint: Control = _layers[i][2]
		var r := _line_rect(i)
		if phase > GLINT_SECONDS:
			glint.visible = false
			continue
		glint.visible = true
		var k := phase / GLINT_SECONDS
		glint.size = Vector2(px * 0.3, r.size.y + px * 0.4)
		glint.position = Vector2(r.position.x - px * 0.5 + (r.size.x + px) * k, r.position.y - px * 0.2)
		glint.queue_redraw()


func _baseline(i: int) -> Vector2:
	var r := _line_rect(i)
	return Vector2(r.position.x, r.position.y + r.size.y)


func _draw() -> void:
	var outline := int(px * 0.17)
	var depth := int(px * 0.1)
	for i in lines.size():
		var sz := int(px * sizes[i])
		var base := _baseline(i)
		draw_string_outline(_font, base + Vector2(0, depth + px * 0.06), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, outline, Color(0, 0, 0, 0.3))
		for k in range(depth, 0, -1):
			draw_string_outline(_font, base + Vector2(0, k), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, outline, Color("#5A2600"))
		draw_string_outline(_font, base, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, outline, UiTheme.OUTLINE)
		draw_string(_font, base, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, UiTheme.GOLD_DEEP)


## One clipped band of line `i`'s face in `color`.
func _draw_line(layer: Control, i: int, color: Color) -> void:
	var sz := int(px * sizes[i])
	layer.draw_string(_font, _baseline(i) - layer.position, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, color)
