class_name GameIcons
## Small vector icons for the lobby (dock tabs, gift, trophy), drawn with
## CanvasItem calls in white with an ink outline so they read on any
## glossy tile. `k` is the icon's half-size in px.

const INK := Color("#1A1238")


static func draw(ci: CanvasItem, kind: String, c: Vector2, k: float, fill := Color.WHITE) -> void:
	var o := maxf(2.0, k * 0.16)
	match kind:
		"check":
			# A mint disc with a white tick: something done or collected.
			ci.draw_circle(c, k, INK, true, -1.0, true)
			ci.draw_circle(c, k - o, UiTheme.MINT, true, -1.0, true)
			var tick := PackedVector2Array([c + Vector2(-k * 0.42, k * 0.02), c + Vector2(-k * 0.1, k * 0.34), c + Vector2(k * 0.44, -k * 0.3)])
			ci.draw_polyline(tick, Color.WHITE, o * 1.5, true)
		"star":
			_star(ci, c, k, UiTheme.GOLD if fill == Color.WHITE else fill, o)
		"coin":
			coin_face(ci, c, k, Color("#B8722E"), o)
		"friends":
			_person(ci, c + Vector2(k * 0.38, -k * 0.05), k * 0.78, fill.darkened(0.15), o)
			_person(ci, c + Vector2(-k * 0.28, k * 0.05), k * 0.9, fill, o)
		"quests":
			var r := Rect2(c - Vector2(k * 0.7, k * 0.9), Vector2(k * 1.4, k * 1.8))
			_rect(ci, r, fill, o, k * 0.18)
			for i in 3:
				var y := r.position.y + k * (0.45 + i * 0.5)
				_check(ci, Vector2(r.position.x + k * 0.38, y), k * 0.2, UiTheme.MINT, o * 0.7)
				ci.draw_line(Vector2(r.position.x + k * 0.72, y), Vector2(r.end.x - k * 0.25, y), INK, o * 0.8, true)
		"shop":
			var body := PackedVector2Array([c + Vector2(-k * 0.85, -k * 0.35), c + Vector2(k * 0.85, -k * 0.35), c + Vector2(k * 0.7, k * 0.9), c + Vector2(-k * 0.7, k * 0.9)])
			ci.draw_arc(c + Vector2(0, -k * 0.35), k * 0.45, PI, TAU, 16, INK, o * 2.2, true)
			ci.draw_arc(c + Vector2(0, -k * 0.35), k * 0.45, PI, TAU, 16, fill, o * 0.9, true)
			_poly(ci, body, fill, o)
			_coin(ci, c + Vector2(0, k * 0.3), k * 0.32, o * 0.7)
		"clubs":
			var shield := PackedVector2Array([c + Vector2(-k * 0.8, -k * 0.85), c + Vector2(k * 0.8, -k * 0.85), c + Vector2(k * 0.8, k * 0.05), c + Vector2(0, k * 0.95), c + Vector2(-k * 0.8, k * 0.05)])
			_poly(ci, shield, fill, o)
			var half := PackedVector2Array([c + Vector2(0, -k * 0.85), c + Vector2(k * 0.8, -k * 0.85), c + Vector2(k * 0.8, k * 0.05), c + Vector2(0, k * 0.95)])
			ci.draw_colored_polygon(half, UiTheme.BADGE)
			ci.draw_polyline(_closed(shield), INK, o, true)
			_star(ci, c + Vector2(0, -k * 0.05), k * 0.38, UiTheme.GOLD, o * 0.6)
		"more":
			for i in 3:
				var p := c + Vector2((i - 1) * k * 0.7, 0)
				ci.draw_circle(p, k * 0.28, INK)
				ci.draw_circle(p, k * 0.28 - o * 0.6, fill)
		"gift":
			var box := Rect2(c + Vector2(-k * 0.8, -k * 0.2), Vector2(k * 1.6, k * 1.05))
			var lid := Rect2(c + Vector2(-k * 0.92, -k * 0.55), Vector2(k * 1.84, k * 0.42))
			for loop in [-1, 1]:
				ci.draw_circle(c + Vector2(loop * k * 0.3, -k * 0.72), k * 0.28, INK)
				ci.draw_circle(c + Vector2(loop * k * 0.3, -k * 0.72), k * 0.28 - o, UiTheme.BADGE)
			_rect(ci, box, UiTheme.GOLD, o, k * 0.1)
			_rect(ci, lid, UiTheme.GOLD.lightened(0.2), o, k * 0.1)
			ci.draw_rect(Rect2(c.x - k * 0.16, lid.position.y + o, k * 0.32, box.end.y - lid.position.y - o * 2), UiTheme.BADGE)
		"trophy":
			var cup := PackedVector2Array([c + Vector2(-k * 0.7, -k * 0.85), c + Vector2(k * 0.7, -k * 0.85), c + Vector2(k * 0.5, -k * 0.05), c + Vector2(k * 0.15, k * 0.25), c + Vector2(-k * 0.15, k * 0.25), c + Vector2(-k * 0.5, -k * 0.05)])
			for side in [-1, 1]:
				ci.draw_arc(c + Vector2(side * k * 0.68, -k * 0.45), k * 0.28, 0, TAU, 16, INK, o * 2.4, true)
				ci.draw_arc(c + Vector2(side * k * 0.68, -k * 0.45), k * 0.28, 0, TAU, 16, UiTheme.GOLD, o, true)
			_poly(ci, cup, UiTheme.GOLD, o)
			_rect(ci, Rect2(c + Vector2(-k * 0.12, k * 0.2), Vector2(k * 0.24, k * 0.4)), UiTheme.GOLD_DEEP, o * 0.7, 0)
			_rect(ci, Rect2(c + Vector2(-k * 0.55, k * 0.55), Vector2(k * 1.1, k * 0.35)), UiTheme.GOLD_DEEP, o, k * 0.08)
		"play":
			var tri := PackedVector2Array([c + Vector2(-k * 0.5, -k * 0.75), c + Vector2(k * 0.8, 0), c + Vector2(-k * 0.5, k * 0.75)])
			_poly(ci, tri, fill, o)
		"cards":
			# Two shares, the back one tilted: the Market.
			for i in 2:
				var at := c + Vector2((i - 0.5) * k * 0.62, (0.5 - i) * k * 0.14)
				var r := Rect2(at - Vector2(k * 0.6, k * 0.85), Vector2(k * 1.2, k * 1.7))
				_rect(ci, r, fill if i == 1 else fill.darkened(0.18), o, k * 0.18)
				ci.draw_rect(Rect2(r.position + Vector2(o, o), Vector2(r.size.x - o * 2.0, k * 0.42)), Companies.DATA[5 - i * 3]["color"])
				ci.draw_line(r.position + Vector2(o, k * 0.42 + o), r.position + Vector2(r.size.x - o, k * 0.42 + o), INK, o * 0.7, true)
		"seal":
			# The regulator token: a gold seal with an R.
			ci.draw_circle(c + Vector2(0, k * 0.1), k * 0.9, INK)
			ci.draw_circle(c, k * 0.9, INK)
			ci.draw_circle(c, k * 0.9 - o, UiTheme.GOLD)
			ci.draw_arc(c, k * 0.62, 0, TAU, 24, UiTheme.GOLD_DEEP, o * 0.6, true)
			var font := UiTheme.display_font()
			var px := int(k * 1.05)
			var w := font.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			ci.draw_string(font, c + Vector2(-w / 2.0, px * 0.36), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, px, INK)
		"coins":
			# A gold coin on a bronze one: capital.
			coin_face(ci, c + Vector2(-k * 0.28, k * 0.28), k * 0.58, Companies.BRONZE, o)
			coin_face(ci, c + Vector2(k * 0.26, -k * 0.22), k * 0.58, UiTheme.GOLD, o)
		"gear":
			var teeth := PackedVector2Array()
			for i in 32:
				var a := TAU * i / 32.0
				var r := k * (0.92 if (i / 2) % 2 == 0 else 0.68)
				teeth.append(c + Vector2.from_angle(a + PI / 32.0) * r)
			_poly(ci, teeth, fill, o)
			ci.draw_circle(c, k * 0.3, INK)
			ci.draw_circle(c, k * 0.3 - o * 0.8, UiTheme.VIOLET.darkened(0.3))
		"flame":
			var pts := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				var r := k * (0.62 + 0.0 * a)
				var p := Vector2(cos(a) * r * 0.85, sin(a) * r)
				if p.y < 0:
					p.x *= 1.0 + p.y / k * 0.9
					p.y *= 1.6
				pts.append(c + p + Vector2(0, k * 0.25))
			_poly(ci, pts, Color("#FF7A1F"), o)
			var inner := PackedVector2Array()
			for p in pts:
				inner.append(c + Vector2(0, k * 0.45) + (p - c - Vector2(0, k * 0.45)) * 0.5)
			ci.draw_colored_polygon(inner, Color("#FFE27A"))


static func _person(ci: CanvasItem, c: Vector2, k: float, fill: Color, o: float) -> void:
	ci.draw_circle(c + Vector2(0, -k * 0.42), k * 0.36, INK)
	ci.draw_circle(c + Vector2(0, -k * 0.42), k * 0.36 - o, fill)
	var body := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		body.append(c + Vector2(cos(a) * k * 0.62, k * 0.75 + sin(a) * k * 0.75))
	_poly(ci, body, fill, o)


static func _coin(ci: CanvasItem, c: Vector2, r: float, o: float) -> void:
	ci.draw_circle(c, r, INK)
	ci.draw_circle(c, r - o, UiTheme.GOLD)
	ci.draw_circle(c - Vector2(r * 0.2, r * 0.2), r * 0.35, UiTheme.GOLD_PALE)


## A capital coin face (bronze or gold), without a number.
static func coin_face(ci: CanvasItem, c: Vector2, r: float, face: Color, o: float) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.14), r, INK)
	ci.draw_circle(c, r, INK)
	ci.draw_circle(c, r - o, face)
	ci.draw_arc(c, r * 0.66, 0, TAU, 20, face.darkened(0.25), o * 0.6, true)
	ci.draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.22, Color(1, 1, 1, 0.45))


static func _check(ci: CanvasItem, c: Vector2, k: float, color: Color, o: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-k, 0), c + Vector2(-k * 0.2, k * 0.8), c + Vector2(k * 1.1, -k * 0.8)])
	ci.draw_polyline(pts, INK, o * 2.6, true)
	ci.draw_polyline(pts, color, o * 1.2, true)


static func _star(ci: CanvasItem, c: Vector2, r: float, color: Color, o: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	_poly(ci, pts, color, o)


static func _rect(ci: CanvasItem, r: Rect2, fill: Color, o: float, radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(int(ceil(o)))
	box.set_corner_radius_all(int(radius))
	box.anti_aliasing = true
	ci.draw_style_box(box, r)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, o: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(_closed(pts), INK, o, true)


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


## A red notification bubble with a white rim and a count (or "!").
static func badge(ci: CanvasItem, c: Vector2, r: float, text: String, font: Font) -> void:
	ci.draw_circle(c + Vector2(0, r * 0.12), r + 2, INK)
	ci.draw_circle(c, r + 1.5, INK)
	ci.draw_circle(c, r, Color.WHITE)
	ci.draw_circle(c, r - maxf(2.0, r * 0.18), UiTheme.BADGE)
	var sz := int(r * 1.15)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	ci.draw_string(font, c + Vector2(-w / 2.0, sz * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE)
