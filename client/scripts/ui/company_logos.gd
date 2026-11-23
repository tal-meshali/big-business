class_name CompanyLogos
## The drawn company logos: the six standard companies' art (sun, pine,
## anchor, gear, cloud, bolt) and the extra ones a Founder may pick for a
## custom company. Each is drawn in a 24-unit box with ink outlines and the
## company colour as fill, so a logo reads at any size and on any band.
## WHY drawn, not pictures: they need no review (anyone may pick them) and
## each has its own silhouette, so colourblind players can still tell the
## six companies at a table apart by shape. Ids must match
## server/src/match/founder.ts LOGOS (Companies.LOGOS on the client).


## Draws `logo` centred on `center`, `box` px wide, filled with `fill`.
static func draw(ci: CanvasItem, logo: String, center: Vector2, box: float, fill: Color) -> void:
	var k := box / 24.0
	var at := func(x: float, y: float) -> Vector2: return center + (Vector2(x, y) - Vector2(12, 12)) * k
	var w := maxf(1.0, 1.6 * k)
	var ink := Companies.INK
	var face := Companies.CARD_FACE
	match logo:
		"sun":
			for ray in [[12, 2, 12, 5], [12, 19, 12, 22], [2, 12, 5, 12], [19, 12, 22, 12], [4.9, 4.9, 7, 7], [17, 17, 19.1, 19.1], [4.9, 19.1, 7, 17], [17, 7, 19.1, 4.9]]:
				ci.draw_line(at.call(ray[0], ray[1]), at.call(ray[2], ray[3]), ink, w, true)
			_disc(ci, at.call(12, 12), 4.5 * k, fill, w)
		"pine":
			_shape(ci, at, [[12, 2], [19, 21], [5, 21]], fill, w)
			for seg in [[8.6, 12, 15.4, 12], [7, 16.5, 17, 16.5], [12, 7, 12, 21]]:
				ci.draw_line(at.call(seg[0], seg[1]), at.call(seg[2], seg[3]), ink, w, true)
		"anchor":
			_disc(ci, at.call(12, 5), 2.3 * k, fill, w * 1.1)
			ci.draw_line(at.call(12, 7.3), at.call(12, 21), ink, w * 1.1, true)
			ci.draw_line(at.call(8, 10.5), at.call(16, 10.5), ink, w * 1.1, true)
			ci.draw_arc(at.call(12, 13.5), 7.5 * k, 0, PI, 24, ink, w * 1.1, true)
		"gear":
			var gear := [[10.4, 2], [13.6, 2], [14.2, 4.6], [16.2, 5.4], [18.5, 4], [20.7, 6.2], [19.3, 8.5], [20.1, 10.5], [22.7, 11.1], [22.7, 14.3], [20.1, 14.9], [19.3, 16.9], [20.7, 19.2], [18.5, 21.4], [16.2, 20], [14.2, 20.8], [13.6, 23.4], [10.4, 23.4], [9.8, 20.8], [7.8, 20], [5.5, 21.4], [3.3, 19.2], [4.7, 16.9], [3.9, 14.9], [2, 13.6], [2, 10.4], [4.6, 9.8], [5.4, 7.8], [4, 5.5], [6.2, 3.3], [8.5, 4.7], [10.5, 3.9]]
			var pts: Array = []
			for p in gear:
				pts.append([p[0], p[1] - 0.7])
			_shape(ci, at, pts, fill, w)
			_disc(ci, at.call(12, 12), 3.4 * k, face, w)
		"cloud":
			# Ink blobs first, then the same blobs in colour, smaller.
			var blobs := [[7.4, 14.2, 4.8], [12.2, 10.6, 5.6], [17.2, 14.6, 4.4]]
			for b in blobs:
				ci.draw_circle(at.call(b[0], b[1]), b[2] * k + w, ink)
			ci.draw_rect(Rect2(at.call(7.4, 14.2) - Vector2(0, w), (Vector2(17.2, 19) - Vector2(7.4, 14.2)) * k + Vector2(0, 2 * w)), ink)
			for b in blobs:
				ci.draw_circle(at.call(b[0], b[1]), b[2] * k, fill)
			ci.draw_rect(Rect2(at.call(7.4, 14.2), (Vector2(17.2, 19) - Vector2(7.4, 14.2)) * k), fill)
		"bolt":
			_disc(ci, at.call(12, 12), 9.5 * k, fill, w)
			_disc(ci, at.call(12, 12), 6.2 * k, face, w)
			ci.draw_colored_polygon(_pts(at, [[13.2, 7.2], [9.4, 12.6], [12.5, 12.6], [11.4, 16.8], [15.2, 11.3], [12.1, 11.3]]), ink)
		"rocket":
			_shape(ci, at, [[8.6, 12], [5, 18.5], [8.6, 17]], fill, w)
			_shape(ci, at, [[15.4, 12], [19, 18.5], [15.4, 17]], fill, w)
			ci.draw_colored_polygon(_pts(at, [[10, 17], [12, 22], [14, 17]]), ink)
			_shape(ci, at, [[12, 1.8], [14.6, 5], [15.4, 9], [15.4, 17.5], [8.6, 17.5], [8.6, 9], [9.4, 5]], fill, w)
			_disc(ci, at.call(12, 9.5), 2.1 * k, face, w)
		"crown":
			_shape(ci, at, [[3.5, 19], [3.5, 8], [8, 12.5], [12, 4.5], [16, 12.5], [20.5, 8], [20.5, 19]], fill, w)
			ci.draw_line(at.call(3.5, 15.5), at.call(20.5, 15.5), ink, w, true)
			for x in [7.5, 12.0, 16.5]:
				ci.draw_circle(at.call(x, 17.3), 1.0 * k, ink)
		"leaf":
			var leaf: Array = []
			for i in 13:
				var t := float(i) / 12.0
				leaf.append([4 + 16 * t, 20 - 16 * t - 5.5 * sin(PI * t)])
			for i in range(11, 0, -1):
				var t := float(i) / 12.0
				leaf.append([4 + 16 * t + 5.5 * sin(PI * t), 20 - 16 * t])
			_shape(ci, at, leaf, fill, w)
			ci.draw_line(at.call(3, 21), at.call(16, 8), ink, w, true)
		"diamond":
			_shape(ci, at, [[7, 4], [17, 4], [21.5, 9.5], [12, 21.5], [2.5, 9.5]], fill, w)
			for seg in [[2.5, 9.5, 21.5, 9.5], [7, 4, 9.6, 9.5], [17, 4, 14.4, 9.5], [9.6, 9.5, 12, 21.5], [14.4, 9.5, 12, 21.5], [12, 4, 9.6, 9.5], [12, 4, 14.4, 9.5]]:
				ci.draw_line(at.call(seg[0], seg[1]), at.call(seg[2], seg[3]), ink, w * 0.8, true)
		"heart":
			var heart: Array = []
			for i in 40:
				var t := TAU * float(i) / 40.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				heart.append([12 + x * 0.6, 11.5 - y * 0.6])
			_shape(ci, at, heart, fill, w)
		"star":
			var star: Array = []
			for i in 10:
				var a := -PI / 2.0 + PI * float(i) / 5.0
				var r := 10.5 if i % 2 == 0 else 4.4
				star.append([12 + r * cos(a), 12.8 + r * sin(a)])
			_shape(ci, at, star, fill, w)
		"chart":
			# Three rising bars on a base line, with an arrow over them.
			for bar in [[3.5, 15, 7.5], [9.5, 11, 13.5], [15.5, 7, 19.5]]:
				_shape(ci, at, [[bar[0], 20.5], [bar[0], bar[1]], [bar[2], bar[1]], [bar[2], 20.5]], fill, w)
			ci.draw_line(at.call(2, 20.5), at.call(22, 20.5), ink, w * 1.2, true)
			ci.draw_polyline(_pts(at, [[3, 10.5], [9, 6.5], [12.5, 8], [19.5, 2.8]]), ink, w * 1.1, true)
			ci.draw_colored_polygon(_pts(at, [[21.5, 1.5], [16.6, 2.4], [19.9, 5.6]]), ink)
		"flame":
			var flame: Array = []
			for i in 25:
				var t := TAU * float(i) / 24.0
				# A teardrop pointing up: round bottom, narrow tip.
				var r := 7.0
				flame.append([12 + r * sin(t) * (1.0 - 0.45 * (1.0 + cos(t)) / 2.0), 14 - r * cos(t) * (1.55 if cos(t) > 0 else 1.0)])
			_shape(ci, at, flame, fill, w)
			var inner: Array = []
			for i in 25:
				var t := TAU * float(i) / 24.0
				var r := 3.0
				inner.append([12 + r * sin(t) * (1.0 - 0.45 * (1.0 + cos(t)) / 2.0), 17.2 - r * cos(t) * (1.55 if cos(t) > 0 else 1.0)])
			_shape(ci, at, inner, face, w * 0.8)
		"key":
			_shape(ci, at, [[11, 10.5], [21.5, 10.5], [21.5, 13.5], [20, 13.5], [20, 16.5], [17.6, 16.5], [17.6, 13.5], [16, 13.5], [16, 15.5], [13.8, 15.5], [13.8, 13.5], [11, 13.5]], fill, w)
			_disc(ci, at.call(7.5, 12), 5.2 * k, fill, w)
			_disc(ci, at.call(7.5, 12), 1.9 * k, face, w)
		"mountain":
			_shape(ci, at, [[2, 20.5], [9, 6], [12.6, 12.5], [15.6, 8.5], [22, 20.5]], fill, w)
			_shape(ci, at, [[9, 6], [11.2, 10], [10, 9.2], [9, 10.2], [8, 9.3], [7.07, 10]], face, w * 0.8)
		"cup":
			ci.draw_arc(at.call(17.2, 12.6), 3.4 * k, -PI / 2.0, PI / 2.0, 16, ink, w * 1.6, true)
			_shape(ci, at, [[4, 8], [18, 8], [16.4, 20], [5.6, 20]], fill, w)
			for x in [8.0, 11.0, 14.0]:
				ci.draw_line(at.call(x, 2.5), at.call(x, 5.5), ink, w, true)
		"globe":
			_disc(ci, at.call(12, 12), 9.8 * k, fill, w)
			var ell := PackedVector2Array()
			for i in 33:
				var t := TAU * float(i) / 32.0
				ell.append(at.call(12 + 4.2 * cos(t), 12 + 9.8 * sin(t)))
			ci.draw_polyline(ell, ink, w * 0.8, true)
			ci.draw_line(at.call(2.2, 12), at.call(21.8, 12), ink, w * 0.8, true)
			ci.draw_line(at.call(12, 2.2), at.call(12, 21.8), ink, w * 0.8, true)
			ci.draw_line(at.call(4, 7), at.call(20, 7), ink, w * 0.8, true)
			ci.draw_line(at.call(4, 17), at.call(20, 17), ink, w * 0.8, true)


## A logo picture (Founder upload) in a round frame `box` px wide, with an
## ink ring, centred on `center`.
static func draw_picture(ci: CanvasItem, tex: Texture2D, center: Vector2, box: float) -> void:
	var r := box / 2.0
	ci.draw_circle(center, r + 1.5, Companies.INK)
	# WHY a polygon with UVs: Godot draws a texture only into rectangles or
	# polygons, and a round logo needs the polygon to clip the corners.
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		var d := Vector2(cos(a), sin(a))
		pts.append(center + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	ci.draw_colored_polygon(pts, Color.WHITE, uvs, tex)


static func _pts(at: Callable, points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(at.call(p[0], p[1]))
	return out


static func _shape(ci: CanvasItem, at: Callable, points: Array, fill: Color, width: float) -> void:
	var pts := _pts(at, points)
	ci.draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	ci.draw_polyline(pts, Companies.INK, width, true)


static func _disc(ci: CanvasItem, c: Vector2, r: float, fill: Color, width: float) -> void:
	ci.draw_circle(c, r, fill)
	ci.draw_arc(c, r, 0, TAU, 40, Companies.INK, width, true)
