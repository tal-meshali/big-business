class_name Glyphs
## Drawn-in-code artwork shared by the cards, plates, coins and the start
## page: the six company silhouettes from docs/design/theme.md, the bronze
## and gold coins, and the tutorial's tapping hand. Everything takes the
## CanvasItem to draw on, a centre and a radius so it scales with its host.


## Company icon at `center`, fitting a circle of radius `r`; `fill` is the
## company colour, `ink` the outline.
static func company_icon(ci: CanvasItem, center: Vector2, r: float, company: int, fill: Color, ink: Color) -> void:
	var w := maxf(1.0, r * 0.14)
	match company:
		0:
			# Sun: disc with eight rays.
			ci.draw_circle(center, r * 0.45, fill)
			ci.draw_arc(center, r * 0.45, 0, TAU, 32, ink, w, true)
			for i in 8:
				var a := TAU * i / 8.0
				var dir := Vector2(cos(a), sin(a))
				ci.draw_line(center + dir * r * 0.62, center + dir * r * 0.95, ink, w)
		1:
			# Pinecone: tall triangle with a spine and two cross lines.
			var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r * 0.72, r * 0.9), center + Vector2(-r * 0.72, r * 0.9)])
			ci.draw_colored_polygon(pts, fill)
			_outline(ci, pts, ink, w)
			ci.draw_line(center + Vector2(0, -r * 0.5), center + Vector2(0, r * 0.9), ink, w)
			ci.draw_line(center + Vector2(-r * 0.32, r * 0.05), center + Vector2(r * 0.32, r * 0.05), ink, w)
			ci.draw_line(center + Vector2(-r * 0.5, r * 0.5), center + Vector2(r * 0.5, r * 0.5), ink, w)
		2:
			# Anchor: ring, shank, crossbar and a curved base.
			ci.draw_circle(center + Vector2(0, -r * 0.7), r * 0.22, fill)
			ci.draw_arc(center + Vector2(0, -r * 0.7), r * 0.22, 0, TAU, 24, ink, w, true)
			ci.draw_line(center + Vector2(0, -r * 0.48), center + Vector2(0, r * 0.95), ink, w * 1.3)
			ci.draw_line(center + Vector2(-r * 0.4, -r * 0.2), center + Vector2(r * 0.4, -r * 0.2), ink, w)
			ci.draw_arc(center + Vector2(0, r * 0.15), r * 0.78, PI * 0.15, PI * 0.85, 24, ink, w * 1.3, true)
		3:
			# Gear: twelve teeth around a disc, with a light hub.
			var pts := PackedVector2Array()
			var teeth := 12
			for i in teeth * 2:
				var a := TAU * i / (teeth * 2.0) - PI / 2
				var rr := r if i % 2 == 0 else r * 0.74
				pts.append(center + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, fill)
			_outline(ci, pts, ink, w * 0.8)
			ci.draw_circle(center, r * 0.3, Color("#FFFDF6"))
			ci.draw_arc(center, r * 0.3, 0, TAU, 24, ink, w * 0.8, true)
		4:
			# Cloud: three bumps on a flat base.
			ci.draw_circle(center + Vector2(-r * 0.4, r * 0.15), r * 0.42, fill)
			ci.draw_circle(center + Vector2(r * 0.05, -r * 0.2), r * 0.55, fill)
			ci.draw_circle(center + Vector2(r * 0.5, r * 0.2), r * 0.38, fill)
			ci.draw_rect(Rect2(center + Vector2(-r * 0.4, r * 0.15), Vector2(r * 0.9, r * 0.42)), fill, true)
			ci.draw_arc(center + Vector2(-r * 0.4, r * 0.15), r * 0.42, PI * 0.5, PI * 1.55, 20, ink, w, true)
			ci.draw_arc(center + Vector2(r * 0.05, -r * 0.2), r * 0.55, PI * 1.1, PI * 1.95, 24, ink, w, true)
			ci.draw_arc(center + Vector2(r * 0.5, r * 0.2), r * 0.38, -PI * 0.4, PI * 0.5, 20, ink, w, true)
			ci.draw_line(center + Vector2(-r * 0.4, r * 0.57), center + Vector2(r * 0.5, r * 0.58), ink, w)
		_:
			# Wheel with a lightning bolt.
			ci.draw_circle(center, r, fill)
			ci.draw_arc(center, r, 0, TAU, 40, ink, w, true)
			ci.draw_circle(center, r * 0.62, Color("#FFFDF6"))
			ci.draw_arc(center, r * 0.62, 0, TAU, 32, ink, w * 0.8, true)
			var bolt := PackedVector2Array([
				center + Vector2(r * 0.12, -r * 0.5), center + Vector2(-r * 0.28, r * 0.06), center + Vector2(0.0, r * 0.06),
				center + Vector2(-r * 0.12, r * 0.5), center + Vector2(r * 0.28, -r * 0.06), center + Vector2(0.0, -r * 0.06),
			])
			ci.draw_colored_polygon(bolt, ink)


static func _outline(ci: CanvasItem, pts: PackedVector2Array, ink: Color, w: float) -> void:
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	ci.draw_polyline(closed, ink, w, true)


## A coin seen from above: shaded disc with an ink rim.
static func coin(ci: CanvasItem, center: Vector2, r: float, gold: bool) -> void:
	var rim := Companies.INK
	var base: Color = Companies.GOLD if gold else Companies.BRONZE
	ci.draw_circle(center, r, rim)
	ci.draw_circle(center, r - maxf(1.0, r * 0.12), base)
	ci.draw_circle(center + Vector2(-r * 0.25, -r * 0.28), r * 0.42, base.lightened(0.28))
	ci.draw_circle(center + Vector2(r * 0.12, r * 0.18), r * 0.5, Color(base.darkened(0.18), 0.55))


## A coin seen edge-on (a chip in a stack): a flat ellipse.
static func coin_disc(ci: CanvasItem, center: Vector2, rx: float, ry: float, gold: bool) -> void:
	var base: Color = Companies.GOLD if gold else Companies.BRONZE
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, base.lightened(0.15))
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	ci.draw_polyline(closed, Companies.INK, maxf(1.0, ry * 0.25), true)


## A loudspeaker; `off` adds a slash instead of the sound waves.
static func speaker(ci: CanvasItem, center: Vector2, r: float, ink: Color, off: bool) -> void:
	var w := maxf(1.5, r * 0.18)
	var body := PackedVector2Array([
		center + Vector2(-r, -r * 0.35), center + Vector2(-r * 0.45, -r * 0.35), center + Vector2(0, -r * 0.85),
		center + Vector2(0, r * 0.85), center + Vector2(-r * 0.45, r * 0.35), center + Vector2(-r, r * 0.35),
	])
	ci.draw_colored_polygon(body, ink)
	if off:
		ci.draw_line(center + Vector2(r * 0.25, -r * 0.45), center + Vector2(r * 0.95, r * 0.45), ink, w)
		ci.draw_line(center + Vector2(r * 0.95, -r * 0.45), center + Vector2(r * 0.25, r * 0.45), ink, w)
	else:
		ci.draw_arc(center, r * 0.5, -PI * 0.3, PI * 0.3, 12, ink, w, true)
		ci.draw_arc(center, r * 0.9, -PI * 0.3, PI * 0.3, 16, ink, w, true)


## A pointing hand, used by the coach's hint row.
static func tap_hand(ci: CanvasItem, center: Vector2, r: float, ink: Color) -> void:
	var w := maxf(1.5, r * 0.16)
	# Palm.
	var palm := Rect2(center + Vector2(-r * 0.55, -r * 0.1), Vector2(r * 1.1, r * 0.9))
	ci.draw_rect(palm, Color("#FFFDF6"), true)
	ci.draw_rect(palm, ink, false, w)
	# Index finger raised.
	var finger := Rect2(center + Vector2(-r * 0.25, -r * 0.95), Vector2(r * 0.34, r * 0.95))
	ci.draw_rect(finger, Color("#FFFDF6"), true)
	ci.draw_rect(finger, ink, false, w)
	# Three folded knuckles.
	for i in 3:
		var x := -r * 0.55 + r * 0.37 * i
		ci.draw_line(center + Vector2(x + r * 0.37, -r * 0.1), center + Vector2(x + r * 0.37, r * 0.35), ink, w * 0.8)
