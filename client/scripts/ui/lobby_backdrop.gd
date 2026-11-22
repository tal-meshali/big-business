class_name LobbyBackdrop
extends Control
## The lobby's room: a royal purple glow, slow gold rays turning behind the
## logo, and a few gold sparkles twinkling and drifting up. All drawn, so
## it scales to any screen and costs no textures.

const RAYS := 16
const RAY_SECONDS := 60.0
const SPARKS := 18

## Centre of the rays, as a fraction of the size.
var center := Vector2(0.5, 0.26)
var _t := 0.0
var _glow: TextureRect
var _sparks: Array[Vector3] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_glow = TextureRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([UiTheme.ROYAL_GLOW, UiTheme.ROYAL, UiTheme.NIGHT])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.fill_to = center + Vector2(0.0, 0.8)
	tex.width = 128
	tex.height = 256
	_glow.texture = tex
	add_child(_glow)
	# The rays draw on a child so they sit above the glow.
	var rays := Control.new()
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.draw.connect(func() -> void: _draw_rays(rays))
	add_child(rays)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in SPARKS:
		# x, phase, speed
		_sparks.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.6, 1.4)))


func _process(delta: float) -> void:
	_t += delta
	for c in get_children():
		c.queue_redraw()


## Gold rays from `c`, `n` thin wedges out to radius `r` turned by `turn`
## radians, fading from `alpha` at the centre to nothing. Also used behind
## the table's get-ready countdown.
static func draw_rays(on: CanvasItem, c: Vector2, r: float, turn: float, n: int, alpha: float) -> void:
	var w := TAU / n * 0.32
	var cols := PackedColorArray([Color(1, 0.84, 0.43, alpha), Color(1, 0.84, 0.43, 0.0), Color(1, 0.84, 0.43, 0.0)])
	for i in n:
		var a := turn + TAU * i / n
		on.draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - w) * r, c + Vector2.from_angle(a + w) * r]), cols)


func _draw_rays(on: Control) -> void:
	draw_rays(on, size * center, size.length(), _t / RAY_SECONDS * TAU, RAYS, 0.22)
	# Sparkles: four-pointed stars that rise, twinkle and fade.
	for sp in _sparks:
		var life := fposmod(_t * 0.06 * sp.z + sp.y, 1.0)
		var p := Vector2(sp.x * size.x + sin(_t * sp.z + sp.y * 9.0) * 10.0, size.y * (1.0 - life))
		var tw := 0.5 + 0.5 * sin(_t * 3.0 * sp.z + sp.y * 20.0)
		var k := size.x / 390.0 * (1.5 + 2.5 * tw)
		var a := sin(life * PI) * 0.8
		var col := Color(1, 0.88, 0.5, a)
		on.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -k * 2), p + Vector2(k * 0.4, 0), p + Vector2(0, k * 2), p + Vector2(-k * 0.4, 0)]), col)
		on.draw_colored_polygon(PackedVector2Array([p + Vector2(-k * 2, 0), p + Vector2(0, -k * 0.4), p + Vector2(k * 2, 0), p + Vector2(0, k * 0.4)]), col)
