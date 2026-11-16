@tool
class_name GlossBox
extends StyleBox
## A glossy, chunky game button face, after the casual-game look (Clash
## Royale, Brawl Stars): a thick ink outline, a dark lip underneath standing
## in for depth, a face in three toon-shaded bands (light top, base, darker
## bottom) and a soft white streak across the top. Pressed, the face sinks
## into the lip. Built from anti-aliased StyleBoxFlat layers, because
## Godot's flat style box has no gradients and plain polygons have no AA.

## Base colour of the face; the bands are derived from it.
var face := Color("#6A4CF0"):
	set(v):
		face = v
		_dirty = true
		emit_changed()
var outline := Color("#1A1238"):
	set(v):
		outline = v
		_dirty = true
		emit_changed()
var radius := 14.0:
	set(v):
		radius = v
		_dirty = true
		emit_changed()
## Height of the dark lip under the face, px.
var lip := 6.0:
	set(v):
		lip = v
		_dirty = true
		emit_changed()
var border := 3.0:
	set(v):
		border = v
		_dirty = true
		emit_changed()
var pressed := false:
	set(v):
		pressed = v
		_dirty = true
		emit_changed()
## Show the white streak along the top (off for flat tiles).
var shine := true

var _dirty := true
var _layers: Array[StyleBoxFlat] = []


static func make(face_color: Color, r: float, lip_px: float, border_px: float, is_pressed := false) -> GlossBox:
	var g := GlossBox.new()
	g.face = face_color
	g.radius = r
	g.lip = lip_px
	g.border = border_px
	g.pressed = is_pressed
	return g


func _build() -> void:
	_layers.clear()
	var r := int(round(radius))
	# 0: outline and lip, one dark rounded block.
	var shell := StyleBoxFlat.new()
	shell.bg_color = outline
	shell.set_corner_radius_all(r)
	shell.anti_aliasing = true
	_layers.append(shell)
	# 1: the lip's own colour, a darker face peeking under the face.
	var lip_box := StyleBoxFlat.new()
	lip_box.bg_color = face.darkened(0.45)
	lip_box.set_corner_radius_all(maxi(0, r - int(border)))
	lip_box.anti_aliasing = true
	_layers.append(lip_box)
	# 2: bottom band (darker), 3: base band, 4: top band (lighter).
	for c in [face.darkened(0.16), face, face.lightened(0.28)]:
		var band := StyleBoxFlat.new()
		band.bg_color = c
		band.set_corner_radius_all(maxi(0, r - int(border)))
		band.anti_aliasing = true
		_layers.append(band)
	# 5: the streak.
	var streak := StyleBoxFlat.new()
	streak.bg_color = Color(1, 1, 1, 0.5)
	streak.set_corner_radius_all(maxi(2, int(r * 0.6)))
	streak.anti_aliasing = true
	_layers.append(streak)
	_dirty = false


func _draw(ci: RID, rect: Rect2) -> void:
	if _dirty or _layers.is_empty():
		_build()
	var b := border
	var sink := lip - 1.0 if pressed else 0.0
	# The whole block: outline plus lip.
	_layers[0].draw(ci, rect)
	var inner := rect.grow_individual(-b, -b, -b, -b)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return
	_layers[1].draw(ci, inner)
	# The face sits on the lip; pressed, it sinks most of the way down.
	var face_rect := Rect2(inner.position + Vector2(0, sink), Vector2(inner.size.x, inner.size.y - lip))
	if face_rect.size.y <= 2:
		return
	_layers[2].draw(ci, face_rect)
	_layers[3].draw(ci, Rect2(face_rect.position, Vector2(face_rect.size.x, face_rect.size.y * 0.78)))
	_layers[4].draw(ci, Rect2(face_rect.position, Vector2(face_rect.size.x, face_rect.size.y * 0.46)))
	if shine and face_rect.size.y > 18:
		var pad := maxf(4.0, radius * 0.45)
		var h := maxf(2.0, face_rect.size.y * 0.13)
		_layers[5].draw(ci, Rect2(face_rect.position + Vector2(pad, h * 0.6), Vector2(face_rect.size.x - pad * 2.0, h)))


## Content sits on the face: margins grow by the outline, and the lip below.
func _get_minimum_size() -> Vector2:
	return Vector2(radius * 2.0 + border * 2.0, radius * 2.0 + border * 2.0 + lip)
