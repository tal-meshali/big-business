class_name TableSurface
extends Control
## The tilted table from the design canvas, drawn in 2D with a real
## perspective projection: a stadium-shaped felt with a rim and two stacked
## edge layers below it, dashed zones for the Market, the supply and your
## Portfolio, and their labels. Other nodes place cards on the table through
## `project()` and `factor()`, so the whole scene shares one camera.
##
## Table coordinates (u, v) are design px on the plane, origin at the plane's
## centre, v growing toward the viewer; z is height above the felt. The
## design plane is 380 x 620 design px, tilted TILT degrees, seen from
## DIST design px.

const PLANE_W := 380.0
const PLANE_H := 620.0
const TILT_DEG := 32.0
const DIST := 900.0
const ZONES := {
	"market": Rect2(-145, -92, 290, 150),
	"supply": Rect2(-30, -178, 60, 78),
	"portfolio": Rect2(-145, 62, 290, 82),
}
const LABELS := {
	"market": ["THE MARKET", Vector2(-145, -110)],
	"portfolio": ["YOUR PORTFOLIO", Vector2(-145, 150)],
}

## Design px on the plane -> px on screen at zero depth (set by the owner).
var k: float = 1.0
## Screen position (local) of the plane's centre.
var center: Vector2 = Vector2.ZERO
## Felt and rim colours (from Cosmetics; kept as properties for tests).
var felt: Color = Companies.TABLE_BG
var rim: Color = Companies.TABLE_EDGE
## Text after the dot in the supply label.
var supply_count: int = 0
var _glow: Dictionary = {}
var _time: float = 0.0
var _cos := cos(deg_to_rad(TILT_DEG))
var _sin := sin(deg_to_rad(TILT_DEG))


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _glow.values().has(true):
		_time += delta
		queue_redraw()


## Perspective factor at plane depth v and height z (1 at the centre).
func factor(v: float, z: float = 0.0) -> float:
	var depth := v * _sin + z * _cos
	return DIST / maxf(DIST - depth, 1.0)


## Screen position (local px) of the table point (u, v) at height z.
func project(u: float, v: float, z: float = 0.0) -> Vector2:
	var f := factor(v, z)
	var y3 := v * _cos - z * _sin
	return center + Vector2(u * f, y3 * f) * k


## Vertical squash of something lying flat on the felt.
func squash() -> float:
	return _cos


## Light up (or dim) a zone.
func set_glow(zone: String, on: bool) -> void:
	if bool(_glow.get(zone, false)) == on:
		return
	_glow[zone] = on
	queue_redraw()


## Screen bounding box (local px) of a zone, for spotlights and hit areas.
func zone_rect(zone: String) -> Rect2:
	var r: Rect2 = ZONES.get(zone, Rect2())
	var pts := [project(r.position.x, r.position.y), project(r.end.x, r.position.y), project(r.position.x, r.end.y), project(r.end.x, r.end.y)]
	var out := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		out = out.expand(p)
	return out


func set_colors(p_felt: Color, p_rim: Color) -> void:
	felt = p_felt
	rim = p_rim
	queue_redraw()


func _draw() -> void:
	var half := Vector2(PLANE_W / 2.0, PLANE_H / 2.0)
	var radius := PLANE_W / 2.0
	# Drop shadow, then the two edge layers below the felt, then the felt.
	var shadow := _stadium(half, radius, -15.0, Vector2(0, 30))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(_stadium(half, radius, -15.0), rim.darkened(0.4))
	draw_colored_polygon(_stadium(half, radius, -7.0), rim.darkened(0.15))
	var outer := _stadium(half, radius, 0.0)
	draw_colored_polygon(outer, rim)
	draw_colored_polygon(_stadium(half - Vector2(14, 14), radius - 14, 0.0), felt)
	# Soft highlight toward the centre, like the design's radial gradient.
	draw_colored_polygon(_stadium(half - Vector2(70, 110), radius - 70, 0.0), Color(felt.lightened(0.12), 0.55))
	draw_colored_polygon(_stadium(half - Vector2(130, 210), radius - 130, 0.0), Color(felt.lightened(0.2), 0.45))
	# Ink outline around the rim and a faint inner line.
	var closed := PackedVector2Array(outer)
	closed.append(outer[0])
	draw_polyline(closed, Companies.INK, maxf(1.5, 2.0 * k), true)
	var inner_line := _stadium(half - Vector2(14, 14), radius - 14, 0.0)
	inner_line.append(inner_line[0])
	draw_polyline(inner_line, Color(Companies.INK, 0.35), maxf(1.0, 1.2 * k), true)

	for zone in ZONES:
		_draw_zone(zone, ZONES[zone], bool(_glow.get(zone, false)))
	for zone in LABELS:
		_draw_label(LABELS[zone][0], LABELS[zone][1])
	_draw_label("SUPPLY · %d" % supply_count, Vector2(40, -152))


## A rounded (stadium) outline on the plane, projected. `half` is the half
## size, `r` the corner radius, `z` the height, `shift` a plane offset.
func _stadium(half: Vector2, r: float, z: float, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(half.x - r, -(half.y - r)), Vector2(half.x - r, half.y - r), Vector2(-(half.x - r), half.y - r), Vector2(-(half.x - r), -(half.y - r))]
	var steps := 14
	for c in 4:
		var start := -PI / 2 + c * PI / 2
		for i in steps + 1:
			var a := start + PI / 2 * i / steps
			var p: Vector2 = corners[c] + Vector2(cos(a), sin(a)) * r + shift
			pts.append(project(p.x, p.y, z))
	return pts


func _draw_zone(name: String, r: Rect2, glow: bool) -> void:
	var half := r.size / 2.0
	var shift := r.get_center()
	var outline := _stadium(half, 14.0, 0.4, shift)
	if glow:
		var pulse := 0.42 + 0.18 * sin(_time * TAU * 0.9)
		draw_colored_polygon(outline, Color(Companies.CARD_FACE, pulse))
		var closed := PackedVector2Array(outline)
		closed.append(outline[0])
		draw_polyline(closed, Companies.INK, maxf(1.5, 2.0 * k), true)
		return
	# Dashed outline: alternate runs of projected perimeter points.
	var dash_len := 4
	var i := 0
	var n := outline.size()
	while i < n:
		var seg := PackedVector2Array()
		for j in dash_len + 1:
			seg.append(outline[(i + j) % n])
		draw_polyline(seg, Color(Companies.INK, 0.32), maxf(1.0, 2.0 * k), true)
		i += dash_len * 2


func _draw_label(text: String, at: Vector2) -> void:
	var pos := project(at.x, at.y, 0.6)
	var f := factor(at.y)
	var px := int(maxf(6.0, 11.0 * k * f))
	draw_string(UiTheme.display(), pos + Vector2(0, px * 0.9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(Companies.INK, 0.72))
